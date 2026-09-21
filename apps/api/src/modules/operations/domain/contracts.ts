import { z } from "zod";
export const id = z.uuid();
const quantity = z.number().int().min(1).max(1_000_000);
const millimes = z.string().regex(/^(0|[1-9]\d{0,14})$/);
const allocation = z.object({ lotId: id, quantity }).strict();
export const saleLine = z
  .object({
    id,
    productId: id,
    quantity,
    unitPriceMillimes: millimes,
    allocations: z.array(allocation).min(1).max(50),
  })
  .strict();
const saleFields = {
  saleId: id,
  occurredAt: z.iso.datetime({ offset: true }),
  lines: z.array(saleLine).min(1).max(100),
};
const receiptLine = z
  .object({
    productId: id,
    batch: z.string().trim().min(1).max(100),
    expiry: z.string().max(10),
    quantity,
  })
  .strict();
const orderLine = z.object({ productId: id, quantity }).strict();
export const commandSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("sale.create"), ...saleFields }).strict(),
  z
    .object({
      type: z.literal("sale.correct"),
      ...saleFields,
      reason: z.string().trim().min(3).max(300),
    })
    .strict(),
  z
    .object({
      type: z.literal("sale.return"),
      saleId: id,
      reason: z.string().trim().min(3).max(300),
      lines: z
        .array(
          z
            .object({ lineId: id, lotId: id, quantity, sellable: z.boolean() })
            .strict(),
        )
        .min(1)
        .max(100),
    })
    .strict(),
  z
    .object({
      type: z.literal("stock.receive"),
      lines: z.array(receiptLine).min(1).max(200),
      reason: z.enum(["opening", "receipt"]),
    })
    .strict(),
  z
    .object({
      type: z.literal("stock.adjust"),
      lotId: id,
      quantity: z.number().int().min(0).max(1_000_000),
      reason: z.string().trim().min(3).max(300),
    })
    .strict(),
  z
    .object({
      type: z.literal("stock.damage"),
      lotId: id,
      quantity,
      reason: z.string().trim().min(3).max(300),
    })
    .strict(),
  z
    .object({
      type: z.literal("order.create"),
      orderId: id,
      lines: z.array(orderLine).min(1).max(200),
    })
    .strict(),
  z.object({ type: z.literal("order.prepare"), orderId: id }).strict(),
  z
    .object({
      type: z.literal("delivery.dispatch"),
      orderId: id,
      deliveryId: id,
      lines: z.array(orderLine).min(1).max(200),
    })
    .strict(),
  z
    .object({
      type: z.literal("delivery.receive"),
      deliveryId: id,
      lines: z.array(receiptLine).max(200),
      note: z.string().max(500).default(""),
    })
    .strict(),
  z
    .object({ type: z.literal("reward.request"), claimId: id, rewardId: id })
    .strict(),
  z
    .object({
      type: z.literal("reward.resolve"),
      claimId: id,
      decision: z.enum(["fulfilled", "cancelled", "rejected"]),
    })
    .strict(),
]);
export const operationSchema = z
  .object({
    operationId: id,
    storeId: id,
    organizationId: id,
    payloadVersion: z.union([z.literal(1), z.literal(2)]),
    dependencies: z.array(id).max(200).optional(),
    expectedVersion: z.number().int().min(1).optional(),
    command: commandSchema,
  })
  .strict();
export const syncBatchSchema = z
  .object({ operations: z.array(operationSchema).min(1).max(50) })
  .strict();
export type Operation = z.infer<typeof operationSchema>;
export type Command = Operation["command"];
export type LineInput = z.infer<typeof saleLine>;
export interface AcceptedLine extends LineInput {
  pointsPerUnit: number;
}
export interface Actor {
  sessionId?: string;
  id: string;
  name: string;
  email: string;
  platformAdmin: boolean;
}
export interface Scope {
  organizationId: string;
  storeId: string;
  actor: Actor;
  permissions: string[];
  timezone: string;
}
export interface Lot {
  id: string;
  productId: string;
  batch: string;
  expiry: Date;
  sellable: number;
  damaged: number;
  version: number;
}
export interface SaleRecord {
  id: string;
  sellerId: string;
  occurredAt: Date;
  version: number;
  lines: AcceptedLine[];
  returned: Record<string, number>;
  totalMillimes: bigint;
  earnedPoints: bigint;
}
export interface PointsAccount {
  balance: bigint;
  reserved: bigint;
}
export interface RewardRecord {
  id: string;
  title: string;
  cost: number;
  productId: string | null;
  quantity: number;
  active: boolean;
}
export interface ClaimRecord extends Omit<RewardRecord, "id" | "active"> {
  id: string;
  rewardId: string;
  userId: string;
  status: string;
  version: number;
}
export interface OrderRecord {
  id: string;
  status: string;
  lines: { productId: string; quantity: number }[];
  version: number;
}
export interface DeliveryRecord extends OrderRecord {
  orderId: string;
}
export interface OperationResult {
  operationId: string;
  status: "accepted" | "conflict" | "rejected" | "blocked" | "retryable";
  committedCursor?: string;
  affectedVersions?: { resource: string; id: string; version: number }[];
  retryAfterMs?: number;
  code?: string;
  message?: string;
  data?: Record<string, unknown>;
}
