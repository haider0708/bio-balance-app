import { requireRule } from "../../../shared/domain/errors";
import { OrderRecord } from "./contracts";
import { FulfillmentLine } from "./order-fulfillment";

/** Order commitments are independent of physical stock. */
export class Order {
  static readonly terminal = ["received", "cancelled", "closed_partial"];
  static editable(order: OrderRecord) {
    requireRule(
      !this.terminal.includes(order.status),
      "ORDER_COMPLETE",
      "Cette commande est terminée ou annulée.",
      409,
    );
  }
  static amend(
    order: OrderRecord,
    lines: OrderRecord["lines"],
    fulfillment: FulfillmentLine[],
  ) {
    this.editable(order);
    requireRule(
      new Set(lines.map((l) => l.productId)).size === lines.length,
      "DUPLICATE_PRODUCT",
      "Produit répété.",
    );
    for (const old of fulfillment) {
      const next =
        lines.find((l) => l.productId === old.productId)?.quantity ?? 0;
      requireRule(
        next >= old.received + old.inTransit + old.cancelled,
        "ORDER_COMMITTED",
        "La quantité ne peut pas être inférieure aux unités reçues, engagées ou annulées.",
        409,
      );
    }
    order.requestedLines ??= order.lines;
    order.lines = lines;
    order.version++;
  }
  static cancel(order: OrderRecord, fulfillment: FulfillmentLine[]) {
    this.editable(order);
    requireRule(
      fulfillment.some((l) => l.remainingToDispatch > 0),
      "NO_REMAINDER",
      "Aucun reliquat disponible à annuler. Résolvez d’abord les livraisons en cours.",
      409,
    );
    order.cancelledLines = fulfillment
      .map((l) => ({
        productId: l.productId,
        quantity: l.cancelled + l.remainingToDispatch,
      }))
      .filter((l) => l.quantity > 0);
    order.version++;
  }
  static status(fulfillment: FulfillmentLine[], hasIssues: boolean) {
    if (fulfillment.some((l) => l.inTransit > 0))
      return fulfillment.some((l) => l.received > 0) ? "partial" : "dispatched";
    if (hasIssues || fulfillment.some((l) => l.remainingToReceive > 0))
      return "partial";
    return fulfillment.some((l) => l.cancelled > 0)
      ? fulfillment.some((l) => l.received > 0)
        ? "closed_partial"
        : "cancelled"
      : "received";
  }
}
