import { Injectable } from "@nestjs/common";
import type {
  Pdv,
  StockTransfer,
  TransferDirection,
  TransferLine,
  TransferRevision,
  TransferStatus,
} from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, json, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { ownedProofs } from "../media/proofs";
import { adjustStock, findLocation } from "../stock/ledger";

const MAX_LINES = 30;
const MAX_QUANTITY = 100_000;
/** A transfer nobody decided in three days is dropped: the shelves have moved on. */
export const TRANSFER_LIFE_MS = 3 * 86_400_000;

export interface TransferLineInput {
  productId: string;
  quantity: number;
}

export interface TransferInput {
  fromPdvId: string;
  toPdvId: string;
  direction: TransferDirection;
  lines: TransferLineInput[];
  photoId?: string;
  note?: string;
}

type Party = Pick<
  Pdv,
  "id" | "name" | "address" | "city" | "regionId" | "groupId" | "status"
>;
type Full = StockTransfer & {
  lines: TransferLine[];
  revisions?: TransferRevision[];
};

/**
 * Products that move between two paras of the same group. The two paras settle it by phone, then
 * someone records it here with one photo; the admin approves the quantities and only then does the
 * stock move, in one transaction. Made by the admin, it moves at once, with no photo.
 */
@Injectable()
export class TransfersService {
  constructor(private readonly db: Database) {}

  // ───────────────────────────── Checks ─────────────────────────────

  private normalise(lines: TransferLineInput[]) {
    requireRule(
      lines.length >= 1 && lines.length <= MAX_LINES,
      "NO_LINES",
      `Add between 1 and ${MAX_LINES} products.`,
    );
    const ids = lines.map((l) => l.productId);
    requireRule(
      new Set(ids).size === ids.length,
      "DUPLICATE_PRODUCT",
      "A product appears twice.",
    );
    for (const l of lines)
      requireRule(
        Number.isInteger(l.quantity) &&
          l.quantity >= 1 &&
          l.quantity <= MAX_QUANTITY,
        "INVALID_QUANTITY",
        "Quantities are whole numbers above zero.",
      );
    return lines.map((l) => ({ productId: l.productId, quantity: l.quantity }));
  }

  /** Both paras, checked: they exist, are active and belong to the same group. Read as trusted work (a team member cannot see the other para). */
  private async parties(fromId: string, toId: string) {
    requireRule(fromId !== toId, "SAME_PLACE", "Choose two different paras.");
    return this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.pdv.findMany({
        where: { id: { in: [fromId, toId] } },
        select: {
          id: true,
          name: true,
          address: true,
          city: true,
          regionId: true,
          groupId: true,
          status: true,
        },
      });
      const from = rows.find((r) => r.id === fromId);
      const to = rows.find((r) => r.id === toId);
      requireRule(from && to, "PARA_NOT_FOUND", "Unknown para.", 404);
      requireRule(
        from.groupId && from.groupId === to.groupId,
        "NOT_SAME_GROUP",
        "Only paras of the same group can exchange products.",
      );
      requireRule(
        from.status === "ACTIVE" && to.status === "ACTIVE",
        "PLACE_INACTIVE",
        "Both paras must be active.",
      );
      const group = await tx.group.findUnique({
        where: { id: from.groupId },
        select: { id: true, name: true, status: true },
      });
      requireRule(
        group?.status === "ACTIVE",
        "GROUP_INACTIVE",
        "The group is not active.",
      );
      return { from: from as Party, to: to as Party, group };
    });
  }

  /** Who may act on a pair of paras: a team member of either, the responsable of the region, the admin. */
  private mayAct(actor: Actor, from: Party, to: Party) {
    const ok =
      actor.role === "ADMIN" ||
      (actor.role === "RESPONSABLE" && actor.regionId === from.regionId) ||
      (actor.role === "VENDEUR" &&
        (actor.pdvId === from.id || actor.pdvId === to.id));
    requireRule(ok, "FORBIDDEN", "This is not one of your paras.", 403);
  }

  private async products(ids: string[]) {
    return this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.product.findMany({
        where: { id: { in: ids } },
        select: { id: true, name: true, family: true, active: true },
      });
      requireRule(
        rows.length === ids.length && rows.every((r) => r.active),
        "PRODUCT_NOT_FOUND",
        "Unknown or inactive product.",
        404,
      );
      return new Map(rows.map((r) => [r.id, r]));
    });
  }

  /** What the sending para holds now (a team member of the other para cannot read it: trusted read). */
  private async available(fromId: string, productIds: string[]) {
    return this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.stock.findMany({
        where: { locationId: fromId, productId: { in: productIds } },
        select: { productId: true, quantity: true },
      });
      return new Map(rows.map((r) => [r.productId, r.quantity]));
    });
  }

  private shortage(
    lines: TransferLineInput[],
    held: Map<string, number>,
    names: Map<string, { name: string }>,
    fromName: string,
  ) {
    const short = lines
      .filter((l) => (held.get(l.productId) ?? 0) < l.quantity)
      .map((l) => ({
        productId: l.productId,
        name: names.get(l.productId)?.name ?? "?",
        available: held.get(l.productId) ?? 0,
        wanted: l.quantity,
      }));
    if (short.length)
      throw new DomainError(
        "TRANSFER_STOCK",
        `${fromName} does not hold enough of ${short.map((s) => s.name).join(", ")}.`,
        409,
        { from: fromName, products: short },
      );
  }

  // ───────────────────────────── Making one ─────────────────────────────

  /** Paras of the same group as `pdvId` (default: the team member's own), to choose who to exchange with. */
  async partners(actor: Actor, pdvId?: string) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const id = actor.role === "VENDEUR" ? actor.pdvId : (pdvId ?? actor.pdvId);
    requireRule(id, "PARA_NOT_FOUND", "Choose a para.", 404);
    return this.db.run("SYSTEM", async (tx) => {
      const own = await tx.pdv.findUnique({ where: { id } });
      requireRule(own, "PARA_NOT_FOUND", "Unknown para.", 404);
      requireRule(
        actor.role === "ADMIN" ||
          (actor.role === "RESPONSABLE" && actor.regionId === own.regionId) ||
          (actor.role === "VENDEUR" && actor.pdvId === own.id),
        "FORBIDDEN",
        "This is not one of your paras.",
        403,
      );
      if (!own.groupId) return { group: null, partners: [] };
      const group = await tx.group.findUnique({ where: { id: own.groupId } });
      const peers = await tx.pdv.findMany({
        where: {
          groupId: own.groupId,
          status: "ACTIVE",
          id: { not: own.id },
        },
        select: { id: true, name: true, address: true, city: true },
        orderBy: { name: "asc" },
      });
      return {
        group: group && { id: group.id, name: group.name },
        partners: peers,
      };
    });
  }

  async create(actor: Actor, input: TransferInput) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const lines = this.normalise(input.lines);
    const { from, to, group } = await this.parties(
      input.fromPdvId,
      input.toPdvId,
    );
    this.mayAct(actor, from, to);
    // A team member always speaks for their own para.
    const direction: TransferDirection =
      actor.role === "VENDEUR"
        ? actor.pdvId === from.id
          ? "SEND"
          : "REQUEST"
        : input.direction;
    const names = await this.products(lines.map((l) => l.productId));
    const held = await this.available(
      from.id,
      lines.map((l) => l.productId),
    );
    this.shortage(lines, held, names, from.name);
    const direct = actor.role === "ADMIN";
    const created = await this.db.run(actor, async (tx) => {
      const photoIds = direct
        ? []
        : await ownedProofs(
            tx,
            actor,
            input.photoId ? [input.photoId] : [],
            "Add one photo as proof.",
            { regionId: from.regionId },
          );
      requireRule(
        photoIds.length <= 1,
        "TOO_MANY_PHOTOS",
        "One photo is enough.",
      );
      const [sequence] = await tx.$queryRaw<
        { n: bigint }[]
      >`SELECT nextval('transfer_number_seq') AS n`;
      const number = `TR-${new Date().getUTCFullYear()}-${String(sequence!.n).padStart(6, "0")}`;
      const transfer = await tx.stockTransfer.create({
        data: {
          number,
          regionId: from.regionId,
          groupId: group.id,
          fromPdvId: from.id,
          toPdvId: to.id,
          direction,
          status: direct ? "APPROVED" : "PENDING",
          createdById: actor.id,
          photoId: photoIds[0] ?? null,
          note: input.note?.trim() || null,
          expiresAt: direct ? null : new Date(Date.now() + TRANSFER_LIFE_MS),
          ...(direct && { decidedById: actor.id, decidedAt: new Date() }),
          lines: {
            create: lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
              requestedQuantity: l.quantity,
            })),
          },
        },
        include: { lines: true },
      });
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      if (direct) {
        await this.apply(tx, actor, transfer, lines);
        await audit(
          tx,
          actor,
          "transfer.approved",
          "StockTransfer",
          transfer.id,
          { number, units, direct: true },
          from.regionId,
        );
        await notify(tx, await this.audience(tx, transfer, actor.id), {
          key: "transfer.approved",
          params: { number, from: from.name, to: to.name, units },
          entityType: "StockTransfer",
          entityId: transfer.id,
        });
      } else {
        await audit(
          tx,
          actor,
          "transfer.requested",
          "StockTransfer",
          transfer.id,
          { number, units, direction },
          from.regionId,
        );
        await notifyAdmins(tx, from.regionId, {
          key: "transfer.requested",
          params: { by: actor.name, from: from.name, to: to.name, units },
          entityType: "StockTransfer",
          entityId: transfer.id,
        });
        // The responsable of the region knows what their team members record.
        if (actor.role === "VENDEUR")
          await notify(tx, await responsableIds(tx, from.regionId), {
            key: "transfer.requested",
            params: { by: actor.name, from: from.name, to: to.name, units },
            entityType: "StockTransfer",
            entityId: transfer.id,
            push: false,
          });
      }
      return transfer.id;
    });
    return this.get(actor, created);
  }

  /** The stock moves: out of the sender, into the receiver, with a history line each. */
  private async apply(
    tx: Tx,
    actor: Actor,
    transfer: Pick<StockTransfer, "id" | "fromPdvId" | "toPdvId">,
    lines: TransferLineInput[],
  ) {
    const from = await findLocation(tx, transfer.fromPdvId);
    const to = await findLocation(tx, transfer.toPdvId);
    for (const l of lines) {
      const ref = {
        refType: "StockTransfer",
        refId: transfer.id,
        actorId: actor.id,
      };
      await adjustStock(tx, from, l.productId, -l.quantity, {
        reason: "TRANSFER_OUT",
        ...ref,
      });
      await adjustStock(tx, to, l.productId, l.quantity, {
        reason: "TRANSFER_IN",
        ...ref,
      });
    }
  }

  /** Everyone who should hear of the outcome: the creator, the region's responsable, the teams of both paras. */
  private async audience(tx: Tx, t: StockTransfer, except?: string) {
    const sellers = await tx.user.findMany({
      where: {
        role: "VENDEUR",
        status: "ACTIVE",
        pdvId: { in: [t.fromPdvId, t.toPdvId] },
      },
      select: { id: true },
    });
    const ids = new Set([
      t.createdById,
      ...(await responsableIds(tx, t.regionId)),
      ...sellers.map((s) => s.id),
    ]);
    if (except) ids.delete(except);
    return [...ids];
  }

  // ───────────────────────────── Changing, cancelling ─────────────────────────────

  private async mine(tx: Tx, actor: Actor, id: string): Promise<Full> {
    await this.db.lock(tx, "StockTransfer", id);
    const t = await tx.stockTransfer.findUnique({
      where: { id },
      include: { lines: true },
    });
    if (!t) throw notFound("Transfer");
    requireRule(
      actor.role === "ADMIN" ||
        (actor.role === "RESPONSABLE" && actor.regionId === t.regionId) ||
        (actor.role === "VENDEUR" &&
          (actor.pdvId === t.fromPdvId || actor.pdvId === t.toPdvId)),
      "FORBIDDEN",
      "This is not one of your paras.",
      403,
    );
    return t;
  }

  /** The quantities are changed (by either para, or its responsable) while the admin has not decided. */
  async edit(actor: Actor, id: string, input: { lines: TransferLineInput[] }) {
    const lines = this.normalise(input.lines);
    const current = await this.db.run(actor, (tx) => this.mine(tx, actor, id));
    requireRule(
      current.status === "PENDING",
      "INVALID_STATE",
      "Only a transfer waiting for the admin can be changed.",
      409,
    );
    const names = await this.products(lines.map((l) => l.productId));
    const held = await this.available(
      current.fromPdvId,
      lines.map((l) => l.productId),
    );
    const fromName = (await this.names([current.fromPdvId])).get(
      current.fromPdvId,
    )!;
    this.shortage(lines, held, names, fromName);
    await this.db.run(actor, async (tx) => {
      const t = await this.mine(tx, actor, id);
      requireRule(
        t.status === "PENDING",
        "INVALID_STATE",
        "Only a transfer waiting for the admin can be changed.",
        409,
      );
      await this.revise(tx, actor, t, lines);
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      await audit(
        tx,
        actor,
        "transfer.changed",
        "StockTransfer",
        id,
        { number: t.number, units },
        t.regionId,
      );
      const place = await this.names([t.fromPdvId, t.toPdvId]);
      const params = {
        by: actor.name,
        number: t.number,
        from: place.get(t.fromPdvId),
        to: place.get(t.toPdvId),
        units,
      };
      await notifyAdmins(tx, t.regionId, {
        key: "transfer.changed",
        params,
        entityType: "StockTransfer",
        entityId: id,
      });
      await notify(tx, await this.audience(tx, t, actor.id), {
        key: "transfer.changed",
        params,
        entityType: "StockTransfer",
        entityId: id,
        push: false,
      });
    });
    return this.get(actor, id);
  }

  /** Replace the lines, keeping what was first asked, and write who changed what. */
  private async revise(
    tx: Tx,
    actor: Actor,
    t: Full,
    lines: TransferLineInput[],
  ) {
    const before = t.lines.map((l) => ({
      productId: l.productId,
      quantity: l.quantity,
    }));
    const same =
      before.length === lines.length &&
      before.every((b) =>
        lines.some(
          (l) => l.productId === b.productId && l.quantity === b.quantity,
        ),
      );
    if (same) return false;
    const asked = new Map(
      t.lines.map((l) => [l.productId, l.requestedQuantity]),
    );
    await tx.transferLine.deleteMany({ where: { transferId: t.id } });
    await tx.transferLine.createMany({
      data: lines.map((l) => ({
        transferId: t.id,
        productId: l.productId,
        quantity: l.quantity,
        requestedQuantity: asked.get(l.productId) ?? 0,
      })),
    });
    const version = t.revision + 1;
    await tx.transferRevision.create({
      data: {
        transferId: t.id,
        version,
        editorId: actor.id,
        before: json(before),
        after: json(lines),
      },
    });
    await tx.stockTransfer.update({
      where: { id: t.id },
      data: {
        revision: version,
        expiresAt: new Date(Date.now() + TRANSFER_LIFE_MS),
      },
    });
    return true;
  }

  async cancel(actor: Actor, id: string) {
    await this.db.run(actor, async (tx) => {
      const t = await this.mine(tx, actor, id);
      requireRule(
        t.status === "PENDING",
        "INVALID_STATE",
        "Only a transfer waiting for the admin can be cancelled.",
        409,
      );
      await tx.stockTransfer.update({
        where: { id },
        data: { status: "CANCELLED" },
      });
      await audit(
        tx,
        actor,
        "transfer.cancelled",
        "StockTransfer",
        id,
        { number: t.number },
        t.regionId,
      );
    });
    return this.get(actor, id);
  }

  // ───────────────────────────── The admin decides ─────────────────────────────

  /**
   * Approve: the quantities may be corrected on the way (what the admin writes is what moves). The
   * stock is checked again now, and moves in this one transaction.
   */
  async approve(
    actor: Actor,
    id: string,
    input: { note?: string; lines?: TransferLineInput[] },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin approves.",
      403,
    );
    const wanted = input.lines ? this.normalise(input.lines) : null;
    if (wanted) await this.products(wanted.map((l) => l.productId));
    await this.db.run(actor, async (tx) => {
      const t = await this.mine(tx, actor, id);
      requireRule(
        t.status === "PENDING",
        "INVALID_STATE",
        "This transfer is not waiting any more.",
        409,
      );
      const lines =
        wanted ??
        t.lines.map((l) => ({ productId: l.productId, quantity: l.quantity }));
      if (wanted) await this.revise(tx, actor, t, wanted);
      // The stock the sender holds right now (a sale may have taken some since it was made).
      const rows = await tx.stock.findMany({
        where: {
          locationId: t.fromPdvId,
          productId: { in: lines.map((l) => l.productId) },
        },
        select: { productId: true, quantity: true },
      });
      const names = await this.products(lines.map((l) => l.productId));
      const fromName = (await this.names([t.fromPdvId])).get(t.fromPdvId)!;
      this.shortage(
        lines,
        new Map(rows.map((r) => [r.productId, r.quantity])),
        names,
        fromName,
      );
      await this.apply(tx, actor, t, lines);
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      const done = await tx.stockTransfer.update({
        where: { id },
        data: {
          status: "APPROVED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: input.note?.trim() || null,
          expiresAt: null,
        },
      });
      await audit(
        tx,
        actor,
        "transfer.approved",
        "StockTransfer",
        id,
        { number: t.number, units, changed: wanted !== null },
        t.regionId,
      );
      const place = await this.names([t.fromPdvId, t.toPdvId]);
      await notify(tx, await this.audience(tx, done, actor.id), {
        key: "transfer.approved",
        params: {
          number: t.number,
          from: place.get(t.fromPdvId),
          to: place.get(t.toPdvId),
          units,
        },
        entityType: "StockTransfer",
        entityId: id,
      });
    });
    return this.get(actor, id);
  }

  async reject(actor: Actor, id: string, input: { note: string }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin decides.",
      403,
    );
    await this.db.run(actor, async (tx) => {
      const t = await this.mine(tx, actor, id);
      requireRule(
        t.status === "PENDING",
        "INVALID_STATE",
        "This transfer is not waiting any more.",
        409,
      );
      const done = await tx.stockTransfer.update({
        where: { id },
        data: {
          status: "REJECTED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: input.note.trim(),
          expiresAt: null,
        },
      });
      await audit(
        tx,
        actor,
        "transfer.rejected",
        "StockTransfer",
        id,
        { number: t.number, note: input.note.trim() },
        t.regionId,
      );
      await notify(tx, await this.audience(tx, done, actor.id), {
        key: "transfer.rejected",
        params: { number: t.number, note: input.note.trim() },
        entityType: "StockTransfer",
        entityId: id,
      });
    });
    return this.get(actor, id);
  }

  // ───────────────────────────── Reading ─────────────────────────────

  /** Names of paras, read as trusted work (a team member cannot read the other para). */
  private async names(ids: string[]) {
    return this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.pdv.findMany({
        where: { id: { in: ids } },
        select: { id: true, name: true },
      });
      return new Map(rows.map((r) => [r.id, r.name]));
    });
  }

  async list(
    actor: Actor,
    filter: { status?: TransferStatus; pdvId?: string },
  ) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const rows = await this.db.run(actor, (tx) =>
      tx.stockTransfer.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.pdvId && {
            OR: [{ fromPdvId: filter.pdvId }, { toPdvId: filter.pdvId }],
          }),
        },
        include: { lines: true },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: 100,
      }),
    );
    return this.present(actor, rows, false);
  }

  async get(actor: Actor, id: string) {
    const row = await this.db.run(actor, (tx) =>
      tx.stockTransfer.findUnique({
        where: { id },
        include: { lines: true, revisions: { orderBy: { version: "asc" } } },
      }),
    );
    if (!row) throw notFound("Transfer");
    return (await this.present(actor, [row], true))[0]!;
  }

  private async present(actor: Actor, rows: Full[], detail: boolean) {
    const placeIds = [
      ...new Set(rows.flatMap((r) => [r.fromPdvId, r.toPdvId])),
    ];
    const productIds = [
      ...new Set(
        rows.flatMap((r) => [
          ...r.lines.map((l) => l.productId),
          ...(r.revisions ?? []).flatMap((rev) => [
            ...(rev.before as { productId: string }[]).map((l) => l.productId),
            ...(rev.after as { productId: string }[]).map((l) => l.productId),
          ]),
        ]),
      ),
    ];
    const peopleIds = [
      ...new Set(
        rows.flatMap((r) => [
          r.createdById,
          ...(r.decidedById ? [r.decidedById] : []),
          ...(r.revisions ?? []).map((rev) => rev.editorId),
        ]),
      ),
    ];
    const [places, products, people, groups] = await this.db.run(
      "SYSTEM",
      async (tx) =>
        Promise.all([
          tx.pdv.findMany({
            where: { id: { in: placeIds } },
            select: { id: true, name: true, address: true, city: true },
          }),
          tx.product.findMany({
            where: { id: { in: productIds } },
            select: { id: true, name: true, family: true },
          }),
          tx.user.findMany({
            where: { id: { in: peopleIds } },
            select: { id: true, name: true, role: true },
          }),
          tx.group.findMany({
            where: { id: { in: rows.map((r) => r.groupId) } },
            select: { id: true, name: true },
          }),
        ]),
    );
    const place = new Map(places.map((p) => [p.id, p]));
    const product = new Map(products.map((p) => [p.id, p]));
    const person = new Map(people.map((p) => [p.id, p]));
    const group = new Map(groups.map((g) => [g.id, g.name]));
    const mine = (r: Full) =>
      actor.role === "ADMIN" ||
      (actor.role === "RESPONSABLE" && actor.regionId === r.regionId) ||
      (actor.role === "VENDEUR" &&
        (actor.pdvId === r.fromPdvId || actor.pdvId === r.toPdvId));
    const side = (id: string) => {
      const p = place.get(id);
      return {
        id,
        name: p?.name ?? "?",
        address: p?.address ?? "",
        city: p?.city ?? "",
      };
    };
    const who = (id: string | null) =>
      id
        ? { id, name: person.get(id)?.name ?? "?", role: person.get(id)?.role }
        : null;
    return rows.map((r) => ({
      id: r.id,
      number: r.number,
      status: r.status,
      direction: r.direction,
      group: { id: r.groupId, name: group.get(r.groupId) ?? "" },
      from: side(r.fromPdvId),
      to: side(r.toPdvId),
      createdBy: who(r.createdById),
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      note: r.note,
      photoId: r.photoId,
      revision: r.revision,
      decidedBy: who(r.decidedById),
      decidedAt: r.decidedAt,
      decisionNote: r.decisionNote,
      units: r.lines.reduce((s, l) => s + l.quantity, 0),
      lines: [...r.lines]
        .sort((a, b) =>
          (product.get(a.productId)?.name ?? "").localeCompare(
            product.get(b.productId)?.name ?? "",
          ),
        )
        .map((l) => ({
          productId: l.productId,
          name: product.get(l.productId)?.name ?? "?",
          family: product.get(l.productId)?.family ?? "",
          quantity: l.quantity,
          requestedQuantity: l.requestedQuantity,
        })),
      // What the viewer may do now.
      canEdit: r.status === "PENDING" && mine(r),
      canCancel: r.status === "PENDING" && mine(r),
      canDecide: r.status === "PENDING" && actor.role === "ADMIN",
      changes: detail
        ? (r.revisions ?? []).map((rev) => ({
            version: rev.version,
            at: rev.createdAt,
            by: who(rev.editorId),
            before: (rev.before as unknown as TransferLineInput[]).map((l) => ({
              name: product.get(l.productId)?.name ?? "?",
              quantity: l.quantity,
            })),
            after: (rev.after as unknown as TransferLineInput[]).map((l) => ({
              name: product.get(l.productId)?.name ?? "?",
              quantity: l.quantity,
            })),
          }))
        : undefined,
    }));
  }

  // ───────────────────────────── Housekeeping ─────────────────────────────

  /** Transfers the admin did not decide in time are dropped, and the people who made them told. */
  async expire(now = new Date()) {
    await this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.$queryRaw<
        { id: string; number: string; createdById: string; regionId: string }[]
      >`
        UPDATE "StockTransfer" SET status = 'EXPIRED', "updatedAt" = now()
        WHERE status = 'PENDING' AND "expiresAt" <= ${now}
        RETURNING id, number, "createdById", "regionId"`;
      for (const r of rows) {
        await notify(
          tx,
          [r.createdById, ...(await responsableIds(tx, r.regionId))],
          {
            key: "transfer.expired",
            params: { number: r.number },
            entityType: "StockTransfer",
            entityId: r.id,
          },
        );
        await audit(
          tx,
          null,
          "transfer.expired",
          "StockTransfer",
          r.id,
          {
            number: r.number,
          },
          r.regionId,
        );
      }
    });
  }
}
