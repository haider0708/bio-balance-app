import { Prisma } from '@prisma/client';
import { OrderFulfillment, FulfillmentLine } from '../domain/order-fulfillment';

/** Uses actual receipts once received; a dispatched parcel still reserves supply. */
export async function orderFulfillment(
  tx: Prisma.TransactionClient, organizationId: string, storeId: string,
  orders: { id: string; lines: unknown }[],
): Promise<Map<string, FulfillmentLine[]>> {
  if (!orders.length) return new Map();
  const rows = await tx.$queryRaw<{ orderId: string; productId: string; received: bigint; inTransit: bigint }[]>(Prisma.sql`
    SELECT d."orderId", line->>'productId' AS "productId",
      COALESCE(SUM((line->>'quantity')::bigint) FILTER (WHERE d.status='received'), 0)::bigint AS received,
      COALESCE(SUM((line->>'quantity')::bigint) FILTER (WHERE d.status='dispatched'), 0)::bigint AS "inTransit"
    FROM "Delivery" d LEFT JOIN "DeliveryReceipt" r ON r."deliveryId"=d.id
      AND r."storeId"=d."storeId" AND r."organizationId"=d."organizationId"
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN d.status='received' THEN COALESCE(r.lines, '[]'::jsonb) ELSE d.lines END) line
    WHERE d."organizationId"=${organizationId}::uuid AND d."storeId"=${storeId}::uuid
      AND d."orderId" IN (${Prisma.join(orders.map(o => Prisma.sql`${o.id}::uuid`))})
    GROUP BY d."orderId", line->>'productId'`);
  return new Map(orders.map(order => [order.id, OrderFulfillment.calculate(
    order.lines as { productId: string; quantity: number }[],
    rows.filter(row => row.orderId === order.id).map(row => ({ ...row,
      received: Number(row.received), inTransit: Number(row.inTransit) })),
  )]));
}

/** Includes all outstanding orders, independently of the paginated order history. */
export async function outstandingSupply(tx: Prisma.TransactionClient, organizationId: string, storeId: string) {
  const rows = await tx.$queryRaw<{productId:string;quantity:bigint}[]>`
    WITH actual AS (
      SELECT d."orderId", line->>'productId' AS product, SUM((line->>'quantity')::bigint) AS quantity
      FROM "Delivery" d JOIN "DeliveryReceipt" r ON r."deliveryId"=d.id AND r."storeId"=d."storeId"
      CROSS JOIN LATERAL jsonb_array_elements(r.lines) line
      WHERE d."organizationId"=${organizationId}::uuid AND d."storeId"=${storeId}::uuid AND d.status='received'
      GROUP BY d."orderId", line->>'productId'
    )
    SELECT line->>'productId' AS "productId", SUM(GREATEST(0, (line->>'quantity')::bigint - COALESCE(a.quantity,0)))::bigint AS quantity
    FROM "ReplenishmentOrder" o CROSS JOIN LATERAL jsonb_array_elements(o.lines) line
    LEFT JOIN actual a ON a."orderId"=o.id AND a.product=line->>'productId'
    WHERE o."organizationId"=${organizationId}::uuid AND o."storeId"=${storeId}::uuid AND o.status<>'received'
    GROUP BY line->>'productId'`;
  return rows.map(row => ({productId:row.productId,quantity:Number(row.quantity)}));
}
