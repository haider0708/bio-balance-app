import { Prisma } from "@prisma/client";
import { OrderFulfillment, FulfillmentLine } from "../domain/order-fulfillment";

/** Uses actual receipts once received; a dispatched parcel still reserves supply. */
export async function orderFulfillment(
  tx: Prisma.TransactionClient,
  organizationId: string,
  storeId: string,
  orders: { id: string; lines: unknown; cancelledLines?: unknown }[],
): Promise<Map<string, FulfillmentLine[]>> {
  if (!orders.length) return new Map();
  const rows = await tx.$queryRaw<
    {
      orderId: string;
      productId: string;
      received: bigint;
      inTransit: bigint;
    }[]
  >(Prisma.sql`
    SELECT d."orderId", expected->>'productId' AS "productId",
      COALESCE(SUM(LEAST((expected->>'quantity')::bigint, COALESCE(actual.quantity,0))) FILTER (WHERE d.status='received'), 0)::bigint AS received,
      COALESCE(SUM((expected->>'quantity')::bigint) FILTER (WHERE d.status='dispatched'), 0)::bigint AS "inTransit"
    FROM "Delivery" d LEFT JOIN "DeliveryReceipt" r ON r."deliveryId"=d.id
      AND r."storeId"=d."storeId" AND r."organizationId"=d."organizationId"
    CROSS JOIN LATERAL jsonb_array_elements(d.lines) expected
    LEFT JOIN LATERAL (
      SELECT SUM((line->>'quantity')::bigint) AS quantity FROM jsonb_array_elements(COALESCE(r.lines,'[]'::jsonb)) line
      WHERE line->>'productId'=expected->>'productId' AND COALESCE(line->>'condition','sellable')='sellable'
    ) actual ON true
    WHERE d."organizationId"=${organizationId}::uuid AND d."storeId"=${storeId}::uuid
      AND d."orderId" IN (${Prisma.join(orders.map((o) => Prisma.sql`${o.id}::uuid`))})
    GROUP BY d."orderId", expected->>'productId' `);
  const holds = await tx.deliveryIssue.findMany({
    where: {
      organizationId,
      storeId,
      orderId: { in: orders.map((o) => o.id) },
      status: { not: "resolved" },
    },
  });
  return new Map(
    orders.map((order) => {
      const totals = new Map(
        rows
          .filter((r) => r.orderId === order.id)
          .map((r) => [
            r.productId,
            {
              productId: r.productId,
              received: Number(r.received),
              inTransit: Number(r.inTransit),
            },
          ]),
      );
      for (const hold of holds
        .filter((h) => h.orderId === order.id)
        .flatMap(
          (h) => h.heldLines as { productId: string; quantity: number }[],
        )) {
        const line = totals.get(hold.productId) ?? {
          productId: hold.productId,
          received: 0,
          inTransit: 0,
        };
        line.inTransit += hold.quantity;
        totals.set(hold.productId, line);
      }
      return [
        order.id,
        OrderFulfillment.calculate(
          order.lines as { productId: string; quantity: number }[],
          [...totals.values()],
          (order.cancelledLines ?? []) as {
            productId: string;
            quantity: number;
          }[],
        ),
      ];
    }),
  );
}

/** Includes all outstanding orders, independently of the paginated order history. */
export async function outstandingSupply(
  tx: Prisma.TransactionClient,
  organizationId: string,
  storeId: string,
) {
  const rows = await tx.$queryRaw<{ productId: string; quantity: bigint }[]>`
    WITH actual AS (
      SELECT d."orderId", expected->>'productId' AS product,
        SUM(LEAST((expected->>'quantity')::bigint, COALESCE(received.quantity,0))) AS quantity
      FROM "Delivery" d JOIN "DeliveryReceipt" r ON r."deliveryId"=d.id AND r."storeId"=d."storeId" AND r."organizationId"=d."organizationId"
      CROSS JOIN LATERAL jsonb_array_elements(d.lines) expected
      LEFT JOIN LATERAL (
        SELECT SUM((line->>'quantity')::bigint) AS quantity FROM jsonb_array_elements(r.lines) line
        WHERE line->>'productId'=expected->>'productId' AND COALESCE(line->>'condition','sellable')='sellable'
      ) received ON true
      WHERE d."organizationId"=${organizationId}::uuid AND d."storeId"=${storeId}::uuid AND d.status='received'
      GROUP BY d."orderId", expected->>'productId'
    )
    SELECT line->>'productId' AS "productId", SUM(GREATEST(0, (line->>'quantity')::bigint - COALESCE(a.quantity,0) - COALESCE((SELECT (c->>'quantity')::bigint FROM jsonb_array_elements(o."cancelledLines") c WHERE c->>'productId'=line->>'productId'),0)))::bigint AS quantity
    FROM "ReplenishmentOrder" o CROSS JOIN LATERAL jsonb_array_elements(o.lines) line
    LEFT JOIN actual a ON a."orderId"=o.id AND a.product=line->>'productId'
    WHERE o."organizationId"=${organizationId}::uuid AND o."storeId"=${storeId}::uuid AND o.status NOT IN ('received','cancelled','closed_partial')
    GROUP BY line->>'productId'`;
  return rows.map((row) => ({
    productId: row.productId,
    quantity: Number(row.quantity),
  }));
}
