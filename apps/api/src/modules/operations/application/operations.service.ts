import { Order } from "../domain/order";
import { createHash, randomUUID } from "node:crypto";
import { DomainError, requireRule } from "../../../shared/domain/errors";
import { expiryDate, localDate } from "../../../shared/domain/money";
import {
  Actor,
  Operation,
  OperationResult,
  CommandOutcome,
  SaleRecord,
} from "../domain/contracts";
import { Sale } from "../domain/sale";
import { Ledger, UnitOfWork } from "./ports";
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object")
    return `{${Object.entries(value)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`)
      .join(",")}}`;
  return JSON.stringify(value);
}
export class OperationsService {
  constructor(private readonly unitOfWork: UnitOfWork) {}
  async status(actor: Actor, operation: Operation) {
    const hash = createHash("sha256")
      .update(canonical(operation))
      .digest("hex");
    return this.unitOfWork.run(
      actor,
      operation.organizationId,
      operation.storeId,
      async (ledger) => {
        const prior = await ledger.prior(operation.operationId, hash);
        // A conservative watermark also covers legacy accepted results, without rewriting them.
        return prior
          ? {
              ...prior,
              committedCursor: prior.committedCursor ?? (await ledger.cursor()),
            }
          : { operationId: operation.operationId, status: "unknown" as const };
      },
    );
  }
  async submit(actor: Actor, operation: Operation): Promise<OperationResult> {
    const hash = createHash("sha256")
      .update(canonical(operation))
      .digest("hex");
    try {
      return await this.unitOfWork.run(
        actor,
        operation.organizationId,
        operation.storeId,
        async (ledger) => {
          const prior = await ledger.prior(operation.operationId, hash);
          if (prior) return prior;
          if (
            !(await ledger.dependenciesAccepted(operation.dependencies ?? []))
          ) {
            return {
              operationId: operation.operationId,
              status: "blocked",
              code: "DEPENDENCY_PENDING",
              message:
                "Une opération précédente doit être synchronisée ou corrigée.",
            };
          }
          const data = await this.apply(ledger, operation);
          const result: OperationResult = {
            operationId: operation.operationId,
            status: "accepted",
            data,
          };
          await ledger.finish(
            operation.operationId,
            hash,
            result,
            operation.command.type,
            String(data.id ?? operation.operationId),
            operation.command,
          );
          return result;
        },
      );
    } catch (error) {
      if (!(error instanceof DomainError)) throw error;
      return {
        operationId: operation.operationId,
        status:
          error.status >= 500 || error.status === 429
            ? "retryable"
            : error.status === 409
              ? "conflict"
              : "rejected",
        code: error.code,
        message: error.message,
      };
    }
  }
  private allow(ledger: Ledger, permission: string) {
    requireRule(
      ledger.scope.actor.platformAdmin ||
        ledger.scope.permissions.includes(permission) ||
        ledger.scope.permissions.includes("manage"),
      "FORBIDDEN",
      "Vous n’avez pas accès à cette action.",
      403,
    );
  }
  private version(actual: number, expected: number | undefined) {
    requireRule(
      expected === actual,
      "VERSION_CONFLICT",
      "Cet élément a été modifié. Consultez la version synchronisée.",
      409,
    );
  }
  private async editableSale(
    ledger: Ledger,
    id: string,
    expected: number | undefined,
  ): Promise<SaleRecord> {
    this.allow(ledger, "sell");
    const sale = await ledger.sale(id);
    requireRule(sale, "NOT_FOUND", "Vente introuvable.", 404);
    requireRule(
      sale.sellerId === ledger.scope.actor.id ||
        ledger.scope.actor.platformAdmin ||
        ledger.scope.permissions.includes("manage"),
      "FORBIDDEN",
      "Vous pouvez corriger uniquement vos propres ventes.",
      403,
    );
    this.version(sale.version, expected);
    return sale;
  }
  private async apply(ledger: Ledger, op: Operation): Promise<CommandOutcome> {
    const cmd = op.command,
      actor = ledger.scope.actor,
      affected = new Set<string>();
    if (cmd.type === "sale.create" || cmd.type === "sale.correct") {
      this.allow(ledger, "sell");
      const previous =
        cmd.type === "sale.correct"
          ? await this.editableSale(ledger, cmd.saleId, op.expectedVersion)
          : undefined;
      requireRule(
        previous || !(await ledger.sale(cmd.saleId)),
        "SALE_EXISTS",
        "Cette vente existe déjà.",
        409,
      );
      const declarations = cmd.batchDeclarations ?? [];
      requireRule(
        new Set(declarations.map((d) => d.lotId)).size === declarations.length,
        "DUPLICATE_LOT",
        "Un lot est déclaré plusieurs fois.",
      );
      for (const declaration of declarations) {
        requireRule(
          cmd.lines.some(
            (line) =>
              line.productId === declaration.productId &&
              line.allocations.some(
                (allocation) => allocation.lotId === declaration.lotId,
              ),
          ),
          "UNUSED_BATCH",
          "Le lot déclaré doit correspondre à un produit de cette vente.",
        );
        await ledger.declareBatch(
          declaration.lotId,
          declaration.productId,
          declaration.batch,
          expiryDate(declaration.expiry),
        );
      }
      const lots = new Map();
      const rates = new Map<string, number>();
      for (const line of cmd.lines) {
        rates.set(line.productId, await ledger.rate(line.productId));
        affected.add(line.productId);
        for (const a of line.allocations)
          lots.set(a.lotId, await ledger.lot(a.lotId));
      }
      const sale = Sale.accept(
        cmd.saleId,
        previous?.sellerId ?? actor.id,
        new Date(cmd.occurredAt),
        cmd.lines,
        rates,
        lots,
        ledger.scope.timezone,
        previous,
      );
      for (const line of previous?.lines ?? []) affected.add(line.productId);
      for (const [lotId, delta] of sale.stockDelta(previous))
        if (delta)
          await ledger.move(lotId, delta, cmd.saleId, op.operationId, cmd.type);
      await ledger.saveSale(
        sale.record,
        previous,
        cmd.type === "sale.correct" ? cmd.reason : "Vente initiale",
        op.operationId,
      );
      await ledger.credit(
        sale.record.sellerId,
        sale.record.earnedPoints - (previous?.earnedPoints ?? 0n),
        "earned",
        cmd.saleId,
        op.operationId,
      );
      await ledger.alerts([...affected]);
      return {
        id: cmd.saleId,
        version: sale.record.version,
        total: {
          currency: "TND",
          millimes: sale.record.totalMillimes.toString(),
        },
        points: sale.record.earnedPoints.toString(),
      };
    }
    if (cmd.type === "sale.return") {
      const old = await this.editableSale(
        ledger,
        cmd.saleId,
        op.expectedVersion,
      );
      const returned = new Sale(old).returnItems(cmd.lines);
      for (const line of cmd.lines) {
        const lot = await ledger.lot(line.lotId);
        affected.add(lot.productId);
        const sellable =
          line.sellable &&
          lot.expiry.toISOString().slice(0, 10) >=
            localDate(new Date(), ledger.scope.timezone);
        await ledger.move(
          lot.id,
          line.quantity,
          cmd.saleId,
          op.operationId,
          "sale.return",
          sellable ? "sellable" : "damaged",
        );
      }
      const next = {
        ...old,
        version: old.version + 1,
        returned: returned.returned,
      };
      await ledger.saveSale(next, old, cmd.reason, op.operationId);
      await ledger.credit(
        old.sellerId,
        returned.points,
        "earned",
        cmd.saleId,
        op.operationId,
      );
      await ledger.alerts([...affected]);
      return { id: cmd.saleId, version: next.version };
    }
    if (cmd.type === "stock.receive") {
      this.allow(ledger, "manage");
      for (const line of cmd.lines) {
        await ledger.receive(
          line.productId,
          line.batch,
          expiryDate(line.expiry),
          line.quantity,
          op.operationId,
          op.operationId,
          cmd.reason,
        );
        affected.add(line.productId);
      }
      await ledger.alerts([...affected]);
      return { id: op.operationId };
    }
    if (cmd.type === "stock.adjust" || cmd.type === "stock.damage") {
      this.allow(ledger, "manage");
      const lot = await ledger.lot(cmd.lotId);
      this.version(lot.version, op.expectedVersion);
      if (cmd.type === "stock.damage") {
        requireRule(
          lot.sellable >= cmd.quantity,
          "INSUFFICIENT_STOCK",
          "Stock insuffisant pour cette sortie.",
        );
        await ledger.move(
          lot.id,
          -cmd.quantity,
          op.operationId,
          op.operationId,
          cmd.reason,
        );
        await ledger.move(
          lot.id,
          cmd.quantity,
          op.operationId,
          op.operationId,
          "damage",
          "damaged",
        );
      } else
        await ledger.move(
          lot.id,
          cmd.quantity - lot.sellable,
          op.operationId,
          op.operationId,
          `adjustment: ${cmd.reason}`,
        );
      await ledger.alerts([lot.productId]);
      return { id: lot.id };
    }
    if (cmd.type === "order.create") {
      this.allow(ledger, "manage");
      requireRule(
        new Set(cmd.lines.map((l) => l.productId)).size === cmd.lines.length,
        "DUPLICATE_PRODUCT",
        "Produit répété.",
      );
      for (const line of cmd.lines) await ledger.rate(line.productId);
      await ledger.saveOrder({
        id: cmd.orderId,
        lines: cmd.lines,
        requestedLines: cmd.lines,
        cancelledLines: [],
        status: "requested",
        version: 1,
      });
      await ledger.notify(
        op.operationId,
        "Nouvelle commande",
        "Une commande de réapprovisionnement est à préparer.",
      );
      return { id: cmd.orderId, version: 1 };
    }
    if (cmd.type === "order.report" || cmd.type === "order.resolve") {
      this.allow(ledger, "manage");
      requireRule(
        cmd.type === "order.report" || actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const order = await ledger.order(cmd.orderId);
      this.version(order.version, op.expectedVersion);
      const active = await ledger.orderProblemActive(order.id);
      requireRule(
        cmd.type === "order.report" ? !active : active,
        active ? "ISSUE_EXISTS" : "ISSUE_CLOSED",
        active
          ? "Un signalement est déjà ouvert. Consultez son suivi."
          : "Aucun signalement ouvert pour cette commande.",
        409,
      );
      await ledger.setOrderProblem(
        order.id,
        cmd.reason,
        cmd.type === "order.report",
      );
      order.version++;
      await ledger.saveOrder(order);
      await ledger.notify(
        op.operationId,
        cmd.type === "order.report"
          ? "Problème sur une commande"
          : "Signalement traité",
        cmd.reason,
      );
      return { id: order.id, version: order.version, status: order.status };
    }
    if (cmd.type === "order.amend" || cmd.type === "order.cancel") {
      this.allow(ledger, "manage");
      requireRule(
        cmd.type === "order.cancel" || actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const order = await ledger.order(cmd.orderId);
      this.version(order.version, op.expectedVersion);
      const fulfillment = await ledger.fulfillment(order);
      if (cmd.type === "order.amend") {
        for (const line of cmd.lines) await ledger.rate(line.productId);
        Order.amend(order, cmd.lines, fulfillment);
      } else if (actor.platformAdmin) Order.cancel(order, fulfillment);
      else Order.cancelRequest(order, fulfillment);
      await ledger.saveOrder(order);
      order.status = Order.status(
        await ledger.fulfillment(order),
        await ledger.hasIssues(order.id),
        order.status,
      );
      await ledger.saveOrder(order);
      await ledger.notify(
        op.operationId,
        cmd.type === "order.amend"
          ? "Commande modifiée"
          : order.status === "cancelled"
            ? "Commande annulée"
            : "Reliquat annulé",
        cmd.reason,
      );
      return { id: order.id, version: order.version, status: order.status };
    }
    if (
      cmd.type === "delivery.report" ||
      (cmd.type === "delivery.receive" && cmd.lines.length === 0)
    ) {
      this.allow(ledger, "manage");
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_CLOSED",
        "Cette livraison n’est plus en transit.",
        409,
      );
      const reason =
        cmd.type === "delivery.report" ? cmd.reason : cmd.note.trim();
      requireRule(
        reason.length >= 3,
        "MISSING_DELIVERY_REASON",
        "Indiquez pourquoi la livraison n’a pas été reçue.",
      );
      const prior = await ledger.issue(delivery.id);
      requireRule(
        !prior,
        "ISSUE_EXISTS",
        "Un incident existe déjà pour cette livraison. Consultez son suivi.",
        409,
      );
      await ledger.saveIssue({
        id: randomUUID(),
        deliveryId: delivery.id,
        orderId: delivery.orderId,
        status: "open",
        reason,
        heldLines: [],
        version: 1,
      });
      delivery.version++;
      await ledger.saveDelivery(delivery);
      await ledger.notify(op.operationId, "Livraison non reçue", reason);
      return { id: delivery.id, version: delivery.version, status: "reported" };
    }
    if (cmd.type === "delivery.resolve") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      const issue = await ledger.issue(delivery.id);
      requireRule(
        issue && issue.status !== "resolved",
        "ISSUE_CLOSED",
        "Aucun incident ouvert pour cette livraison.",
        409,
      );
      if (cmd.decision === "tracing") issue.status = "in_progress";
      else {
        requireRule(
          cmd.decision !== "settled" || delivery.status === "received",
          "RECEIPT_REQUIRED",
          "Une livraison en transit doit être reçue, déclarée perdue ou retournée.",
          409,
        );
        requireRule(
          !["lost", "returned"].includes(cmd.decision) ||
            delivery.status === "dispatched",
          "DELIVERY_RECEIVED",
          "La réception physique existe déjà. Réglez les écarts sans effacer cette réception.",
          409,
        );
        if (cmd.decision === "lost" || cmd.decision === "returned")
          delivery.status = cmd.decision;
        issue.status = "resolved";
        issue.heldLines = [];
      }
      issue.resolution = cmd.decision;
      issue.resolutionNote = cmd.reason;
      issue.version++;
      await ledger.saveIssue(issue);
      delivery.version++;
      await ledger.saveDelivery(delivery);
      const order = await ledger.order(delivery.orderId);
      order.status = Order.status(
        await ledger.fulfillment(order),
        await ledger.hasIssues(order.id),
      );
      order.version++;
      await ledger.saveOrder(order);
      await ledger.notify(op.operationId, "Suivi de livraison", cmd.reason);
      return {
        id: delivery.id,
        version: delivery.version,
        orderVersion: order.version,
        status: delivery.status,
      };
    }
    if (cmd.type === "order.prepare" || cmd.type === "delivery.dispatch") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const order = await ledger.order(cmd.orderId);
      this.version(order.version, op.expectedVersion);
      Order.editable(order);
      if (cmd.type === "order.prepare") {
        Order.prepare(order, await ledger.fulfillment(order));
        await ledger.notify(
          op.operationId,
          "Commande en préparation",
          "BioBalance prépare les produits demandés. La demande ne peut plus être annulée depuis le magasin.",
        );
      } else {
        const fulfillment = await ledger.fulfillment(order);
        requireRule(
          new Set(cmd.lines.map((l) => l.productId)).size === cmd.lines.length,
          "DUPLICATE_PRODUCT",
          "Produit répété.",
        );
        for (const line of cmd.lines) {
          const remaining =
            fulfillment.find((l) => l.productId === line.productId)
              ?.remainingToDispatch ?? 0;
          requireRule(
            line.quantity <= remaining,
            "DELIVERY_EXCEEDS_ORDER",
            "Quantité supérieure au reste à expédier.",
          );
        }
        await ledger.saveDelivery({
          id: cmd.deliveryId,
          orderId: order.id,
          lines: cmd.lines,
          status: "dispatched",
          version: 1,
        });
        order.status = Order.status(
          await ledger.fulfillment(order),
          await ledger.hasIssues(order.id),
        );
        await ledger.notify(
          op.operationId,
          "Livraison expédiée",
          "Une livraison est en route vers votre magasin.",
        );
      }
      order.version++;
      await ledger.saveOrder(order);
      return {
        id: cmd.type === "delivery.dispatch" ? cmd.deliveryId : order.id,
        version: cmd.type === "delivery.dispatch" ? 1 : order.version,
        orderVersion: order.version,
      };
    }
    if (cmd.type === "delivery.receive") {
      this.allow(ledger, "manage");
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_ALREADY_RECEIVED",
        "Cette livraison a déjà été réceptionnée.",
        409,
      );
      requireRule(
        cmd.lines.length > 0 || cmd.note.trim().length > 0,
        "MISSING_DELIVERY_REASON",
        "Expliquez pourquoi aucune unité n’a été reçue.",
      );
      const actual = new Map<string, number>();
      const damaged = new Map<string, number>();
      const refused = new Map<string, number>();
      for (const line of cmd.lines) {
        requireRule(
          delivery.lines.some((l) => l.productId === line.productId),
          "UNEXPECTED_PRODUCT",
          "Produit absent de cette livraison.",
        );
        const bucket =
          line.condition === "damaged"
            ? damaged
            : line.condition === "refused"
              ? refused
              : actual;
        bucket.set(
          line.productId,
          (bucket.get(line.productId) ?? 0) + line.quantity,
        );
      }
      const differences = delivery.lines.map((l) => ({
        productId: l.productId,
        expected: l.quantity,
        actual: actual.get(l.productId) ?? 0,
        damaged: damaged.get(l.productId) ?? 0,
        refused: refused.get(l.productId) ?? 0,
        surplus: Math.max(
          0,
          (actual.get(l.productId) ?? 0) +
            (damaged.get(l.productId) ?? 0) +
            (refused.get(l.productId) ?? 0) -
            l.quantity,
        ),
      }));
      requireRule(
        !differences.some(
          (l) => l.damaged > 0 || l.refused > 0 || l.surplus > 0,
        ) || cmd.note.trim().length >= 3,
        "DELIVERY_DIFFERENCE_REASON",
        "Expliquez les unités abîmées, refusées ou supplémentaires.",
      );
      await ledger.receipt(
        delivery.id,
        cmd.lines,
        { lines: differences, note: cmd.note },
        op.operationId,
      );
      for (const line of cmd.lines) {
        if (line.condition === "refused") continue;
        await ledger.receive(
          line.productId,
          line.batch,
          expiryDate(line.expiry),
          line.quantity,
          delivery.id,
          op.operationId,
          "delivery.receive",
          line.condition === "damaged" ? "damaged" : "sellable",
        );
        affected.add(line.productId);
      }
      delivery.status = "received";
      delivery.version++;
      await ledger.saveDelivery(delivery);
      const priorIssue = await ledger.issue(delivery.id);
      const hasDifferences = differences.some(
        (l) =>
          l.expected !== l.actual ||
          l.damaged > 0 ||
          l.refused > 0 ||
          l.surplus > 0,
      );
      if (hasDifferences) {
        await ledger.saveIssue({
          id: priorIssue?.id ?? randomUUID(),
          deliveryId: delivery.id,
          orderId: delivery.orderId,
          status: "open",
          reason:
            cmd.note.trim() || "Écart entre les quantités expédiées et reçues.",
          heldLines: differences
            .filter((l) => l.expected > l.actual)
            .map((l) => ({
              productId: l.productId,
              quantity: l.expected - l.actual,
            })),
          version: (priorIssue?.version ?? 0) + 1,
        });
      } else if (priorIssue && priorIssue.status !== "resolved") {
        await ledger.saveIssue({
          ...priorIssue,
          status: "resolved",
          heldLines: [],
          resolution: "received",
          resolutionNote: "Réception complète confirmée.",
          version: priorIssue.version + 1,
        });
      }
      const order = await ledger.order(delivery.orderId);
      const fulfillment = await ledger.fulfillment(order);
      order.status = Order.status(
        fulfillment,
        await ledger.hasIssues(order.id),
      );
      order.version++;
      await ledger.saveOrder(order);
      await ledger.alerts([...affected]);
      await ledger.notify(
        op.operationId,
        "Livraison réceptionnée",
        cmd.lines.length
          ? "Les quantités reçues ont été ajoutées au stock."
          : "Le magasin n’a reçu aucune unité. Consultez le motif et préparez le suivi.",
      );
      return { id: delivery.id, version: delivery.version, differences };
    }
    if (cmd.type === "reward.request") {
      this.allow(ledger, "sell");
      const reward = await ledger.reward(cmd.rewardId);
      requireRule(
        reward.active,
        "REWARD_INACTIVE",
        "Cette récompense n’est plus disponible.",
      );
      const points = await ledger.points(actor.id);
      requireRule(
        points.balance - points.reserved >= BigInt(reward.cost),
        "INSUFFICIENT_POINTS",
        "Points disponibles insuffisants.",
      );
      await ledger.reserve(actor.id, BigInt(reward.cost));
      await ledger.saveClaim({
        ...reward,
        id: cmd.claimId,
        rewardId: reward.id,
        userId: actor.id,
        status: "requested",
        version: 1,
      });
      await ledger.notify(
        op.operationId,
        "Récompense demandée",
        `${actor.name} souhaite recevoir ${reward.title}.`,
      );
      return { id: cmd.claimId, version: 1 };
    }
    if (cmd.type === "reward.resolve") {
      const claim = await ledger.claim(cmd.claimId);
      this.version(claim.version, op.expectedVersion);
      if (cmd.decision === "cancelled" && claim.userId === actor.id)
        this.allow(ledger, "sell");
      else this.allow(ledger, "manage");
      requireRule(
        claim.status === "requested",
        "CLAIM_ALREADY_RESOLVED",
        "Cette demande a déjà été traitée.",
        409,
      );
      if (cmd.decision === "fulfilled") {
        const points = await ledger.points(claim.userId);
        requireRule(
          points.balance >= points.reserved,
          "CLAIM_UNAFFORDABLE",
          "Les points ne couvrent plus les réservations. La demande reste en attente.",
          409,
        );
        if (claim.productId) {
          const lots = (
            await ledger.lotsForProduct(claim.productId, claim.quantity)
          ).filter(
            (l) =>
              l.sellable > 0 &&
              l.expiry.toISOString().slice(0, 10) >=
                localDate(new Date(), ledger.scope.timezone),
          );
          requireRule(
            lots.reduce((sum, l) => sum + l.sellable, 0) >= claim.quantity,
            "INSUFFICIENT_STOCK",
            "Stock disponible insuffisant pour remettre ce cadeau.",
            409,
          );
          let remaining = claim.quantity;
          for (const lot of lots) {
            if (!remaining) break;
            const used = Math.min(remaining, lot.sellable);
            if (used)
              await ledger.move(
                lot.id,
                -used,
                claim.id,
                op.operationId,
                "reward",
              );
            remaining -= used;
          }
          await ledger.alerts([claim.productId]);
        }
        await ledger.credit(
          claim.userId,
          -BigInt(claim.cost),
          "redemption",
          claim.id,
          op.operationId,
        );
      }
      await ledger.reserve(claim.userId, -BigInt(claim.cost));
      claim.status = cmd.decision;
      claim.version++;
      await ledger.saveClaim(claim);
      return { id: claim.id, version: claim.version, status: claim.status };
    }
    const exhaustive: never = cmd;
    throw new Error(`Unsupported command ${exhaustive}`);
  }
}
