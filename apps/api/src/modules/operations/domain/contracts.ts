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
    // A seller cannot change the price, only leave a note on the line.
    note: z.string().trim().max(200).optional(),
    allocations: z.array(allocation).min(1).max(50),
  })
  .strict();
export const batchDeclaration = z
  .object({
    lotId: id,
    productId: id,
    batch: z.string().trim().min(1).max(100),
    expiry: z.string().max(10),
  })
  .strict();
const saleFields = {
  batchDeclarations: z.array(batchDeclaration).max(5000).optional(),
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
// A grossiste ships from identified lots; BioBalance's own stock is not tracked.
// A grossiste names the depot lot it ships; BioBalance, which does not track its
// own stock, declares the batch and expiry it puts on the ticket.
const shippedLot = z
  .object({
    lotId: id.optional(),
    batch: z.string().trim().min(1).max(100).optional(),
    expiry: z.string().max(10).optional(),
    quantity,
  })
  .strict();
const dispatchLine = orderLine
  .extend({ allocations: z.array(shippedLot).min(1).max(50).optional() })
  .strict();
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
      // Stock is declared once, at the start. After that it only moves by
      // delivery, sale, customer return and BioBalance's own decisions.
      reason: z.literal("opening"),
    })
    .strict(),
  z
    .object({
      type: z.literal("quality.flag"),
      flagId: id,
      lotId: id,
      quantity,
      kind: z.enum(["damaged", "expired"]),
      note: z.string().trim().max(500).optional(),
    })
    .strict(),
  z
    .object({
      type: z.literal("quality.resolve"),
      flagId: id,
      decision: z.enum(["confirm", "reject"]),
      note: z.string().trim().min(3).max(500),
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
      type: z.literal("order.assign"),
      orderId: id,
      // Null returns the order to BioBalance.
      supplierStoreId: id.nullable(),
    })
    .strict(),
  z
    .object({
      type: z.literal("order.amend"),
      orderId: id,
      lines: z.array(orderLine).min(1).max(200),
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("order.cancel"),
      orderId: id,
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("order.report"),
      orderId: id,
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("order.resolve"),
      orderId: id,
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("delivery.report"),
      deliveryId: id,
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  // The store sees what the ticket lists and turns the whole parcel away;
  // BioBalance then approves the return or asks the store to receive it.
  z
    .object({
      type: z.literal("delivery.refuse"),
      deliveryId: id,
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("delivery.resolve"),
      deliveryId: id,
      // "returned" also approves a store's refusal; "reopen" rejects it.
      decision: z.enum(["tracing", "lost", "returned", "settled", "reopen"]),
      reason: z.string().trim().min(3).max(500),
    })
    .strict(),
  z
    .object({
      type: z.literal("delivery.dispatch"),
      orderId: id,
      deliveryId: id,
      lines: z.array(dispatchLine).min(1).max(200),
    })
    .strict(),
  z.object({ type: z.literal("delivery.reissue"), deliveryId: id }).strict(),
  z
    .object({
      type: z.literal("delivery.receive"),
      deliveryId: id,
      // The code read from the parcel's QR, or the reason it could not be scanned.
      ticketCode: z
        .string()
        .regex(/^[A-Za-z0-9_-]{16,64}$/)
        .optional(),
      manualReason: z.string().trim().min(3).max(300).optional(),
      lines: z
        .array(
          receiptLine.extend({
            condition: z.enum(["sellable", "damaged", "refused"]).optional(),
          }),
        )
        .max(200),
      // With a scanned QR the quantities, lots and dates are the ticket's. The
      // store can still report the state of units: damaged or refused.
      flags: z
        .array(
          z
            .object({
              productId: id,
              batch: z.string().trim().min(1).max(100),
              damaged: z.number().int().min(0).max(1000000),
              refused: z.number().int().min(0).max(1000000),
            })
            .strict(),
        )
        .max(200)
        .default([]),
      note: z.string().max(500).default(""),
    })
    .strict(),
  // BioBalance settles a receipt that was not confirmed by the QR: it sees what
  // was shipped and what the store says it got, corrects it, and submits.
  z
    .object({
      type: z.literal("delivery.validate"),
      deliveryId: id,
      lines: z
        .array(
          receiptLine.extend({
            condition: z.enum(["sellable", "damaged", "refused"]).optional(),
          }),
        )
        .max(200),
      // What happens to units shipped but not received: back to the depot's
      // lots, or written off. BioBalance's own shipments have no depot.
      shortfall: z.enum(["returned", "lost"]).default("returned"),
      note: z.string().trim().min(3).max(500),
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
    dependencies: z.array(id).max(5000).optional(),
    expectedVersion: z.number().int().min(1).optional(),
    // Set by a grossiste acting on an order assigned to its depot.
    supplierStoreId: id.optional(),
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
  /** The store's retail price on the sale date, beside the price charged. */
  listPriceMillimes?: string | null;
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
  /** A grossiste depot records no sales. */
  wholesale?: boolean;
  /** Present when a grossiste acts on an order assigned to its depot. */
  supplier?: { organizationId: string; storeId: string };
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
export interface FlagRecord {
  id: string;
  lotId: string;
  batch: string;
  expiry: string;
  productId: string;
  quantity: number;
  kind: "damaged" | "expired";
  note: string | null;
  status: "open" | "confirmed" | "rejected";
  flaggedBy: string;
  decidedBy: string | null;
  decidedAt: Date | null;
  decisionNote: string | null;
  sourceDeliveryId: string | null;
  sourceTicket: string | null;
  valueMillimes: bigint | null;
  operationId: string;
  version: number;
}
export interface OrderLineRecord {
  productId: string;
  quantity: number;
  /** The supply price fixed when the line was ordered (null when none was set). */
  unitPriceMillimes?: string | null;
}
export interface OrderRecord {
  id: string;
  status: string;
  lines: OrderLineRecord[];
  supplierStoreId?: string | null;
  supplierOrganizationId?: string | null;
  version: number;
  requestedLines?: { productId: string; quantity: number }[];
  cancelledLines?: { productId: string; quantity: number }[];
}
export interface DispatchedLine {
  productId: string;
  quantity: number;
  unitPriceMillimes?: string | null;
  allocations?: {
    // The depot's lot; absent when BioBalance shipped and declared the lot.
    lotId?: string;
    batch: string;
    expiry: string;
    quantity: number;
  }[];
}
export interface DeliveryRecord extends Omit<OrderRecord, "lines"> {
  orderId: string;
  lines: DispatchedLine[];
  sourceStoreId?: string | null;
  sourceOrganizationId?: string | null;
  ticketNumber?: string;
  ticketVersion?: number;
  /** What the store says it received when it could not scan the QR. */
  claim?: unknown;
}
export interface DeliveryIssueRecord {
  id: string;
  deliveryId: string;
  orderId: string;
  status: string;
  reason: string;
  heldLines: { productId: string; quantity: number }[];
  version: number;
  resolution?: string | null;
  resolutionNote?: string | null;
}
export interface CommandOutcome {
  id: string;
  version?: number;
  orderVersion?: number;
  status?: string;
  total?: { currency: "TND"; millimes: string };
  points?: string;
  differences?: { productId: string; expected: number; actual: number }[];
}
export interface OperationResult {
  operationId: string;
  status: "accepted" | "conflict" | "rejected" | "blocked" | "retryable";
  committedCursor?: string;
  affectedVersions?: { resource: string; id: string; version: number }[];
  retryAfterMs?: number;
  code?: string;
  message?: string;
  data?: CommandOutcome;
}
