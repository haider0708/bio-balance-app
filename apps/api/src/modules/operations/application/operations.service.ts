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
  DispatchedLine,
  DeliveryRecord,
} from "../domain/contracts";
import { Sale } from "../domain/sale";
import { verifyTicketCode } from "../../../shared/domain/delivery-ticket";
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
      operation.supplierStoreId,
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
        operation.supplierStoreId,
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
  /** Every shipment carries the lots printed on its ticket. A grossiste names the
   * depot lots it ships, and its stock drops at dispatch; BioBalance, whose own
   * stock is not tracked, declares the batch and expiry of what it sends. */
  private async shipFromDepot(
    ledger: Ledger,
    order: { supplierStoreId?: string | null },
    lines: {
      productId: string;
      quantity: number;
      allocations?: {
        lotId?: string;
        batch?: string;
        expiry?: string;
        quantity: number;
      }[];
    }[],
    deliveryId: string,
  ): Promise<DispatchedLine[]> {
    if (!order.supplierStoreId) {
      const today = localDate(new Date(), ledger.scope.timezone);
      return lines.map((line) => {
        const seen = new Set<string>();
        requireRule(
          line.allocations &&
            line.allocations.every((a) => !a.lotId && a.batch && a.expiry) &&
            line.allocations.reduce((sum, a) => sum + a.quantity, 0) ===
              line.quantity,
          "ALLOCATION_MISMATCH",
          "Indiquez le lot et la péremption de chaque quantité expédiée.",
        );
        const allocations = line.allocations!.map((a) => {
          const expiry = expiryDate(a.expiry!);
          requireRule(
            expiry >= today,
            "LOT_EXPIRED",
            "Un lot périmé ne peut pas être expédié.",
            409,
          );
          const key = `${a.batch}|${expiry}`;
          requireRule(
            !seen.has(key),
            "DUPLICATE_LOT",
            "Regroupez les quantités du même lot.",
          );
          seen.add(key);
          return { batch: a.batch!, expiry, quantity: a.quantity };
        });
        return {
          productId: line.productId,
          quantity: line.quantity,
          allocations,
        };
      });
    }
    for (const line of lines)
      requireRule(
        line.allocations &&
          line.allocations.every((a) => a.lotId) &&
          new Set(line.allocations.map((a) => a.lotId)).size ===
            line.allocations.length &&
          line.allocations.reduce((sum, a) => sum + a.quantity, 0) ===
            line.quantity,
        "ALLOCATION_MISMATCH",
        "Choisissez les lots dont les quantités correspondent à la ligne.",
      );
    return ledger.inDepot(order.supplierStoreId, async (depot) => {
      const changeId = randomUUID();
      const today = localDate(new Date(), depot.scope.timezone);
      const wanted = new Map<string, number>();
      for (const line of lines)
        for (const a of line.allocations!)
          wanted.set(a.lotId!, (wanted.get(a.lotId!) ?? 0) + a.quantity);
      const snapshot = new Map<
        string,
        { lotId: string; batch: string; expiry: string }
      >();
      for (const [lotId, quantity] of wanted) {
        const lot = await depot.lot(lotId);
        requireRule(
          lines.some(
            (l) =>
              l.productId === lot.productId &&
              l.allocations!.some((a) => a.lotId === lotId),
          ),
          "LOT_MISMATCH",
          "Le lot ne correspond pas au produit.",
        );
        requireRule(
          lot.expiry.toISOString().slice(0, 10) >= today,
          "LOT_EXPIRED",
          "Un lot périmé ne peut pas être expédié.",
          409,
        );
        requireRule(
          lot.sellable >= quantity,
          "INSUFFICIENT_STOCK",
          "Stock du dépôt insuffisant pour ce lot.",
          409,
        );
        snapshot.set(lotId, {
          lotId,
          batch: lot.batch,
          expiry: lot.expiry.toISOString().slice(0, 10),
        });
        await depot.move(
          lotId,
          -quantity,
          deliveryId,
          changeId,
          "delivery.dispatch",
        );
      }
      await depot.alerts(lines.map((l) => l.productId));
      await depot.touch("delivery.dispatch", deliveryId, changeId);
      return lines.map((line) => ({
        productId: line.productId,
        quantity: line.quantity,
        allocations: line.allocations!.map((a) => ({
          ...snapshot.get(a.lotId!)!,
          quantity: a.quantity,
        })),
      }));
    });
  }
  private async restoreDepotStock(
    ledger: Ledger,
    delivery: {
      id: string;
      sourceStoreId?: string | null;
      lines: DispatchedLine[];
    },
    operationId: string,
  ) {
    if (!delivery.sourceStoreId) return;
    // Goods already on the road return even if the depot was since suspended.
    await ledger.inDepot(
      delivery.sourceStoreId,
      async (depot) => {
        const changeId = randomUUID();
        const products: string[] = [];
        for (const line of delivery.lines)
          for (const a of line.allocations ?? []) {
            if (!a.lotId) continue;
            products.push(line.productId);
            await depot.move(
              a.lotId,
              a.quantity,
              delivery.id,
              changeId,
              "delivery.return",
            );
          }
        await depot.alerts(products);
        await depot.touch("delivery.return", delivery.id, changeId);
        await depot.notify(
          `${operationId}:return`,
          "Livraison retournée",
          "Les quantités retournées ont été remises dans votre stock.",
        );
      },
      { allowInactive: true },
    );
  }
  /** Points for a grossiste follow units the store has confirmed receiving. */
  private async creditDepot(
    ledger: Ledger,
    delivery: { id: string; sourceStoreId?: string | null },
    units: Map<string, number>,
  ) {
    if (!delivery.sourceStoreId || !units.size) return;
    // A store's confirmation never depends on the depot's current status.
    await ledger.inDepot(
      delivery.sourceStoreId,
      async (depot) => {
        const owner = await depot.owner();
        if (!owner) return;
        const changeId = randomUUID();
        let points = 0n;
        for (const [productId, quantity] of units)
          points += BigInt(quantity) * BigInt(await depot.rate(productId));
        if (points > 0n)
          await depot.credit(owner, points, "earned", delivery.id, changeId);
        await depot.touch("points.earned", delivery.id, changeId);
      },
      { allowInactive: true },
    );
  }
  private checkProducts(
    delivery: { lines: { productId: string }[] },
    lines: { productId: string }[],
  ) {
    for (const line of lines)
      requireRule(
        delivery.lines.some((l) => l.productId === line.productId),
        "UNEXPECTED_PRODUCT",
        "Produit absent de cette livraison.",
      );
  }
  /**
   * Books a receipt: the stock enters the store, and the difference with the
   * shipment is settled against the depot. Reached by a confirmed QR scan, or by
   * BioBalance validating a claim.
   */
  private async settleReceipt(
    ledger: Ledger,
    op: Operation,
    delivery: DeliveryRecord,
    lines: {
      productId: string;
      batch: string;
      expiry: string;
      quantity: number;
      condition: "sellable" | "damaged" | "refused";
    }[],
    proof: {
      scanned: boolean;
      note: string;
      manualReason?: string;
      shortfall?: "returned" | "lost";
      validated?: boolean;
      responsibility?: "shipper" | "store" | "carrier" | "none";
    },
  ) {
    const affected = new Set<string>();
    const sum = (condition: string) => {
      const bucket = new Map<string, number>();
      for (const line of lines)
        if (line.condition === condition)
          bucket.set(
            line.productId,
            (bucket.get(line.productId) ?? 0) + line.quantity,
          );
      return bucket;
    };
    const actual = sum("sellable"),
      damaged = sum("damaged"),
      refused = sum("refused");
    const differences = delivery.lines.map((l) => {
      const got =
        (actual.get(l.productId) ?? 0) +
        (damaged.get(l.productId) ?? 0) +
        (refused.get(l.productId) ?? 0);
      return {
        productId: l.productId,
        expected: l.quantity,
        actual: actual.get(l.productId) ?? 0,
        damaged: damaged.get(l.productId) ?? 0,
        refused: refused.get(l.productId) ?? 0,
        surplus: Math.max(0, got - l.quantity),
        missing: Math.max(0, l.quantity - got),
      };
    });
    // A lot the ticket does not list is recorded, never silently accepted.
    const outsideTicket = lines
      .filter((line) => {
        const listed = delivery.lines.find(
          (l) => l.productId === line.productId,
        )?.allocations;
        if (!listed?.length) return false;
        const expiry = expiryDate(line.expiry);
        return !listed.some(
          (a) => a.batch === line.batch && a.expiry === expiry,
        );
      })
      .map((line) => ({
        productId: line.productId,
        batch: line.batch,
        expiry: expiryDate(line.expiry),
      }));
    await ledger.receipt(
      delivery.id,
      lines,
      {
        lines: differences,
        note: proof.note,
        outsideTicket,
        ...(proof.responsibility
          ? { responsibility: proof.responsibility }
          : {}),
      },
      op.operationId,
      { scanned: proof.scanned, manualReason: proof.manualReason },
    );
    // A store that was supplied has no opening stock left to declare.
    await ledger.closeOpening();
    for (const line of lines) {
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
    // What the store got beyond the shipment comes out of the depot; what it did
    // not get goes back there, or is written off. BioBalance's own stock is not tracked.
    if (proof.validated && delivery.sourceStoreId)
      await this.reconcileDepot(
        ledger,
        delivery,
        lines,
        proof.shortfall ?? "returned",
        op.operationId,
        proof.responsibility,
      );
    const prior = await ledger.issue(delivery.id);
    if (prior && prior.status !== "resolved")
      await ledger.saveIssue({
        ...prior,
        status: "resolved",
        heldLines: [],
        resolution: proof.validated ? "validated" : "received",
        resolutionNote: proof.validated
          ? proof.note
          : "Réception complète confirmée.",
        version: prior.version + 1,
      });
    delivery.status = "received";
    delivery.version++;
    await ledger.saveDelivery(delivery);
    const order = await ledger.order(delivery.orderId);
    order.status = Order.status(
      await ledger.fulfillment(order),
      await ledger.hasIssues(order.id),
    );
    order.version++;
    await ledger.saveOrder(order);
    await ledger.alerts([...affected]);
    await this.creditDepot(
      ledger,
      delivery,
      new Map(
        differences
          .map((l) => [l.productId, Math.min(l.actual, l.expected)] as const)
          .filter(([, quantity]) => quantity > 0),
      ),
    );
    await ledger.notify(
      op.operationId,
      proof.validated ? "Réception validée" : "Livraison réceptionnée",
      proof.validated
        ? `BioBalance a retenu les quantités de chaque lot ; elles ont été ajoutées au stock.${
            proof.responsibility
              ? {
                  shipper: " L’écart est imputé à l’expéditeur.",
                  store: " L’écart est imputé au magasin.",
                  carrier: " L’écart est imputé au transport.",
                  none: "",
                }[proof.responsibility]
              : ""
          }${proof.note ? ` « ${proof.note} »` : ""}`
        : "Les quantités reçues ont été ajoutées au stock.",
    );
    return {
      id: delivery.id,
      version: delivery.version,
      status: delivery.status,
      differences,
    };
  }
  /** The quantity BioBalance retains for each shipped lot is the truth for both
   * sides: the store keeps it, and the depot is settled lot by lot — what did not
   * stay at the store goes back to that lot, what stayed beyond it comes out. */
  private async reconcileDepot(
    ledger: Ledger,
    delivery: DeliveryRecord,
    lines: {
      productId: string;
      batch: string;
      expiry: string;
      quantity: number;
      condition: "sellable" | "damaged" | "refused";
    }[],
    shortfall: "returned" | "lost",
    operationId: string,
    responsibility?: "shipper" | "store" | "carrier" | "none",
  ) {
    const moves = delivery.lines.flatMap((l) =>
      (l.allocations ?? [])
        .filter((a) => a.lotId)
        .map((a) => {
          // Refused units stay with the carrier: they are not kept by the store.
          const kept = lines
            .filter(
              (x) =>
                x.productId === l.productId &&
                x.batch === a.batch &&
                expiryDate(x.expiry) === a.expiry &&
                x.condition !== "refused",
            )
            .reduce((n, x) => n + x.quantity, 0);
          return {
            productId: l.productId,
            lotId: a.lotId!,
            missing: Math.max(0, a.quantity - kept),
            surplus: Math.max(0, kept - a.quantity),
          };
        })
        .filter((m) => m.missing > 0 || m.surplus > 0),
    );
    const who = {
      shipper: "l’écart vous est imputé",
      store: "l’écart est imputé au magasin",
      carrier: "l’écart est imputé au transport",
      none: "aucune responsabilité retenue",
    };
    await ledger.inDepot(
      delivery.sourceStoreId!,
      async (depot) => {
        const changeId = randomUUID();
        const touched: string[] = [];
        for (const m of moves) {
          if (m.missing > 0 && shortfall === "returned") {
            await depot.move(
              m.lotId,
              m.missing,
              delivery.id,
              changeId,
              "delivery.return",
            );
            touched.push(m.productId);
          }
          if (m.surplus > 0) {
            const lot = await depot.lot(m.lotId);
            requireRule(
              lot.sellable >= m.surplus,
              "INSUFFICIENT_STOCK",
              "Le dépôt n’a pas assez de stock dans ce lot pour ce complément. Corrigez les quantités.",
              409,
            );
            await depot.move(
              m.lotId,
              -m.surplus,
              delivery.id,
              changeId,
              "delivery.correction",
            );
            touched.push(m.productId);
          }
        }
        if (touched.length) {
          await depot.alerts(touched);
          await depot.touch("delivery.correction", delivery.id, changeId);
        }
        await depot.notify(
          `${operationId}:depot`,
          "Réception validée par BioBalance",
          `Bon ${delivery.ticketNumber} : les quantités retenues s’appliquent à vous et au magasin${touched.length ? ", votre stock a été ajusté" : ""}${responsibility ? ` ; ${who[responsibility]}` : ""}.`,
        );
      },
      { allowInactive: true },
    );
  }
  private async apply(ledger: Ledger, op: Operation): Promise<CommandOutcome> {
    const cmd = op.command,
      actor = ledger.scope.actor,
      affected = new Set<string>();
    // A grossiste acting on an assigned order may only prepare, ship and settle it.
    requireRule(
      !ledger.scope.supplier ||
        [
          "order.prepare",
          "delivery.dispatch",
          "delivery.resolve",
          "delivery.reissue",
        ].includes(cmd.type),
      "FORBIDDEN",
      "Vous n’avez pas accès à cette action.",
      403,
    );
    requireRule(
      !ledger.scope.wholesale ||
        !["sale.create", "sale.correct", "sale.return"].includes(cmd.type),
      "WHOLESALE_NO_SALES",
      "Un grossiste n’enregistre pas de ventes.",
      403,
    );
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
      // A seller sells at the store's price: the one in force on the sale date
      // (or today's, if the price changed before the phone synchronised), or the
      // price already on the line being corrected. Only the responsable and
      // BioBalance may charge something else.
      if (
        !actor.platformAdmin &&
        !ledger.scope.permissions.includes("manage")
      ) {
        const ids = cmd.lines.map((l) => l.productId);
        const onDate = await ledger.listPrices(ids, new Date(cmd.occurredAt));
        const today = await ledger.listPrices(ids, new Date());
        for (const line of cmd.lines) {
          const same = previous?.lines.find((old) => old.id === line.id);
          const allowed = [
            onDate.get(line.productId),
            today.get(line.productId),
          ]
            .filter((v): v is bigint => v !== undefined)
            .map((v) => v.toString());
          if (same) allowed.push(same.unitPriceMillimes);
          requireRule(
            allowed.length > 0,
            "PRICE_NOT_SET",
            "Le prix de ce produit n’est pas défini. Demandez au responsable de le fixer.",
            409,
          );
          requireRule(
            allowed.includes(line.unitPriceMillimes),
            "PRICE_FIXED",
            "Le prix est fixé par le responsable du magasin : un vendeur ne peut pas le modifier.",
            409,
          );
        }
      }
      const lots = new Map();
      const rates = new Map<string, number>();
      for (const line of cmd.lines) {
        rates.set(
          line.productId,
          await ledger.rateAt(line.productId, new Date(cmd.occurredAt)),
        );
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
        new Date(),
        // The store's retail price on the sale date is kept beside the price charged.
        await ledger.listPrices(
          cmd.lines.map((l) => l.productId),
          new Date(cmd.occurredAt),
        ),
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
      // The one chance to declare what is already on the shelves. Afterwards stock
      // only moves by delivery, sale, customer return and BioBalance's decisions.
      requireRule(
        !(await ledger.openingClosed()),
        "OPENING_CLOSED",
        "Le stock de départ a déjà été déclaré. Passez une commande pour recevoir des produits.",
        409,
      );
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
      await ledger.closeOpening();
      await ledger.alerts([...affected]);
      return { id: op.operationId };
    }
    // Damaged or expired goods leave sellable stock at once and wait for BioBalance.
    if (cmd.type === "stock.damage" || cmd.type === "quality.flag") {
      this.allow(ledger, "manage");
      const lot = await ledger.lot(cmd.lotId);
      this.version(lot.version, op.expectedVersion);
      const flagId = cmd.type === "quality.flag" ? cmd.flagId : op.operationId;
      const kind = cmd.type === "quality.flag" ? cmd.kind : "damaged";
      const note =
        (cmd.type === "quality.flag" ? cmd.note : cmd.reason)?.trim() ?? "";
      requireRule(
        lot.sellable >= cmd.quantity,
        "INSUFFICIENT_STOCK",
        "Stock insuffisant pour cette sortie.",
      );
      requireRule(
        kind !== "expired" ||
          lot.expiry.toISOString().slice(0, 10) <
            localDate(new Date(), ledger.scope.timezone),
        "NOT_EXPIRED",
        "Ce lot n’est pas encore périmé.",
      );
      requireRule(
        kind !== "damaged" || note.length >= 3,
        "MISSING_NOTE",
        "Décrivez le dommage constaté.",
      );
      await ledger.move(
        lot.id,
        -cmd.quantity,
        flagId,
        op.operationId,
        note || `Non-conformité : ${kind}`,
      );
      await ledger.move(
        lot.id,
        cmd.quantity,
        flagId,
        op.operationId,
        "damage",
        "damaged",
      );
      const source = await ledger.lotSource(lot.id);
      await ledger.saveFlag({
        id: flagId,
        lotId: lot.id,
        batch: lot.batch,
        expiry: lot.expiry.toISOString().slice(0, 10),
        productId: lot.productId,
        quantity: cmd.quantity,
        kind,
        note: note || null,
        status: "open",
        flaggedBy: actor.id,
        decidedBy: null,
        decidedAt: null,
        decisionNote: null,
        sourceDeliveryId: source?.deliveryId ?? null,
        sourceTicket: source?.ticketNumber ?? null,
        valueMillimes: null,
        operationId: op.operationId,
        version: 1,
      });
      await ledger.alerts([lot.productId]);
      await ledger.notify(
        op.operationId,
        "Produit non conforme à inspecter",
        `${cmd.quantity} unité(s) ${kind === "expired" ? "périmée(s)" : "abîmée(s)"}, lot ${lot.batch}. BioBalance décide de la suite.`,
      );
      return { id: flagId, version: 1 };
    }
    if (cmd.type === "quality.resolve") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Seul BioBalance décide de la suite d’un produit non conforme.",
        403,
      );
      const flag = await ledger.flag(cmd.flagId);
      this.version(flag.version, op.expectedVersion);
      requireRule(
        flag.status === "open",
        "FLAG_DECIDED",
        "Ce signalement a déjà été décidé.",
        409,
      );
      const lot = await ledger.lot(flag.lotId);
      requireRule(
        lot.damaged >= flag.quantity,
        "FLAG_STOCK_CHANGED",
        "Les unités signalées ne sont plus en stock non vendable.",
        409,
      );
      let value: bigint | null = null;
      // BioBalance may confirm only part of what was flagged.
      const confirmed = cmd.quantity ?? flag.quantity;
      requireRule(
        cmd.decision !== "confirm" || confirmed <= flag.quantity,
        "VALIDATION",
        "Vous ne pouvez pas retenir plus d’unités que celles signalées.",
      );
      const releasable =
        flag.kind === "damaged" &&
        lot.expiry.toISOString().slice(0, 10) >=
          localDate(new Date(), ledger.scope.timezone);
      requireRule(
        cmd.decision !== "confirm" || confirmed === flag.quantity || releasable,
        "EXPIRED_NOT_RELEASABLE",
        "Un produit périmé ne peut pas être remis en vente : retenez toutes les unités.",
        409,
      );
      if (cmd.decision === "confirm") {
        // The loss is valued at the price fixed on the delivery the goods came with.
        const source = flag.sourceDeliveryId
          ? await ledger.delivery(flag.sourceDeliveryId).catch(() => null)
          : null;
        const fixed = source?.lines.find(
          (l) => l.productId === flag.productId,
        )?.unitPriceMillimes;
        const price =
          fixed != null
            ? BigInt(fixed)
            : (await ledger.supplyPrices([flag.productId])).get(flag.productId);
        value = price === undefined ? null : price * BigInt(confirmed);
        await ledger.move(
          lot.id,
          -confirmed,
          flag.id,
          op.operationId,
          "quality.writeoff",
          "damaged",
        );
        // The units not retained are sellable again.
        const rest = flag.quantity - confirmed;
        if (rest > 0) {
          await ledger.move(
            lot.id,
            -rest,
            flag.id,
            op.operationId,
            "quality.release",
            "damaged",
          );
          await ledger.move(
            lot.id,
            rest,
            flag.id,
            op.operationId,
            "quality.release",
          );
        }
        if (cmd.responsibility === "shipper" && source?.sourceStoreId)
          await ledger.inDepot(
            source.sourceStoreId,
            (depot) =>
              depot.notify(
                `${op.operationId}:depot`,
                "Non-conformité imputée",
                `${confirmed} unité(s) du lot ${flag.batch} (bon ${source.ticketNumber}) vous sont imputées : ${cmd.note}`,
              ),
            { allowInactive: true },
          );
      } else {
        // An expired product is never put back on sale.
        requireRule(
          flag.kind === "damaged" &&
            lot.expiry.toISOString().slice(0, 10) >=
              localDate(new Date(), ledger.scope.timezone),
          "EXPIRED_NOT_RELEASABLE",
          "Un produit périmé ne peut pas être remis en vente.",
          409,
        );
        await ledger.move(
          lot.id,
          -flag.quantity,
          flag.id,
          op.operationId,
          "quality.release",
          "damaged",
        );
        await ledger.move(
          lot.id,
          flag.quantity,
          flag.id,
          op.operationId,
          "quality.release",
        );
      }
      await ledger.decideFlag({
        ...flag,
        status: cmd.decision === "confirm" ? "confirmed" : "rejected",
        decidedBy: actor.id,
        decidedAt: new Date(),
        decisionNote: cmd.note,
        valueMillimes: value,
        confirmedQuantity: cmd.decision === "confirm" ? confirmed : null,
        responsibility: cmd.responsibility ?? null,
        version: flag.version + 1,
      });
      await ledger.alerts([flag.productId]);
      await ledger.notify(
        op.operationId,
        cmd.decision === "confirm"
          ? "Produit non conforme retiré du stock"
          : "Produit remis en vente",
        cmd.note,
      );
      return {
        id: flag.id,
        version: flag.version + 1,
        status: cmd.decision === "confirm" ? "confirmed" : "rejected",
      };
    }
    if (cmd.type === "order.create") {
      this.allow(ledger, "manage");
      requireRule(
        new Set(cmd.lines.map((l) => l.productId)).size === cmd.lines.length,
        "DUPLICATE_PRODUCT",
        "Produit répété.",
      );
      for (const line of cmd.lines) await ledger.rate(line.productId);
      // The price in force is fixed on the line; a later price change never alters it.
      const prices = await ledger.supplyPrices(
        cmd.lines.map((l) => l.productId),
      );
      const priced = cmd.lines.map((l) => ({
        ...l,
        unitPriceMillimes: prices.get(l.productId)?.toString() ?? null,
      }));
      await ledger.saveOrder({
        id: cmd.orderId,
        lines: priced,
        requestedLines: priced,
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
        // Existing lines keep the price they were ordered at; new products get today's.
        const fresh = await ledger.supplyPrices(
          cmd.lines
            .filter(
              (l) => !order.lines.some((o) => o.productId === l.productId),
            )
            .map((l) => l.productId),
          order.supplierOrganizationId,
        );
        Order.amend(
          order,
          cmd.lines.map((l) => ({
            ...l,
            unitPriceMillimes:
              order.lines.find((o) => o.productId === l.productId)
                ?.unitPriceMillimes ??
              fresh.get(l.productId)?.toString() ??
              null,
          })),
          fulfillment,
        );
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
      (cmd.type === "delivery.receive" &&
        cmd.lines.length === 0 &&
        cmd.ticketCode === undefined)
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
    if (cmd.type === "delivery.refuse") {
      this.allow(ledger, "manage");
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_CLOSED",
        "Cette livraison n’est plus en transit.",
        409,
      );
      const prior = await ledger.issue(delivery.id);
      requireRule(
        !prior || prior.status === "resolved",
        "ISSUE_EXISTS",
        "Un incident est déjà ouvert pour cette livraison. Consultez son suivi.",
        409,
      );
      const reason = `Colis refusé : ${cmd.reason.trim()}`;
      // One issue per delivery: a refusal after an earlier, closed incident reuses it.
      await ledger.saveIssue(
        prior
          ? {
              ...prior,
              status: "open",
              reason,
              heldLines: [],
              resolution: null,
              resolutionNote: null,
              version: prior.version + 1,
            }
          : {
              id: randomUUID(),
              deliveryId: delivery.id,
              orderId: delivery.orderId,
              status: "open",
              reason,
              heldLines: [],
              version: 1,
            },
      );
      // Nothing enters the store; the parcel waits for BioBalance's decision.
      delivery.status = "refused";
      delivery.version++;
      await ledger.saveDelivery(delivery);
      const order = await ledger.order(delivery.orderId);
      order.status = Order.status(await ledger.fulfillment(order), true);
      order.version++;
      await ledger.saveOrder(order);
      await ledger.notify(op.operationId, "Colis refusé à valider", reason);
      if (delivery.sourceStoreId)
        await ledger.inDepot(
          delivery.sourceStoreId,
          (depot) =>
            depot.notify(
              `${op.operationId}:depot`,
              "Colis refusé par le magasin",
              `${reason}. BioBalance va décider de son retour.`,
            ),
          { allowInactive: true },
        );
      return {
        id: delivery.id,
        version: delivery.version,
        orderVersion: order.version,
        status: delivery.status,
      };
    }
    if (cmd.type === "delivery.resolve") {
      const delivery = await ledger.delivery(cmd.deliveryId);
      // BioBalance settles any delivery; a grossiste settles only its own.
      requireRule(
        actor.platformAdmin ||
          (!!ledger.scope.supplier &&
            delivery.sourceStoreId === ledger.scope.supplier.storeId),
        "FORBIDDEN",
        "Action réservée à BioBalance ou au grossiste de cette livraison.",
        403,
      );
      this.version(delivery.version, op.expectedVersion);
      // A grossiste follows its delivery up; only BioBalance decides the outcome.
      requireRule(
        cmd.decision === "tracing" || actor.platformAdmin,
        "FORBIDDEN",
        "Seul BioBalance décide du sort d’une livraison (perdue, retournée ou réglée).",
        403,
      );
      const issue = await ledger.issue(delivery.id);
      requireRule(
        issue && issue.status !== "resolved",
        "ISSUE_CLOSED",
        "Aucun incident ouvert pour cette livraison.",
        409,
      );
      if (cmd.decision === "tracing") issue.status = "in_progress";
      else if (cmd.decision === "reopen") {
        // BioBalance rejects the refusal: the parcel is back in transit and the
        // store must receive it.
        requireRule(
          actor.platformAdmin && delivery.status === "refused",
          "NOT_REFUSED",
          "Seul un colis refusé peut être remis en réception.",
          409,
        );
        delivery.status = "dispatched";
        issue.status = "resolved";
        issue.heldLines = [];
      } else {
        requireRule(
          cmd.decision !== "settled" || delivery.status === "received",
          "RECEIPT_REQUIRED",
          "Une livraison en transit doit être reçue, déclarée perdue ou retournée.",
          409,
        );
        requireRule(
          cmd.decision !== "lost" || delivery.status === "dispatched",
          "DELIVERY_RECEIVED",
          "Un colis refusé est retourné à l’expéditeur, pas déclaré perdu.",
          409,
        );
        requireRule(
          cmd.decision !== "returned" ||
            ["dispatched", "refused"].includes(delivery.status),
          "DELIVERY_RECEIVED",
          "La réception physique existe déjà. Réglez les écarts sans effacer cette réception.",
          409,
        );
        if (cmd.decision === "lost" || cmd.decision === "returned")
          delivery.status = cmd.decision;
        // A return is decided by BioBalance alone, after inspection.
        requireRule(
          cmd.decision !== "returned" || actor.platformAdmin,
          "FORBIDDEN",
          "Seul BioBalance décide d’un retour, après inspection.",
          403,
        );
        // Returned goods go back to the depot's lots; lost goods do not.
        if (cmd.decision === "returned" && delivery.sourceStoreId)
          await this.restoreDepotStock(ledger, delivery, op.operationId);
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
    if (cmd.type === "order.assign") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      requireRule(
        !ledger.scope.wholesale,
        "WHOLESALE_ORDER",
        "Une commande de grossiste est traitée par BioBalance.",
        409,
      );
      const order = await ledger.order(cmd.orderId);
      this.version(order.version, op.expectedVersion);
      Order.editable(order);
      const fulfillment = await ledger.fulfillment(order);
      requireRule(
        ["requested", "preparing"].includes(order.status) &&
          fulfillment.every((l) => l.inTransit === 0 && l.received === 0),
        "ORDER_ASSIGNMENT_CLOSED",
        "Une livraison a déjà commencé : la commande ne peut plus changer de fournisseur.",
        409,
      );
      const supplierBefore = order.supplierOrganizationId ?? null;
      if (cmd.supplierStoreId) {
        const organizationId = await ledger.inDepot(
          cmd.supplierStoreId,
          async (depot) => {
            await depot.notify(
              `${op.operationId}:depot`,
              "Commande à préparer",
              "BioBalance vous a attribué une commande de magasin.",
            );
            return depot.scope.organizationId;
          },
        );
        order.supplierStoreId = cmd.supplierStoreId;
        order.supplierOrganizationId = organizationId;
      } else {
        order.supplierStoreId = null;
        order.supplierOrganizationId = null;
      }
      // The price follows the supplier: a grossiste's own list, or BioBalance's.
      // Nothing has shipped yet, so repricing the lines rewrites no history.
      const changed = supplierBefore !== (order.supplierOrganizationId ?? null);
      const list = changed
        ? await ledger.supplyPrices(
            order.lines.map((l) => l.productId),
            order.supplierOrganizationId,
          )
        : new Map<string, bigint>();
      for (const line of changed ? order.lines : []) {
        const price = list.get(line.productId);
        requireRule(
          price !== undefined || !order.supplierOrganizationId,
          "SUPPLIER_PRICE_MISSING",
          "Ce grossiste n’a pas encore fixé son prix pour un des produits de la commande.",
          409,
        );
        line.unitPriceMillimes = price?.toString() ?? null;
      }
      // The new handler starts from the beginning of the preparation step.
      order.status = "requested";
      order.version++;
      await ledger.saveOrder(order);
      await ledger.notify(
        op.operationId,
        "Fournisseur de la commande",
        cmd.supplierStoreId
          ? "Votre commande sera livrée par un grossiste partenaire."
          : "Votre commande sera livrée par BioBalance.",
      );
      return { id: order.id, version: order.version, status: order.status };
    }
    if (cmd.type === "order.prepare" || cmd.type === "delivery.dispatch") {
      const order = await ledger.order(cmd.orderId);
      // Exactly one party handles an order: BioBalance, or the assigned grossiste.
      requireRule(
        ledger.scope.supplier
          ? order.supplierStoreId === ledger.scope.supplier.storeId
          : actor.platformAdmin && !order.supplierStoreId,
        "FORBIDDEN",
        order.supplierStoreId
          ? "Cette commande est attribuée à un grossiste. Reprenez-la avant de la traiter."
          : "Action réservée à BioBalance.",
        403,
      );
      this.version(order.version, op.expectedVersion);
      Order.editable(order);
      if (cmd.type === "order.prepare") {
        Order.prepare(order, await ledger.fulfillment(order));
        await ledger.notify(
          op.operationId,
          "Commande en préparation",
          order.supplierStoreId
            ? "Le grossiste prépare les produits demandés. La demande ne peut plus être annulée depuis le magasin."
            : "BioBalance prépare les produits demandés. La demande ne peut plus être annulée depuis le magasin.",
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
        const lines = await this.shipFromDepot(
          ledger,
          order,
          cmd.lines,
          cmd.deliveryId,
        );
        await ledger.saveDelivery({
          id: cmd.deliveryId,
          orderId: order.id,
          // Each line carries its lots and the price fixed on the order.
          lines: lines.map((l) => ({
            ...l,
            unitPriceMillimes:
              order.lines.find((o) => o.productId === l.productId)
                ?.unitPriceMillimes ?? null,
          })),
          status: "dispatched",
          version: 1,
          ticketNumber: await ledger.nextTicketNumber(),
          ...(order.supplierStoreId
            ? {
                sourceStoreId: order.supplierStoreId,
                sourceOrganizationId: order.supplierOrganizationId,
              }
            : {}),
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
    if (cmd.type === "delivery.reissue") {
      const delivery = await ledger.delivery(cmd.deliveryId);
      // Only the shipper (BioBalance, or the grossiste that shipped) renews a QR.
      requireRule(
        actor.platformAdmin ||
          (!!ledger.scope.supplier &&
            delivery.sourceStoreId === ledger.scope.supplier.storeId),
        "FORBIDDEN",
        "Seul l’expéditeur peut renouveler le QR de ce bon.",
        403,
      );
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_CLOSED",
        "Ce bon n’est plus en transit.",
        409,
      );
      // Only the QR changes. The delivery keeps its version, so a receiver whose
      // phone has not synced yet can still confirm the physical reception.
      await ledger.renewTicket(delivery.id, (delivery.ticketVersion ?? 1) + 1);
      return { id: delivery.id, version: delivery.version };
    }
    if (cmd.type === "delivery.receive") {
      this.allow(ledger, "manage");
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      requireRule(
        delivery.status === "dispatched",
        "DELIVERY_ALREADY_RECEIVED",
        delivery.status === "pending_review"
          ? "Cette réception attend la validation de BioBalance."
          : "Cette livraison a déjà été réceptionnée.",
        409,
      );
      // The QR is the truth: a valid scan confirms exactly what the ticket lists.
      if (cmd.ticketCode !== undefined) {
        requireRule(
          verifyTicketCode(
            delivery.id,
            delivery.ticketVersion ?? 1,
            cmd.ticketCode,
          ),
          "TICKET_INVALID",
          "Ce QR ne correspond pas à cette livraison ou a été remplacé. Demandez un nouveau bon à l’expéditeur.",
          409,
        );
        // The ticket fixes quantities, lots and dates; the store only reports
        // the state of units it received (damaged) or turned away (refused).
        const reports = cmd.flags ?? [];
        const flagged = (productId: string, batch: string) =>
          reports
            .filter((f) => f.productId === productId && f.batch === batch)
            .reduce(
              (n, f) => ({
                damaged: n.damaged + f.damaged,
                refused: n.refused + f.refused,
              }),
              { damaged: 0, refused: 0 },
            );
        for (const f of reports)
          requireRule(
            delivery.lines.some((l) =>
              (l.allocations ?? []).some(
                (a) => l.productId === f.productId && a.batch === f.batch,
              ),
            ),
            "VALIDATION",
            "Ce signalement ne correspond à aucun lot du bon.",
          );
        const lines = delivery.lines.flatMap((l) =>
          (l.allocations ?? []).flatMap((a) => {
            const { damaged, refused } = flagged(l.productId, a.batch);
            requireRule(
              damaged + refused <= a.quantity,
              "VALIDATION",
              "Plus d’unités signalées que d’unités dans le lot.",
            );
            const base = {
              productId: l.productId,
              batch: a.batch,
              expiry: a.expiry,
            };
            return [
              {
                ...base,
                quantity: a.quantity - damaged - refused,
                condition: "sellable" as const,
              },
              { ...base, quantity: damaged, condition: "damaged" as const },
              { ...base, quantity: refused, condition: "refused" as const },
            ].filter((x) => x.quantity > 0);
          }),
        );
        const reported = reports.some((f) => f.damaged + f.refused > 0);
        requireRule(
          !reported || cmd.note.trim().length >= 3,
          "NOTE_REQUIRED",
          "Expliquez les unités abîmées ou refusées.",
        );
        requireRule(
          lines.length > 0 &&
            delivery.lines.every(
              (l) =>
                (l.allocations ?? []).reduce(
                  (sum, a) => sum + a.quantity,
                  0,
                ) === l.quantity,
            ),
          "TICKET_WITHOUT_LOTS",
          "Ce bon ne liste pas ses lots : indiquez ce que vous avez reçu, BioBalance validera.",
          409,
        );
        if (reported)
          await ledger.notify(
            op.operationId,
            "Unités signalées à la réception",
            `Bon ${delivery.ticketNumber} : ${cmd.note.trim()}`,
          );
        return this.settleReceipt(ledger, op, delivery, lines, {
          scanned: true,
          note: reported ? cmd.note.trim() : "",
        });
      }
      // Without the QR the store only says what it got. Nothing is added to its
      // stock until BioBalance has compared that with what was shipped.
      requireRule(
        (cmd.manualReason ?? "").length >= 3,
        "MANUAL_REASON_REQUIRED",
        "Scannez le QR du colis, ou indiquez pourquoi c’est impossible.",
      );
      this.checkProducts(delivery, cmd.lines);
      delivery.claim = {
        lines: cmd.lines.map((l) => ({
          productId: l.productId,
          batch: l.batch,
          expiry: expiryDate(l.expiry),
          quantity: l.quantity,
          condition: l.condition ?? "sellable",
        })),
        note: cmd.note.trim(),
        manualReason: cmd.manualReason,
        claimedBy: actor.id,
        claimedAt: new Date().toISOString(),
      };
      delivery.status = "pending_review";
      delivery.version++;
      await ledger.saveDelivery(delivery);
      await ledger.notify(
        op.operationId,
        "Réception à valider",
        `Le bon ${delivery.ticketNumber} a été réceptionné sans scan : ${cmd.manualReason}. Comparez et validez.`,
      );
      return {
        id: delivery.id,
        version: delivery.version,
        status: delivery.status,
      };
    }
    if (cmd.type === "delivery.validate") {
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Seul BioBalance valide une réception sans scan.",
        403,
      );
      const delivery = await ledger.delivery(cmd.deliveryId);
      this.version(delivery.version, op.expectedVersion);
      // BioBalance may also settle a parcel on the store's behalf.
      requireRule(
        ["pending_review", "dispatched"].includes(delivery.status),
        "NOTHING_TO_VALIDATE",
        "Cette livraison est déjà réceptionnée ou clôturée.",
        409,
      );
      this.checkProducts(delivery, cmd.lines);
      // A grossiste's shipment is settled on its own lots: the retained lots are
      // the ones on the ticket, corrected if the store named another.
      if (delivery.sourceStoreId)
        for (const line of cmd.lines)
          requireRule(
            delivery.lines.some(
              (l) =>
                l.productId === line.productId &&
                (l.allocations ?? []).some(
                  (a) =>
                    a.batch === line.batch &&
                    a.expiry === expiryDate(line.expiry),
                ),
            ),
            "LOT_NOT_SHIPPED",
            `Le lot ${line.batch} n’est pas sur le bon : retenez les quantités sur les lots expédiés.`,
          );
      return this.settleReceipt(
        ledger,
        op,
        delivery,
        cmd.lines.map((l) => ({ ...l, condition: l.condition ?? "sellable" })),
        {
          scanned: false,
          note: cmd.note,
          responsibility: cmd.responsibility,
          manualReason: (delivery.claim as { manualReason?: string } | null)
            ?.manualReason,
          shortfall: cmd.shortfall,
          validated: true,
        },
      );
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
      // A member may withdraw their own request; handing over or refusing a
      // reward is BioBalance's decision alone.
      if (cmd.decision === "cancelled" && claim.userId === actor.id)
        this.allow(ledger, "sell");
      else
        requireRule(
          actor.platformAdmin,
          "FORBIDDEN",
          "Les récompenses sont traitées par BioBalance.",
          403,
        );
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
