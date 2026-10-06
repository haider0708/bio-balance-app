import { Injectable } from "@nestjs/common";
import type { OrderStatus, Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { adjustStock, currentQuantity, findLocation } from "../stock/ledger";

export interface QtyLine {
  productId: string;
  quantity: number;
}

type Order = Prisma.RestockOrderGetPayload<{ include: { lines: true } }>;

/**
 * The restock chain:
 *   REQUESTED → (admin) ASSIGNED to a grossiste, or sent directly → SHIPPED
 *   → (receiver) RECEIVED with photo and quantities → (admin) COMPLETED.
 * Stock only moves when the admin approves the receipt.
 */
@Injectable()
export class RestockService {
  constructor(private readonly db: Database) {}

  // ───────────────────────── Request ─────────────────────────

  async create(actor: Actor, input: { destId?: string; note?: string; lines: QtyLine[] }) {
    requireRule(["RESPONSABLE", "GROSSISTE"].includes(actor.role), "FORBIDDEN", "Only a responsable or grossiste requests a restock.", 403);
    return this.db.run(actor, async (tx) => {
      const destId = actor.role === "GROSSISTE" ? actor.depotId : input.destId;
      requireRule(destId, "DESTINATION_REQUIRED", "Choose a point of sale.");
      const dest = await findLocation(tx, destId);
      requireRule(
        actor.role === "GROSSISTE" ? dest.kind === "DEPOT" && dest.id === actor.depotId : dest.kind === "PDV" && dest.regionId === actor.regionId,
        "FORBIDDEN", "You cannot request stock for this place.", 403,
      );
      requireRule(dest.status === "ACTIVE", "INVALID_STATE", "This place is not active yet.", 409);
      await this.checkLines(tx, input.lines);
      const [sequence] = await tx.$queryRaw<{ n: bigint }[]>`SELECT nextval('restock_number_seq') AS n`;
      const number = `RS-${new Date().getUTCFullYear()}-${String(sequence!.n).padStart(6, "0")}`;
      const order = await tx.restockOrder.create({
        data: {
          number, regionId: dest.regionId, destKind: dest.kind, destId: dest.id,
          requestedById: actor.id, note: input.note?.trim() || null,
          lines: { create: input.lines.map((l) => ({ productId: l.productId, requested: l.quantity })) },
        },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.requested", "RestockOrder", order.id, { number, place: dest.name }, dest.regionId);
      await notifyAdmins(tx, { key: "restock.requested", params: { number, place: dest.name, by: actor.name }, entityType: "RestockOrder", entityId: order.id });
      return this.one(tx, order);
    });
  }

  // ───────────────────────── Admin routes the order ─────────────────────────

  /** Give the order to a grossiste. The admin may adjust the quantities first. */
  assign(actor: Actor, id: string, input: { depotId: string; lines?: QtyLine[] }) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can assign.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "REQUESTED");
      requireRule(order.destKind === "PDV", "INVALID_STATE", "A depot restock is sent directly by BioBalance.", 409);
      const depot = await tx.depot.findUnique({ where: { id: input.depotId } });
      requireRule(depot?.status === "ACTIVE", "DEPOT_NOT_FOUND", "Choose an active grossiste.", 404);
      if (input.lines) await this.reshape(tx, order, input.lines);
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "ASSIGNED", source: "GROSSISTE", supplierDepotId: depot.id, assignedAt: new Date() },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.assigned", "RestockOrder", id, { depot: depot.name }, order.regionId);
      await this.tellRequester(tx, order, "restock.assigned", { number: order.number, depot: depot.name });
      await notify(tx, [depot.userId], { key: "restock.to_prepare", params: { number: order.number }, entityType: "RestockOrder", entityId: id });
      return this.one(tx, updated);
    });
  }

  /** BioBalance holds unlimited stock: ship straight to the place. */
  sendDirect(actor: Actor, id: string, input: { lines?: QtyLine[] }) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can send directly.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "REQUESTED");
      if (input.lines) await this.reshape(tx, order, input.lines);
      await tx.$executeRaw`UPDATE "RestockLine" SET shipped = requested WHERE "orderId" = ${id}::uuid`;
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "SHIPPED", source: "BIOBALANCE", shippedAt: new Date(), assignedAt: new Date() },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.sent_direct", "RestockOrder", id, {}, order.regionId);
      await this.tellRequester(tx, order, "restock.shipped", { number: order.number, from: "BioBalance" });
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Grossiste ships ─────────────────────────

  ship(actor: Actor, id: string, input: { lines: QtyLine[] }) {
    requireRule(actor.role === "GROSSISTE" && actor.depotId, "FORBIDDEN", "Only the assigned grossiste ships.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "ASSIGNED");
      requireRule(order.supplierDepotId === actor.depotId, "FORBIDDEN", "This order is not assigned to you.", 403);
      const byProduct = new Map(input.lines.map((l) => [l.productId, l.quantity]));
      requireRule(byProduct.size === input.lines.length, "DUPLICATE_PRODUCT", "A product appears twice.");
      for (const l of input.lines)
        requireRule(order.lines.some((x) => x.productId === l.productId), "PRODUCT_NOT_FOUND", "That product is not in the order.", 422);
      let total = 0;
      for (const line of order.lines) {
        const shipped = byProduct.get(line.productId) ?? 0;
        requireRule(shipped <= line.requested, "TOO_MANY", "You cannot ship more than was requested.");
        const have = await currentQuantity(tx, actor.depotId!, line.productId);
        requireRule(shipped <= have, "INSUFFICIENT_STOCK", "Your depot does not hold enough of a product.", 409);
        total += shipped;
        await tx.restockLine.update({ where: { id: line.id }, data: { shipped } });
      }
      requireRule(total > 0, "NOTHING_SHIPPED", "Ship at least one unit.");
      const updated = await tx.restockOrder.update({
        where: { id }, data: { status: "SHIPPED", shippedAt: new Date() }, include: { lines: true },
      });
      await audit(tx, actor, "restock.shipped", "RestockOrder", id, { units: total }, order.regionId);
      await this.tellRequester(tx, order, "restock.shipped", { number: order.number, from: actor.name });
      await notifyAdmins(tx, { key: "restock.shipped_info", params: { number: order.number, by: actor.name }, entityType: "RestockOrder", entityId: id });
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Receipt ─────────────────────────

  /** The responsable picks a team member to count the goods (or takes it back with `null`). */
  setReceiver(actor: Actor, id: string, userId: string | null) {
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Only the responsable chooses who receives.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id);
      requireRule(order.destKind === "PDV", "INVALID_STATE", "Not applicable.", 409);
      requireRule(["REQUESTED", "ASSIGNED", "SHIPPED"].includes(order.status), "INVALID_STATE", "The delivery was already received.", 409);
      if (userId) {
        const member = await tx.user.findUnique({ where: { id: userId } });
        requireRule(
          member?.role === "VENDEUR" && member.status === "ACTIVE" && member.pdvId === order.destId && !!member.passwordHash,
          "RECEIVER_INVALID", "Choose an active member of this point of sale.", 422,
        );
      }
      const updated = await tx.restockOrder.update({ where: { id }, data: { receiverId: userId }, include: { lines: true } });
      if (userId)
        await notify(tx, [userId], { key: "restock.receiver_assigned", params: { number: order.number }, entityType: "RestockOrder", entityId: id });
      await audit(tx, actor, "restock.receiver_set", "RestockOrder", id, { userId }, order.regionId);
      return this.one(tx, updated);
    });
  }

  /** Photo of the signed paper and the quantities actually counted. */
  receive(actor: Actor, id: string, input: { photoId: string; lines: QtyLine[]; note?: string }) {
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "SHIPPED");
      const isReceiver = order.receiverId === actor.id;
      const allowed =
        isReceiver ||
        (actor.role === "RESPONSABLE" && order.destKind === "PDV" && order.regionId === actor.regionId) ||
        (actor.role === "GROSSISTE" && order.destKind === "DEPOT" && order.destId === actor.depotId);
      requireRule(allowed, "FORBIDDEN", "You cannot receive this delivery.", 403);
      const photo = await tx.mediaAsset.findUnique({ where: { id: input.photoId } });
      requireRule(photo?.purpose === "PROOF" && photo.ownerId === actor.id, "PHOTO_REQUIRED", "Add a photo of the delivery paper.");
      const counted = new Map(input.lines.map((l) => [l.productId, l.quantity]));
      requireRule(counted.size === input.lines.length, "DUPLICATE_PRODUCT", "A product appears twice.");
      for (const l of input.lines)
        requireRule(order.lines.some((x) => x.productId === l.productId && (x.shipped ?? 0) > 0), "PRODUCT_NOT_FOUND", "That product was not shipped.", 422);
      for (const line of order.lines.filter((x) => (x.shipped ?? 0) > 0))
        requireRule(counted.has(line.productId), "LINE_MISSING", "Enter the quantity received for every product.");
      for (const line of order.lines)
        await tx.restockLine.update({ where: { id: line.id }, data: { received: counted.get(line.productId) ?? 0 } });
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "RECEIVED", receiptPhotoId: input.photoId, receivedAt: new Date(), decisionNote: null,
          ...(isReceiver ? {} : { receiverId: actor.id }) },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.received", "RestockOrder", id, { note: input.note ?? null }, order.regionId);
      await notifyAdmins(tx, { key: "restock.received", params: { number: order.number, by: actor.name }, entityType: "RestockOrder", entityId: id });
      return this.one(tx, updated);
    });
  }

  /** The admin checks the photo against the quantities and approves them, as counted or corrected. */
  approve(actor: Actor, id: string, input: { lines?: QtyLine[]; note?: string }) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can approve.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "RECEIVED");
      const overrides = new Map((input.lines ?? []).map((l) => [l.productId, l.quantity]));
      for (const productId of overrides.keys())
        requireRule(order.lines.some((l) => l.productId === productId), "PRODUCT_NOT_FOUND", "That product is not in the order.", 422);
      const dest = await findLocation(tx, order.destId);
      const depot = order.supplierDepotId ? await findLocation(tx, order.supplierDepotId) : null;
      let amended = 0;
      for (const line of order.lines) {
        const approved = overrides.get(line.productId) ?? line.received ?? 0;
        if (approved !== (line.received ?? 0)) amended++;
        await tx.restockLine.update({ where: { id: line.id }, data: { approved } });
        if (approved === 0) continue;
        await adjustStock(tx, dest, line.productId, approved, { reason: "RECEIPT", refType: "RestockOrder", refId: id, actorId: actor.id });
        if (depot)
          await adjustStock(tx, depot, line.productId, -approved, { reason: "SHIPMENT", refType: "RestockOrder", refId: id, actorId: actor.id });
      }
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "COMPLETED", decidedById: actor.id, decidedAt: new Date(), decisionNote: input.note?.trim() || null },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.approved", "RestockOrder", id, { amended }, order.regionId);
      await this.tellEveryone(tx, order, "restock.completed", { number: order.number, amended, note: input.note ?? null });
      return this.one(tx, updated);
    });
  }

  /** The receipt does not match: send it back to be counted again. */
  reject(actor: Actor, id: string, note: string) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can reject.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "RECEIVED");
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "SHIPPED", decisionNote: note, decidedById: actor.id, decidedAt: new Date() },
        include: { lines: true },
      });
      await audit(tx, actor, "restock.receipt_rejected", "RestockOrder", id, { note }, order.regionId);
      const recipients = [order.receiverId, order.requestedById].filter((x): x is string => !!x);
      await notify(tx, recipients, { key: "restock.receipt_rejected", params: { number: order.number, note }, entityType: "RestockOrder", entityId: id });
      return this.one(tx, updated);
    });
  }

  cancel(actor: Actor, id: string, reason: string) {
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id);
      const own = order.requestedById === actor.id && order.status === "REQUESTED";
      requireRule(actor.role === "ADMIN" || own, "FORBIDDEN", "You cannot cancel this order.", 403);
      requireRule(["REQUESTED", "ASSIGNED", "SHIPPED"].includes(order.status), "INVALID_STATE", "This order can no longer be cancelled.", 409);
      const updated = await tx.restockOrder.update({
        where: { id }, data: { status: "CANCELLED", cancelReason: reason }, include: { lines: true },
      });
      await audit(tx, actor, "restock.cancelled", "RestockOrder", id, { reason }, order.regionId);
      await this.tellEveryone(tx, order, "restock.cancelled", { number: order.number, reason }, actor.id);
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Reading ─────────────────────────

  list(actor: Actor, filter: { status?: OrderStatus; regionId?: string; destId?: string; active?: boolean }) {
    requireRule(["ADMIN", "RESPONSABLE", "GROSSISTE", "VENDEUR"].includes(actor.role), "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const orders = await tx.restockOrder.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.active && { status: { in: ["REQUESTED", "ASSIGNED", "SHIPPED", "RECEIVED"] as OrderStatus[] } }),
          ...(filter.destId && { destId: filter.destId }),
          ...(actor.role === "ADMIN" && filter.regionId && { regionId: filter.regionId }),
        },
        include: { lines: true },
        orderBy: { createdAt: "desc" },
        take: 200,
      });
      return this.many(tx, orders);
    });
  }

  get(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => this.one(tx, await this.load(tx, id)));
  }

  // ───────────────────────── Helpers ─────────────────────────

  /** Lock the order and check it is in the expected state. */
  private async load(tx: Tx, id: string, expected?: OrderStatus): Promise<Order> {
    const visible = await tx.restockOrder.findUnique({ where: { id }, select: { id: true } });
    if (!visible) throw notFound("Restock");
    await this.db.lock(tx, "RestockOrder", id);
    const order = await tx.restockOrder.findUniqueOrThrow({ where: { id }, include: { lines: true } });
    if (expected && order.status !== expected)
      throw new DomainError("INVALID_STATE", `This order is ${order.status.toLowerCase()}, not ${expected.toLowerCase()}.`, 409);
    return order;
  }

  private async checkLines(tx: Tx, lines: QtyLine[]) {
    const ids = lines.map((l) => l.productId);
    requireRule(new Set(ids).size === ids.length, "DUPLICATE_PRODUCT", "A product appears twice.");
    requireRule((await tx.product.count({ where: { id: { in: ids }, active: true } })) === ids.length, "PRODUCT_NOT_FOUND", "Unknown or inactive product.", 404);
  }

  /** Replace the requested lines (the admin adjusting before routing). */
  private async reshape(tx: Tx, order: Order, lines: QtyLine[]) {
    await this.checkLines(tx, lines);
    await tx.restockLine.deleteMany({ where: { orderId: order.id } });
    await tx.restockLine.createMany({ data: lines.map((l) => ({ orderId: order.id, productId: l.productId, requested: l.quantity })) });
  }

  private tellRequester(tx: Tx, order: Order, key: string, params: Record<string, unknown>) {
    return notify(tx, [order.requestedById], { key, params, entityType: "RestockOrder", entityId: order.id });
  }

  private async tellEveryone(tx: Tx, order: Order, key: string, params: Record<string, unknown>, except?: string) {
    const depot = order.supplierDepotId ? await tx.depot.findUnique({ where: { id: order.supplierDepotId } }) : null;
    const region = order.regionId ? await responsableIds(tx, order.regionId) : [];
    const ids = [order.requestedById, order.receiverId, depot?.userId, ...region].filter((x): x is string => !!x && x !== except);
    await notify(tx, ids, { key, params, entityType: "RestockOrder", entityId: order.id });
  }

  private async many(tx: Tx, orders: Order[]) {
    if (!orders.length) return [];
    const productIds = [...new Set(orders.flatMap((o) => o.lines.map((l) => l.productId)))];
    const placeIds = [...new Set(orders.flatMap((o) => [o.destId, o.supplierDepotId].filter((x): x is string => !!x)))];
    const userIds = [...new Set(orders.flatMap((o) => [o.requestedById, o.receiverId, o.decidedById].filter((x): x is string => !!x)))];
    const [products, pdvs, depots, users] = await Promise.all([
      tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true, family: true } }),
      tx.pdv.findMany({ where: { id: { in: placeIds } }, select: { id: true, name: true } }),
      tx.depot.findMany({ where: { id: { in: placeIds } }, select: { id: true, name: true } }),
      tx.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    const user = new Map(users.map((u) => [u.id, u.name]));
    const who = (id: string | null) => (id ? { id, name: user.get(id) ?? "" } : null);
    return orders.map((o) => ({
      id: o.id, number: o.number, status: o.status, source: o.source, note: o.note, regionId: o.regionId,
      destination: { id: o.destId, kind: o.destKind, name: place.get(o.destId) ?? "" },
      supplier: o.supplierDepotId ? { id: o.supplierDepotId, name: place.get(o.supplierDepotId) ?? "" } : null,
      requestedBy: who(o.requestedById), receiver: who(o.receiverId), decidedBy: who(o.decidedById),
      createdAt: o.createdAt, assignedAt: o.assignedAt, shippedAt: o.shippedAt, receivedAt: o.receivedAt, decidedAt: o.decidedAt,
      receiptPhotoId: o.receiptPhotoId, decisionNote: o.decisionNote, cancelReason: o.cancelReason,
      lines: o.lines
        .map((l) => ({
          productId: l.productId, name: product.get(l.productId)?.name ?? "", family: product.get(l.productId)?.family ?? "",
          requested: l.requested, shipped: l.shipped, received: l.received, approved: l.approved,
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    }));
  }

  private async one(tx: Tx, order: Order) {
    return (await this.many(tx, [order]))[0]!;
  }
}
