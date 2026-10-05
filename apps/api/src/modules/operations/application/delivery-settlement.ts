import { randomUUID } from "node:crypto";
import { requireRule } from "../../../shared/domain/errors";
import { expiryDate, localDate } from "../../../shared/domain/money";
import { DeliveryRecord, DispatchedLine, Operation } from "../domain/contracts";
import { Order } from "../domain/order";
import { Ledger } from "./ports";

/**
 * How goods move between a depot and a store: shipping from depot lots, booking
 * a receipt, settling what was refused, returned or corrected, and crediting
 * the grossiste's points. Shared by the scan, claim, validation and refusal paths.
 */
export class DeliverySettlement {
  /** Every shipment carries the lots printed on its ticket. A grossiste names the
   * depot lots it ships, and its stock drops at dispatch; BioBalance, whose own
   * stock is not tracked, declares the batch and expiry of what it sends. */
  async shipFromDepot(
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
  async restoreDepotStock(
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
  async creditDepot(
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
  checkProducts(
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
  async settleReceipt(
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
    // Refused units stay with the carrier and go back to the depot, also when
    // the store confirmed the parcel by its QR.
    if (
      delivery.sourceStoreId &&
      (proof.validated || lines.some((l) => l.condition === "refused"))
    )
      await this.reconcileDepot(
        ledger,
        delivery,
        lines,
        proof.shortfall ?? "returned",
        op.operationId,
        proof.responsibility,
        proof.validated === true,
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
  async reconcileDepot(
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
    validated = true,
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
          validated
            ? "Réception validée par BioBalance"
            : "Unités refusées par le magasin",
          validated
            ? `Bon ${delivery.ticketNumber} : les quantités retenues s’appliquent à vous et au magasin${touched.length ? ", votre stock a été ajusté" : ""}${responsibility ? ` ; ${who[responsibility]}` : ""}.`
            : `Bon ${delivery.ticketNumber} : les unités refusées à la réception ont été remises dans votre stock.`,
        );
      },
      { allowInactive: true },
    );
  }
}
