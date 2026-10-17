import { ownedProofs } from "../media/proofs";
import { Injectable } from "@nestjs/common";
import type { OrderStatus, Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { decisionLocked, withinDecisionWindow } from "../../core/approval";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { adjustStock, currentQuantity, findLocation } from "../stock/ledger";
import { SettingsService } from "../../core/settings";

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
  constructor(
    private readonly db: Database,
    private readonly settings: SettingsService = new SettingsService(db),
  ) {}

  // ───────────────────────── Request ─────────────────────────

  /**
   * A responsable asks BioBalance for goods (a store of their region, or a grossiste of it).
   * The admin restocking a grossiste records the delivery on the spot, with photos of the goods.
   */
  async create(
    actor: Actor,
    input: {
      destId?: string;
      note?: string;
      lines: QtyLine[];
      photoIds?: string[];
      /** A responsable the admin allowed suggests the grossiste for a store's order. */
      supplierId?: string;
    },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Only the admin or a responsable restocks.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      requireRule(input.destId, "DESTINATION_REQUIRED", "Choose a place.");
      const dest = await findLocation(tx, input.destId);
      const byAdmin = actor.role === "ADMIN";
      requireRule(
        byAdmin ? dest.kind === "DEPOT" : dest.stockRegionId === actor.regionId,
        "FORBIDDEN",
        byAdmin
          ? "The admin restocks a grossiste; stores order through their responsable."
          : "You cannot request stock for this place.",
        403,
      );
      requireRule(
        dest.status === "ACTIVE",
        "INVALID_STATE",
        "This place is not active yet.",
        409,
      );
      await this.checkLines(tx, input.lines);
      let suggested: { id: string; name: string } | null = null;
      if (input.supplierId) {
        requireRule(
          !byAdmin && dest.kind === "PDV",
          "SUPPLIER_CHOICE_OFF",
          "Only a responsable allowed to choose the grossiste suggests one, for a store's order.",
          403,
        );
        const [global, me] = await Promise.all([
          this.settings.get(),
          tx.user.findUnique({
            where: { id: actor.id },
            select: { canChooseSupplier: true },
          }),
        ]);
        requireRule(
          global.supplierChoice && me?.canChooseSupplier,
          "SUPPLIER_CHOICE_OFF",
          "You cannot choose the grossiste for an order.",
          403,
        );
        // A grossiste of any region (the responsable cannot see other regions' rows themselves).
        const depot = await this.db.run("SYSTEM", (t) =>
          t.depot.findUnique({ where: { id: input.supplierId! } }),
        );
        requireRule(
          depot?.status === "ACTIVE",
          "DEPOT_NOT_FOUND",
          "Choose an active grossiste.",
          404,
        );
        suggested = { id: depot.id, name: depot.name };
      }
      const [sequence] = await tx.$queryRaw<
        { n: bigint }[]
      >`SELECT nextval('restock_number_seq') AS n`;
      const number = `RS-${new Date().getUTCFullYear()}-${String(sequence!.n).padStart(6, "0")}`;
      const photoIds = byAdmin
        ? await ownedProofs(
            tx,
            actor,
            input.photoIds ?? [],
            "Add a photo of the goods.",
            { regionId: dest.stockRegionId },
          )
        : [];
      const now = new Date();
      const order = await tx.restockOrder.create({
        data: {
          number,
          regionId: dest.stockRegionId,
          destKind: dest.kind,
          destId: dest.id,
          requestedById: actor.id,
          note: input.note?.trim() || null,
          suggestedDepotId: suggested?.id ?? null,
          lines: {
            create: input.lines.map((l) => ({
              productId: l.productId,
              requested: l.quantity,
              ...(byAdmin && {
                shipped: l.quantity,
                received: l.quantity,
                approved: l.quantity,
              }),
            })),
          },
          ...(byAdmin && {
            status: "COMPLETED" as const,
            source: "BIOBALANCE" as const,
            assignedAt: now,
            shippedAt: now,
            receivedAt: now,
            decidedAt: now,
            receiverId: actor.id,
            decidedById: actor.id,
            receiptPhotoId: photoIds[0],
            receiptPhotoIds: photoIds,
          }),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        byAdmin ? "restock.recorded" : "restock.requested",
        "RestockOrder",
        order.id,
        { number, place: dest.name },
        dest.stockRegionId,
      );
      if (byAdmin) {
        for (const l of input.lines)
          await adjustStock(tx, dest, l.productId, l.quantity, {
            reason: "RECEIPT",
            refType: "RestockOrder",
            refId: order.id,
            actorId: actor.id,
          });
        await this.tellEveryone(
          tx,
          order,
          "restock.completed",
          { number, amended: 0, note: input.note ?? null },
          actor.id,
        );
      } else
        await notifyAdmins(tx, order.regionId, {
          key: suggested ? "restock.requested_from" : "restock.requested",
          params: {
            number,
            place: dest.name,
            by: actor.name,
            depot: suggested?.name ?? "",
          },
          entityType: "RestockOrder",
          entityId: order.id,
        });
      return this.one(tx, order);
    });
  }

  // ───────────────────────── Admin routes the order ─────────────────────────

  /**
   * Every active grossiste, of any region, with what it holds of the order's products: the admin
   * sees who can send it before choosing. Those holding everything come first, then the order's
   * own region.
   */
  suppliers(actor: Actor, id: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin chooses the grossiste.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await tx.restockOrder.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!order) throw notFound("Restock");
      const [depots, regions] = await Promise.all([
        tx.depot.findMany({ where: { status: "ACTIVE" } }),
        tx.region.findMany({ select: { id: true, name: true } }),
      ]);
      const stock = await tx.stock.findMany({
        where: {
          locationId: { in: depots.map((d) => d.id) },
          productId: { in: order.lines.map((l) => l.productId) },
        },
        select: { locationId: true, productId: true, quantity: true },
      });
      const held = new Map(
        stock.map((s) => [`${s.locationId}:${s.productId}`, s.quantity]),
      );
      const regionName = new Map(regions.map((r) => [r.id, r.name]));
      return depots
        .filter((d) => d.id !== order.destId)
        .map((d) => {
          const lines = order.lines.map((l) => ({
            productId: l.productId,
            requested: l.requested,
            held: Math.max(0, held.get(`${d.id}:${l.productId}`) ?? 0),
          }));
          return {
            id: d.id,
            name: d.name,
            city: d.city,
            regionId: d.regionId,
            regionName: regionName.get(d.regionId) ?? "",
            /** Products of the order it holds fewer of than requested. */
            missing: lines.filter((l) => l.held < l.requested).length,
            lines: lines.sort((a, b) => a.productId.localeCompare(b.productId)),
          };
        })
        .sort(
          (a, b) =>
            a.missing - b.missing ||
            Number(b.regionId === order.regionId) -
              Number(a.regionId === order.regionId) ||
            a.name.localeCompare(b.name),
        );
    });
  }

  /**
   * For a responsable allowed to choose a grossiste: every active grossiste (any region) with
   * whether it can cover the lines. Never the quantities another region holds.
   */
  async suppliersFor(actor: Actor, lines: QtyLine[]) {
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const [global, me] = await Promise.all([
        this.settings.get(),
        tx.user.findUnique({
          where: { id: actor.id },
          select: { canChooseSupplier: true },
        }),
      ]);
      requireRule(
        global.supplierChoice && me?.canChooseSupplier,
        "SUPPLIER_CHOICE_OFF",
        "You cannot choose the grossiste for an order.",
        403,
      );
      await this.checkLines(tx, lines);
      // Read as trusted server code: a responsable's own view stops at their region, but the
      // answer below is only "covers it or not", never another region's quantities.
      const [depots, regions, stock] = await this.db.run("SYSTEM", (t) =>
        Promise.all([
          t.depot.findMany({ where: { status: "ACTIVE" } }),
          t.region.findMany({ select: { id: true, name: true } }),
          t.stock.findMany({
            where: {
              locationKind: "DEPOT",
              productId: { in: lines.map((l) => l.productId) },
            },
            select: { locationId: true, productId: true, quantity: true },
          }),
        ]),
      );
      const held = new Map(
        stock.map((x) => [`${x.locationId}:${x.productId}`, x.quantity]),
      );
      const regionName = new Map(regions.map((r) => [r.id, r.name]));
      return depots
        .map((d) => {
          const covered = lines
            .map((l) => ({
              productId: l.productId,
              enough: (held.get(`${d.id}:${l.productId}`) ?? 0) >= l.quantity,
            }))
            .sort((a, b) => a.productId.localeCompare(b.productId));
          return {
            id: d.id,
            name: d.name,
            city: d.city,
            regionName: regionName.get(d.regionId) ?? "",
            missing: covered.filter((c) => !c.enough).length,
            lines: covered,
          };
        })
        .sort((a, b) => a.missing - b.missing || a.name.localeCompare(b.name));
    });
  }

  /** The admin picks the grossiste the goods leave from, in any region. The admin may adjust the quantities first. */
  assign(
    actor: Actor,
    id: string,
    input: { depotId: string; lines?: QtyLine[] },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can assign.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "REQUESTED");
      requireRule(
        order.destKind === "PDV",
        "INVALID_STATE",
        "A depot restock is sent directly by BioBalance.",
        409,
      );
      const depot = await tx.depot.findUnique({ where: { id: input.depotId } });
      requireRule(
        depot?.status === "ACTIVE",
        "DEPOT_NOT_FOUND",
        "Choose an active grossiste.",
        404,
      );
      if (input.lines) await this.reshape(tx, order, input.lines);
      const updated = await tx.restockOrder.update({
        where: { id },
        data: {
          status: "ASSIGNED",
          source: "GROSSISTE",
          supplierDepotId: depot.id,
          supplierRegionId: depot.regionId,
          assignedAt: new Date(),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.assigned",
        "RestockOrder",
        id,
        { depot: depot.name },
        order.regionId,
      );
      // The responsable of the grossiste's region ships it; the one who asked is told where it comes from.
      const shippers = await responsableIds(tx, depot.regionId);
      await notify(tx, shippers, {
        key: "restock.to_prepare",
        params: { number: order.number, depot: depot.name },
        entityType: "RestockOrder",
        entityId: id,
      });
      if (!shippers.includes(order.requestedById))
        await this.tellRequester(tx, order, "restock.assigned", {
          number: order.number,
          depot: depot.name,
        });
      return this.one(tx, updated);
    });
  }

  /** BioBalance holds unlimited stock: ship straight to the place. */
  sendDirect(actor: Actor, id: string, input: { lines?: QtyLine[] }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can send directly.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "REQUESTED");
      if (input.lines) await this.reshape(tx, order, input.lines);
      await tx.$executeRaw`UPDATE "RestockLine" SET shipped = requested WHERE "orderId" = ${id}::uuid`;
      const updated = await tx.restockOrder.update({
        where: { id },
        data: {
          status: "SHIPPED",
          source: "BIOBALANCE",
          shippedAt: new Date(),
          assignedAt: new Date(),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.sent_direct",
        "RestockOrder",
        id,
        {},
        order.regionId,
      );
      await this.tellRequester(tx, order, "restock.shipped", {
        number: order.number,
        from: "BioBalance",
      });
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Shipping from a grossiste ─────────────────────────

  /** The responsable of the grossiste's region (or the admin) says what really leaves it. */
  ship(actor: Actor, id: string, input: { lines: QtyLine[] }) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Only the admin or the responsable ships.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "ASSIGNED");
      // The goods leave a grossiste: its region's responsable (or the admin) ships them.
      requireRule(
        order.supplierDepotId &&
          (actor.role === "ADMIN" || order.supplierRegionId === actor.regionId),
        "FORBIDDEN",
        "This order is not yours to ship.",
        403,
      );
      const byProduct = new Map(
        input.lines.map((l) => [l.productId, l.quantity]),
      );
      requireRule(
        byProduct.size === input.lines.length,
        "DUPLICATE_PRODUCT",
        "A product appears twice.",
      );
      for (const l of input.lines)
        requireRule(
          order.lines.some((x) => x.productId === l.productId),
          "PRODUCT_NOT_FOUND",
          "That product is not in the order.",
          422,
        );
      const depot = await findLocation(tx, order.supplierDepotId!);
      let total = 0;
      for (const line of order.lines) {
        const shipped = byProduct.get(line.productId) ?? 0;
        requireRule(
          shipped <= line.requested,
          "TOO_MANY",
          "You cannot ship more than was requested.",
        );
        const have = await currentQuantity(tx, depot.id, line.productId);
        requireRule(
          shipped <= have,
          "INSUFFICIENT_STOCK",
          "The grossiste does not hold enough of a product.",
          409,
        );
        total += shipped;
        await tx.restockLine.update({
          where: { id: line.id },
          data: { shipped },
        });
        // The goods leave the depot now; the destination gets what the admin approves.
        if (shipped > 0)
          await adjustStock(tx, depot, line.productId, -shipped, {
            reason: "SHIPMENT",
            refType: "RestockOrder",
            refId: id,
            actorId: actor.id,
          });
      }
      requireRule(total > 0, "NOTHING_SHIPPED", "Ship at least one unit.");
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "SHIPPED", shippedAt: new Date() },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.shipped",
        "RestockOrder",
        id,
        { units: total },
        order.regionId,
      );
      await this.tellEveryone(
        tx,
        order,
        "restock.shipped",
        { number: order.number, from: depot.name },
        actor.id,
      );
      if (actor.role !== "ADMIN")
        await notifyAdmins(tx, order.regionId, {
          key: "restock.shipped_info",
          params: { number: order.number, by: actor.name },
          entityType: "RestockOrder",
          entityId: id,
        });
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Receipt ─────────────────────────

  /** The responsable picks a team member to count the goods (or takes it back with `null`). */
  setReceiver(actor: Actor, id: string, userId: string | null) {
    requireRule(
      actor.role === "RESPONSABLE",
      "FORBIDDEN",
      "Only the responsable chooses who receives.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id);
      // The store's own responsable, not the one of the grossiste's region who ships it.
      requireRule(
        order.regionId === actor.regionId,
        "FORBIDDEN",
        "Only the responsable of this store chooses who receives.",
        403,
      );
      requireRule(
        order.destKind === "PDV",
        "INVALID_STATE",
        "Not applicable.",
        409,
      );
      requireRule(
        ["REQUESTED", "ASSIGNED", "SHIPPED"].includes(order.status),
        "INVALID_STATE",
        "The delivery was already received.",
        409,
      );
      if (userId) {
        const member = await tx.user.findUnique({ where: { id: userId } });
        requireRule(
          member?.role === "VENDEUR" &&
            member.status === "ACTIVE" &&
            member.pdvId === order.destId &&
            !!member.passwordHash,
          "RECEIVER_INVALID",
          "Choose an active member of this point of sale.",
          422,
        );
      }
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { receiverId: userId },
        include: { lines: true },
      });
      if (userId)
        await notify(tx, [userId], {
          key: "restock.receiver_assigned",
          params: { number: order.number },
          entityType: "RestockOrder",
          entityId: id,
        });
      await audit(
        tx,
        actor,
        "restock.receiver_set",
        "RestockOrder",
        id,
        { userId },
        order.regionId,
      );
      return this.one(tx, updated);
    });
  }

  /**
   * The receiver confirms the delivery with its paper (photos or documents). The admin then
   * enters the quantities received and approves. An admin receiving goods settles at once.
   */
  receive(
    actor: Actor,
    id: string,
    input: {
      photoId?: string;
      photoIds?: string[];
      lines?: QtyLine[];
      note?: string;
    },
  ) {
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "SHIPPED");
      const isReceiver = order.receiverId === actor.id;
      const allowed =
        isReceiver ||
        (actor.role === "RESPONSABLE" && order.regionId === actor.regionId) ||
        (actor.role === "ADMIN" && order.destKind === "DEPOT");
      requireRule(
        allowed,
        "FORBIDDEN",
        "You cannot receive this delivery.",
        403,
      );
      const photoIds = await ownedProofs(
        tx,
        actor,
        input.photoIds ?? (input.photoId ? [input.photoId] : []),
        "Add a photo of the delivery paper.",
        { regionId: order.regionId },
      );
      // Quantities counted at the store, from apps that still send them: the admin starts from them.
      if (input.lines) {
        const counted = new Map(
          input.lines.map((l) => [l.productId, l.quantity]),
        );
        requireRule(
          counted.size === input.lines.length,
          "DUPLICATE_PRODUCT",
          "A product appears twice.",
        );
        for (const l of input.lines)
          requireRule(
            order.lines.some(
              (x) => x.productId === l.productId && (x.shipped ?? 0) > 0,
            ),
            "PRODUCT_NOT_FOUND",
            "That product was not shipped.",
            422,
          );
        for (const line of order.lines.filter((x) => (x.shipped ?? 0) > 0))
          requireRule(
            counted.has(line.productId),
            "LINE_MISSING",
            "Enter the quantity received for every product.",
          );
        for (const line of order.lines)
          await tx.restockLine.update({
            where: { id: line.id },
            data: { received: counted.get(line.productId) ?? 0 },
          });
      }
      const updated = await tx.restockOrder.update({
        where: { id },
        data: {
          status: "RECEIVED",
          receiptPhotoId: photoIds[0],
          receiptPhotoIds: photoIds,
          receivedAt: new Date(),
          receiptNote: input.note?.trim() || null,
          decisionNote: null,
          ...(isReceiver ? {} : { receiverId: actor.id }),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.received",
        "RestockOrder",
        id,
        { note: input.note ?? null },
        order.regionId,
      );
      // The admin counting a delivery is also the one who approves it.
      if (actor.role === "ADMIN") return this.settle(tx, actor, updated);
      await notifyAdmins(tx, order.regionId, {
        key: "restock.received",
        params: { number: order.number, by: actor.name },
        entityType: "RestockOrder",
        entityId: id,
      });
      return this.one(tx, updated);
    });
  }

  /** The admin checks the photo against the quantities and approves them, as counted or corrected. */
  approve(
    actor: Actor,
    id: string,
    input: { lines?: QtyLine[]; note?: string },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can approve.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "RECEIVED");
      const overrides = new Map(
        (input.lines ?? []).map((l) => [l.productId, l.quantity]),
      );
      for (const productId of overrides.keys())
        requireRule(
          order.lines.some((l) => l.productId === productId),
          "PRODUCT_NOT_FOUND",
          "That product is not in the order.",
          422,
        );
      return this.settle(tx, actor, order, overrides, input.note);
    });
  }

  /** Put the approved quantities into the destination's stock and close the order. */
  private async settle(
    tx: Tx,
    actor: Actor,
    order: Order,
    overrides: Map<string, number> = new Map(),
    note?: string,
  ) {
    const dest = await findLocation(tx, order.destId);
    let amended = 0;
    for (const line of order.lines) {
      // What the admin entered, else what the store counted (older apps), else what was sent.
      const expected = line.received ?? line.shipped ?? 0;
      const approved = overrides.get(line.productId) ?? expected;
      if (approved !== expected) amended++;
      await tx.restockLine.update({
        where: { id: line.id },
        data: { approved },
      });
      if (approved === 0) continue;
      await adjustStock(tx, dest, line.productId, approved, {
        reason: "RECEIPT",
        refType: "RestockOrder",
        refId: order.id,
        actorId: actor.id,
      });
    }
    const updated = await tx.restockOrder.update({
      where: { id: order.id },
      data: {
        status: "COMPLETED",
        decidedById: actor.id,
        decidedAt: new Date(),
        decisionNote: note?.trim() || null,
      },
      include: { lines: true },
    });
    await audit(
      tx,
      actor,
      "restock.approved",
      "RestockOrder",
      order.id,
      { amended },
      order.regionId,
    );
    await this.tellEveryone(
      tx,
      order,
      "restock.completed",
      { number: order.number, amended, note: note ?? null },
      actor.id,
    );
    return this.one(tx, updated);
  }

  /**
   * The admin corrects the quantities received of a delivery they approved less than 6 hours ago.
   * Only the difference reaches the destination's stock, which never goes below what already left.
   */
  amend(actor: Actor, id: string, input: { lines: QtyLine[]; note?: string }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can amend.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "COMPLETED");
      if (!withinDecisionWindow(order.decidedAt)) throw decisionLocked();
      const overrides = new Map(
        input.lines.map((l) => [l.productId, l.quantity]),
      );
      requireRule(
        overrides.size === input.lines.length,
        "DUPLICATE_PRODUCT",
        "A product appears twice.",
      );
      for (const productId of overrides.keys())
        requireRule(
          order.lines.some((l) => l.productId === productId),
          "PRODUCT_NOT_FOUND",
          "That product is not in the order.",
          422,
        );
      const dest = await findLocation(tx, order.destId);
      const changes = order.lines
        .map((l) => ({
          line: l,
          before: l.approved ?? 0,
          target: overrides.get(l.productId) ?? l.approved ?? 0,
        }))
        .filter((c) => c.target !== c.before);
      const tooLow: { productId: string; name: string; minimum: number }[] = [];
      for (const c of changes.filter((x) => x.target < x.before)) {
        await tx.$queryRaw`SELECT 1 FROM "Stock" WHERE "locationId"=${dest.id}::uuid AND "productId"=${c.line.productId}::uuid FOR UPDATE`;
        const have = await currentQuantity(tx, dest.id, c.line.productId);
        if (have + (c.target - c.before) < 0)
          tooLow.push({
            productId: c.line.productId,
            name:
              (
                await tx.product.findUnique({
                  where: { id: c.line.productId },
                  select: { name: true },
                })
              )?.name ?? "",
            minimum: c.before - have,
          });
      }
      if (tooLow.length)
        throw new DomainError(
          "BELOW_SOLD",
          "Some of these units already left this place (sold or shipped): a quantity cannot go below what was used.",
          409,
          { products: tooLow },
        );
      for (const c of changes) {
        await adjustStock(tx, dest, c.line.productId, c.target - c.before, {
          reason: "RECEIPT",
          refType: "RestockOrder",
          refId: id,
          actorId: actor.id,
        });
        await tx.restockLine.update({
          where: { id: c.line.id },
          data: { approved: c.target },
        });
      }
      await audit(
        tx,
        actor,
        "restock.amended",
        "RestockOrder",
        id,
        {
          changed: changes.length,
          note: input.note ?? null,
          before: Object.fromEntries(
            changes.map((c) => [c.line.productId, c.before]),
          ),
          after: Object.fromEntries(
            changes.map((c) => [c.line.productId, c.target]),
          ),
        },
        order.regionId,
      );
      await this.tellEveryone(
        tx,
        order,
        "restock.amended",
        { number: order.number },
        actor.id,
      );
      return this.one(tx, await this.load(tx, id));
    });
  }

  /**
   * The admin takes back the routing of an order (given to a grossiste that has not shipped, or sent
   * from BioBalance and not yet received) within 6 hours, to route it again.
   */
  reopen(actor: Actor, id: string) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id);
      const direct =
        order.status === "SHIPPED" &&
        order.source === "BIOBALANCE" &&
        !order.receivedAt;
      requireRule(
        order.status === "ASSIGNED" || direct,
        "INVALID_STATE",
        "Only an order that no grossiste has shipped yet can be taken back.",
        409,
      );
      if (!withinDecisionWindow(order.assignedAt)) throw decisionLocked();
      if (direct)
        await tx.restockLine.updateMany({
          where: { orderId: id },
          data: { shipped: null },
        });
      const updated = await tx.restockOrder.update({
        where: { id },
        data: {
          status: "REQUESTED",
          source: null,
          supplierDepotId: null,
          supplierRegionId: null,
          assignedAt: null,
          shippedAt: null,
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.reopened",
        "RestockOrder",
        id,
        { was: order.status },
        order.regionId,
      );
      await notify(
        tx,
        [
          order.requestedById,
          ...(order.supplierRegionId
            ? await responsableIds(tx, order.supplierRegionId)
            : []),
        ],
        {
          key: "restock.reopened",
          params: { number: order.number },
          entityType: "RestockOrder",
          entityId: id,
        },
      );
      return this.one(tx, updated);
    });
  }

  reject(actor: Actor, id: string, note: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can reject.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id, "RECEIVED");
      const updated = await tx.restockOrder.update({
        where: { id },
        data: {
          status: "SHIPPED",
          decisionNote: note,
          decidedById: actor.id,
          decidedAt: new Date(),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.receipt_rejected",
        "RestockOrder",
        id,
        { note },
        order.regionId,
      );
      const recipients = [order.receiverId, order.requestedById].filter(
        (x): x is string => !!x,
      );
      await notify(tx, recipients, {
        key: "restock.receipt_rejected",
        params: { number: order.number, note },
        entityType: "RestockOrder",
        entityId: id,
      });
      return this.one(tx, updated);
    });
  }

  cancel(actor: Actor, id: string, reason: string) {
    return this.db.run(actor, async (tx) => {
      const order = await this.load(tx, id);
      const own =
        order.requestedById === actor.id && order.status === "REQUESTED";
      requireRule(
        actor.role === "ADMIN" || own,
        "FORBIDDEN",
        "You cannot cancel this order.",
        403,
      );
      requireRule(
        ["REQUESTED", "ASSIGNED", "SHIPPED"].includes(order.status),
        "INVALID_STATE",
        "This order can no longer be cancelled.",
        409,
      );
      // Goods already on the road go back to the depot they left.
      if (order.status === "SHIPPED" && order.supplierDepotId) {
        const depot = await findLocation(tx, order.supplierDepotId);
        for (const line of order.lines)
          if ((line.shipped ?? 0) > 0)
            await adjustStock(tx, depot, line.productId, line.shipped!, {
              reason: "SHIPMENT",
              refType: "RestockOrder",
              refId: id,
              actorId: actor.id,
            });
      }
      const updated = await tx.restockOrder.update({
        where: { id },
        data: { status: "CANCELLED", cancelReason: reason },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "restock.cancelled",
        "RestockOrder",
        id,
        { reason },
        order.regionId,
      );
      await this.tellEveryone(
        tx,
        order,
        "restock.cancelled",
        { number: order.number, reason },
        actor.id,
      );
      return this.one(tx, updated);
    });
  }

  // ───────────────────────── Reading ─────────────────────────

  list(
    actor: Actor,
    filter: {
      status?: OrderStatus;
      regionId?: string;
      destId?: string;
      active?: boolean;
    },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "VENDEUR"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const orders = await tx.restockOrder.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.active && {
            status: {
              in: [
                "REQUESTED",
                "ASSIGNED",
                "SHIPPED",
                "RECEIVED",
              ] as OrderStatus[],
            },
          }),
          ...(filter.destId && { destId: filter.destId }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
        },
        include: { lines: true },
        orderBy: { createdAt: "desc" },
        take: 200,
      });
      return this.many(tx, orders);
    });
  }

  get(actor: Actor, id: string) {
    // A plain read: no row lock, so viewing an order never holds up someone acting on it.
    return this.db.run(actor, async (tx) => {
      const order = await tx.restockOrder.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!order) throw notFound("Restock");
      return this.one(tx, order);
    });
  }

  // ───────────────────────── Helpers ─────────────────────────

  /** Lock the order and check it is in the expected state. */
  private async load(
    tx: Tx,
    id: string,
    expected?: OrderStatus,
  ): Promise<Order> {
    const visible = await tx.restockOrder.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!visible) throw notFound("Restock");
    await this.db.lock(tx, "RestockOrder", id);
    const order = await tx.restockOrder.findUniqueOrThrow({
      where: { id },
      include: { lines: true },
    });
    if (expected && order.status !== expected)
      throw new DomainError(
        "INVALID_STATE",
        `This order is ${order.status.toLowerCase()}, not ${expected.toLowerCase()}.`,
        409,
      );
    return order;
  }

  private async checkLines(tx: Tx, lines: QtyLine[]) {
    const ids = lines.map((l) => l.productId);
    requireRule(
      new Set(ids).size === ids.length,
      "DUPLICATE_PRODUCT",
      "A product appears twice.",
    );
    requireRule(
      (await tx.product.count({ where: { id: { in: ids }, active: true } })) ===
        ids.length,
      "PRODUCT_NOT_FOUND",
      "Unknown or inactive product.",
      404,
    );
  }

  /** Replace the requested lines (the admin adjusting before routing). */
  private async reshape(tx: Tx, order: Order, lines: QtyLine[]) {
    await this.checkLines(tx, lines);
    await tx.restockLine.deleteMany({ where: { orderId: order.id } });
    await tx.restockLine.createMany({
      data: lines.map((l) => ({
        orderId: order.id,
        productId: l.productId,
        requested: l.quantity,
      })),
    });
  }

  private tellRequester(
    tx: Tx,
    order: Order,
    key: string,
    params: Record<string, unknown>,
  ) {
    return notify(tx, [order.requestedById], {
      key,
      params,
      entityType: "RestockOrder",
      entityId: order.id,
    });
  }

  private async tellEveryone(
    tx: Tx,
    order: Order,
    key: string,
    params: Record<string, unknown>,
    except?: string,
  ) {
    const region = [
      ...(order.regionId ? await responsableIds(tx, order.regionId) : []),
      ...(order.supplierRegionId
        ? await responsableIds(tx, order.supplierRegionId)
        : []),
    ];
    const ids = [order.requestedById, order.receiverId, ...region].filter(
      (x): x is string => !!x && x !== except,
    );
    await notify(tx, ids, {
      key,
      params,
      entityType: "RestockOrder",
      entityId: order.id,
    });
  }

  private async many(tx: Tx, orders: Order[]) {
    if (!orders.length) return [];
    const productIds = [
      ...new Set(orders.flatMap((o) => o.lines.map((l) => l.productId))),
    ];
    const placeIds = [
      ...new Set(
        orders.flatMap((o) =>
          [o.destId, o.supplierDepotId, o.suggestedDepotId].filter(
            (x): x is string => !!x,
          ),
        ),
      ),
    ];
    const userIds = [
      ...new Set(
        orders.flatMap((o) =>
          [o.requestedById, o.receiverId, o.decidedById].filter(
            (x): x is string => !!x,
          ),
        ),
      ),
    ];
    const [products, pdvs, depots, users] = await Promise.all([
      tx.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, name: true, family: true },
      }),
      tx.pdv.findMany({
        where: { id: { in: placeIds } },
        select: { id: true, name: true },
      }),
      tx.depot.findMany({
        where: { id: { in: placeIds } },
        select: { id: true, name: true },
      }),
      tx.user.findMany({
        where: { id: { in: userIds } },
        select: { id: true, name: true },
      }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    // A grossiste of another region is not in the responsable's own view: its name is all they get.
    const unseen = orders
      .map((o) => o.suggestedDepotId)
      .filter((x): x is string => !!x && !place.has(x));
    if (unseen.length)
      for (const d of await this.db.run("SYSTEM", (t) =>
        t.depot.findMany({
          where: { id: { in: unseen } },
          select: { id: true, name: true },
        }),
      ))
        place.set(d.id, d.name);
    const user = new Map(users.map((u) => [u.id, u.name]));
    const who = (id: string | null) =>
      id ? { id, name: user.get(id) ?? "" } : null;
    return orders.map((o) => ({
      id: o.id,
      number: o.number,
      status: o.status,
      source: o.source,
      note: o.note,
      regionId: o.regionId,
      destination: {
        id: o.destId,
        kind: o.destKind,
        name: place.get(o.destId) ?? "",
      },
      supplier: o.supplierDepotId
        ? {
            id: o.supplierDepotId,
            name: place.get(o.supplierDepotId) ?? "",
            regionId: o.supplierRegionId,
          }
        : null,
      requestedBy: who(o.requestedById),
      receiver: who(o.receiverId),
      decidedBy: who(o.decidedById),
      createdAt: o.createdAt,
      assignedAt: o.assignedAt,
      shippedAt: o.shippedAt,
      receivedAt: o.receivedAt,
      decidedAt: o.decidedAt,
      receiptPhotoId: o.receiptPhotoId,
      receiptPhotoIds: o.receiptPhotoIds.length
        ? o.receiptPhotoIds
        : o.receiptPhotoId
          ? [o.receiptPhotoId]
          : [],
      receiptNote: o.receiptNote,
      decisionNote: o.decisionNote,
      cancelReason: o.cancelReason,
      /** The grossiste the responsable suggested (the admin decides). */
      suggestedSupplier: o.suggestedDepotId
        ? { id: o.suggestedDepotId, name: place.get(o.suggestedDepotId) ?? "" }
        : null,
      lines: o.lines
        .map((l) => ({
          productId: l.productId,
          name: product.get(l.productId)?.name ?? "",
          family: product.get(l.productId)?.family ?? "",
          requested: l.requested,
          shipped: l.shipped,
          received: l.received,
          approved: l.approved,
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    }));
  }

  private async one(tx: Tx, order: Order) {
    return (await this.many(tx, [order]))[0]!;
  }
}
