export interface FulfillmentLine {
  productId: string;
  ordered: number;
  cancelled: number;
  received: number;
  inTransit: number;
  remainingToDispatch: number;
  remainingToReceive: number;
}

export class OrderFulfillment {
  static calculate(
    lines: { productId: string; quantity: number }[],
    totals: { productId: string; received: number; inTransit: number }[],
    cancelledLines: { productId: string; quantity: number }[] = [],
  ): FulfillmentLine[] {
    const byProduct = new Map(totals.map((line) => [line.productId, line]));
    return lines.map((line) => {
      const { received = 0, inTransit = 0 } =
        byProduct.get(line.productId) ?? {};
      const cancelled =
        cancelledLines.find((c) => c.productId === line.productId)?.quantity ??
        0;
      return {
        productId: line.productId,
        ordered: line.quantity,
        received,
        cancelled,
        inTransit,
        remainingToDispatch: Math.max(
          0,
          line.quantity - received - inTransit - cancelled,
        ),
        remainingToReceive: Math.max(0, line.quantity - received - cancelled),
      };
    });
  }
}
