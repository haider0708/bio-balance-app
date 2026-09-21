import { createHash } from "node:crypto";
import { DomainError, requireRule } from "../../../shared/domain/errors";
import { expiryDate, localDate } from "../../../shared/domain/money";
import {
  Actor,
  Operation,
  OperationResult,
  Command,
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
        status: error.status === 409 ? "conflict" : "rejected",
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
  private async apply(
    ledger: Ledger,
    op: Operation,
  ): Promise<Record<string, unknown>> {
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
    if (cmd.type === "order.prepare" || cmd.type === "delivery.dispatch") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const order = await ledger.order(cmd.orderId);
      this.version(order.version, op.expectedVersion);
      requireRule(
        order.status !== "received",
        "ORDER_COMPLETE",
        "Cette commande est déjà réceptionnée.",
        409,
      );
      if (cmd.type === "order.prepare") order.status = "preparing";
      else {
        const delivered = await ledger.deliveries(order.id);
        requireRule(
          new Set(cmd.lines.map((l) => l.productId)).size === cmd.lines.length,
          "DUPLICATE_PRODUCT",
          "Produit répété.",
        );
        for (const line of cmd.lines) {
          const requested =
            order.lines.find((l) => l.productId === line.productId)?.quantity ??
            0;
          const sent = delivered.reduce(
            (sum, d) =>
              sum +
              (d.lines.find((l) => l.productId === line.productId)?.quantity ??
                0),
            0,
          );
          requireRule(
            line.quantity + sent <= requested,
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
        order.status = "dispatched";
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
        version: order.version,
      };
    }
    if (cmd.type === "delivery.receive") {
      this.allow(ledger, "receive");
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_ALREADY_RECEIVED",
        "Cette livraison a déjà été réceptionnée.",
        409,
      );
      const actual = new Map<string, number>();
      for (const line of cmd.lines) {
        requireRule(
          delivery.lines.some((l) => l.productId === line.productId),
          "UNEXPECTED_PRODUCT",
          "Produit absent de cette livraison.",
        );
        actual.set(
          line.productId,
          (actual.get(line.productId) ?? 0) + line.quantity,
        );
      }
      const differences = delivery.lines.map((l) => ({
        productId: l.productId,
        expected: l.quantity,
        actual: actual.get(l.productId) ?? 0,
      }));
      await ledger.receipt(
        delivery.id,
        cmd.lines,
        { lines: differences, note: cmd.note },
        op.operationId,
      );
      for (const line of cmd.lines) {
        await ledger.receive(
          line.productId,
          line.batch,
          expiryDate(line.expiry),
          line.quantity,
          delivery.id,
          op.operationId,
          "delivery.receive",
        );
        affected.add(line.productId);
      }
      delivery.status = "received";
      delivery.version++;
      await ledger.saveDelivery(delivery);
      const order = await ledger.order(delivery.orderId);
      const deliveries = await ledger.deliveries(order.id);
      order.status =
        deliveries.every((d) => d.status === "received") &&
        order.lines.every(
          (l) =>
            deliveries.reduce(
              (sum, d) =>
                sum +
                (d.lines.find((x) => x.productId === l.productId)?.quantity ??
                  0),
              0,
            ) >= l.quantity,
        )
          ? "received"
          : "partial";
      order.version++;
      await ledger.saveOrder(order);
      await ledger.alerts([...affected]);
      await ledger.notify(
        op.operationId,
        "Livraison réceptionnée",
        "Les quantités reçues ont été ajoutées au stock.",
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
          const lots = (await ledger.lotsForProduct(claim.productId)).filter(
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
