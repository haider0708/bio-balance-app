import { Injectable } from "@nestjs/common";
import type {
  ReturnAction,
  ReturnLine,
  ReturnRevision,
  ReturnStatus,
  StockReturn,
} from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, json, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { adjustStock, findLocation } from "../stock/ledger";

const MAX_LINES = 30;
const MAX_QUANTITY = 100_000;
/** A return nobody decided in three days is dropped: the shelves have moved on. */
export const RETURN_LIFE_MS = 3 * 86_400_000;

export interface ReturnLineInput {
  productId: string;
  quantity: number;
}

type Full = StockReturn & {
  lines: ReturnLine[];
  revisions?: ReturnRevision[];
};

/**
 * A return takes quantities out of one para's stock. The responsable of the region asks, the admin
 * decides (and may correct the quantities); only then does the stock leave. Made by the admin, for
 * any para, it applies at once.
 */
@Injectable()
export class ReturnsService {
  constructor(private readonly db: Database) {}

  private normalise(lines: ReturnLineInput[]) {
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

  /** The para, checked: it exists, is active, and the actor may act on it (a responsable: their region's). */
  private async para(actor: Actor, pdvId: string) {
    requireRule(
      actor.role === "RESPONSABLE" || actor.role === "ADMIN",
      "FORBIDDEN",
      "Only a responsable or the admin handles returns.",
      403,
    );
    const pdv = await this.db.run("SYSTEM", (tx) =>
      tx.pdv.findUnique({
        where: { id: pdvId },
        select: { id: true, name: true, regionId: true, status: true },
      }),
    );
    requireRule(
      pdv && (actor.role === "ADMIN" || actor.regionId === pdv.regionId),
      "PARA_NOT_FOUND",
      "Unknown para.",
      404,
    );
    requireRule(
      pdv.status === "ACTIVE",
      "PLACE_INACTIVE",
      "This para is not active.",
    );
    return pdv;
  }

  /** The para that receives a moved quantity: any other active para (the admin's choice, any region). */
  private async destination(pdvId: string, toPdvId: string) {
    requireRule(toPdvId !== pdvId, "SAME_PLACE", "Choose two different paras.");
    const to = await this.db.run("SYSTEM", (tx) =>
      tx.pdv.findUnique({
        where: { id: toPdvId },
        select: { id: true, name: true, regionId: true, status: true },
      }),
    );
    requireRule(to, "PARA_NOT_FOUND", "Unknown para.", 404);
    requireRule(
      to.status === "ACTIVE",
      "PLACE_INACTIVE",
      "This para is not active.",
    );
    return to;
  }

  private async products(ids: string[]) {
    return this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.product.findMany({
        where: { id: { in: ids } },
        select: { id: true, name: true, family: true },
      });
      requireRule(
        rows.length === ids.length,
        "PRODUCT_NOT_FOUND",
        "Unknown product.",
        404,
      );
      return new Map(rows.map((r) => [r.id, r]));
    });
  }

  private shortage(
    lines: ReturnLineInput[],
    held: Map<string, number>,
    names: Map<string, { name: string }>,
    paraName: string,
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
        "RETURN_STOCK",
        `${paraName} does not hold enough of ${short.map((s) => s.name).join(", ")}.`,
        409,
        { para: paraName, products: short },
      );
  }

  private async held(tx: Tx, pdvId: string, productIds: string[]) {
    const rows = await tx.stock.findMany({
      where: { locationId: pdvId, productId: { in: productIds } },
      select: { productId: true, quantity: true },
    });
    return new Map(rows.map((r) => [r.productId, r.quantity]));
  }

  // ───────────────────────────── Asking, making ─────────────────────────────

  async create(
    actor: Actor,
    input: {
      pdvId: string;
      action?: ReturnAction;
      toPdvId?: string;
      lines: ReturnLineInput[];
      note?: string;
    },
  ) {
    const action = input.action ?? "REMOVE";
    requireRule(
      actor.role === "ADMIN" || action === "REMOVE",
      "FORBIDDEN",
      "Only the admin can move or add quantities.",
      403,
    );
    requireRule(
      action === "MOVE" ? !!input.toPdvId : !input.toPdvId,
      "INVALID_ACTION",
      action === "MOVE"
        ? "Choose the para that receives."
        : "Only a move has a receiving para.",
    );
    const lines = this.normalise(input.lines);
    const pdv = await this.para(actor, input.pdvId);
    const to = input.toPdvId
      ? await this.destination(pdv.id, input.toPdvId)
      : null;
    const names = await this.products(lines.map((l) => l.productId));
    const direct = actor.role === "ADMIN";
    const id = await this.db.run(actor, async (tx) => {
      // Quantities leaving a para must be there; adding only needs the products to exist.
      if (action !== "ADD")
        this.shortage(
          lines,
          await this.held(
            tx,
            pdv.id,
            lines.map((l) => l.productId),
          ),
          names,
          pdv.name,
        );
      const [sequence] = await tx.$queryRaw<
        { n: bigint }[]
      >`SELECT nextval('return_number_seq') AS n`;
      const number = `RT-${new Date().getUTCFullYear()}-${String(sequence!.n).padStart(6, "0")}`;
      const created = await tx.stockReturn.create({
        data: {
          number,
          regionId: pdv.regionId,
          pdvId: pdv.id,
          action,
          toPdvId: to?.id ?? null,
          status: direct ? "APPROVED" : "PENDING",
          createdById: actor.id,
          note: input.note?.trim() || null,
          expiresAt: direct ? null : new Date(Date.now() + RETURN_LIFE_MS),
          ...(direct && { decidedById: actor.id, decidedAt: new Date() }),
          lines: {
            create: lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
              requestedQuantity: l.quantity,
            })),
          },
        },
      });
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      if (direct) {
        await this.apply(tx, actor, created, lines);
        await audit(
          tx,
          actor,
          "return.approved",
          "StockReturn",
          created.id,
          { number, units, action, direct: true },
          pdv.regionId,
        );
        await notify(tx, await this.audience(tx, created, actor.id), {
          key: this.outcomeKey(action),
          params: { number, para: pdv.name, to: to?.name ?? "", units },
          entityType: "StockReturn",
          entityId: created.id,
        });
      } else {
        await audit(
          tx,
          actor,
          "return.requested",
          "StockReturn",
          created.id,
          { number, units },
          pdv.regionId,
        );
        await notifyAdmins(tx, pdv.regionId, {
          key: "return.requested",
          params: { by: actor.name, para: pdv.name, units },
          entityType: "StockReturn",
          entityId: created.id,
        });
      }
      return created.id;
    });
    return this.get(actor, id);
  }

  /** The notice sent when the stock has moved: it says what was done. */
  private outcomeKey(action: ReturnAction) {
    return action === "MOVE"
      ? "return.moved"
      : action === "ADD"
        ? "return.added"
        : "return.approved";
  }

  /**
   * The stock moves, with a history line each: out of the para (remove, move), into the receiving
   * para (move), or only into the para (add).
   */
  private async apply(
    tx: Tx,
    actor: Actor,
    r: Pick<StockReturn, "id" | "pdvId" | "action" | "toPdvId">,
    lines: ReturnLineInput[],
  ) {
    const ref = { refType: "StockReturn", refId: r.id, actorId: actor.id };
    const place = await findLocation(tx, r.pdvId);
    const receiver =
      r.action === "MOVE" && r.toPdvId
        ? await findLocation(tx, r.toPdvId)
        : null;
    for (const l of lines) {
      if (r.action === "ADD")
        await adjustStock(tx, place, l.productId, l.quantity, {
          reason: "RETURN_IN",
          ...ref,
        });
      else {
        await adjustStock(tx, place, l.productId, -l.quantity, {
          reason: "RETURN_OUT",
          ...ref,
        });
        if (receiver)
          await adjustStock(tx, receiver, l.productId, l.quantity, {
            reason: "RETURN_IN",
            ...ref,
          });
      }
    }
  }

  /** Everyone who should hear of the outcome: whoever asked, and the region's responsable. */
  private async audience(tx: Tx, r: StockReturn, except?: string) {
    const ids = new Set([
      r.createdById,
      ...(await responsableIds(tx, r.regionId)),
    ]);
    // A para that receives is told through its own region's responsable.
    if (r.toPdvId) {
      const to = await tx.pdv.findUnique({
        where: { id: r.toPdvId },
        select: { regionId: true },
      });
      if (to)
        for (const id of await responsableIds(tx, to.regionId)) ids.add(id);
    }
    if (except) ids.delete(except);
    return [...ids];
  }

  // ───────────────────────────── Changing, cancelling ─────────────────────────────

  private async mine(tx: Tx, actor: Actor, id: string): Promise<Full> {
    await this.db.lock(tx, "StockReturn", id);
    const r = await tx.stockReturn.findUnique({
      where: { id },
      include: { lines: true },
    });
    if (!r) throw notFound("Return");
    requireRule(
      actor.role === "ADMIN" ||
        (actor.role === "RESPONSABLE" && actor.regionId === r.regionId),
      "FORBIDDEN",
      "This is not one of your paras.",
      403,
    );
    return r;
  }

  async edit(actor: Actor, id: string, input: { lines: ReturnLineInput[] }) {
    const lines = this.normalise(input.lines);
    await this.db.run(actor, async (tx) => {
      const r = await this.mine(tx, actor, id);
      requireRule(
        r.status === "PENDING",
        "INVALID_STATE",
        "Only a return waiting for the admin can be changed.",
        409,
      );
      const names = await this.products(lines.map((l) => l.productId));
      const para = await tx.pdv.findUniqueOrThrow({ where: { id: r.pdvId } });
      this.shortage(
        lines,
        await this.held(
          tx,
          r.pdvId,
          lines.map((l) => l.productId),
        ),
        names,
        para.name,
      );
      const changed = await this.revise(tx, actor, r, lines);
      if (!changed) return;
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      await audit(
        tx,
        actor,
        "return.changed",
        "StockReturn",
        id,
        { number: r.number, units },
        r.regionId,
      );
      await notifyAdmins(tx, r.regionId, {
        key: "return.changed",
        params: { by: actor.name, number: r.number, para: para.name, units },
        entityType: "StockReturn",
        entityId: id,
      });
    });
    return this.get(actor, id);
  }

  /** Replace the lines, keeping what was first asked, and write who changed what. */
  private async revise(
    tx: Tx,
    actor: Actor,
    r: Full,
    lines: ReturnLineInput[],
  ) {
    const before = r.lines.map((l) => ({
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
      r.lines.map((l) => [l.productId, l.requestedQuantity]),
    );
    await tx.returnLine.deleteMany({ where: { returnId: r.id } });
    await tx.returnLine.createMany({
      data: lines.map((l) => ({
        returnId: r.id,
        productId: l.productId,
        quantity: l.quantity,
        requestedQuantity: asked.get(l.productId) ?? 0,
      })),
    });
    const version = r.revision + 1;
    await tx.returnRevision.create({
      data: {
        returnId: r.id,
        version,
        editorId: actor.id,
        before: json(before),
        after: json(lines),
      },
    });
    await tx.stockReturn.update({
      where: { id: r.id },
      data: {
        revision: version,
        expiresAt: new Date(Date.now() + RETURN_LIFE_MS),
      },
    });
    return true;
  }

  async cancel(actor: Actor, id: string) {
    await this.db.run(actor, async (tx) => {
      const r = await this.mine(tx, actor, id);
      requireRule(
        r.status === "PENDING",
        "INVALID_STATE",
        "Only a return waiting for the admin can be cancelled.",
        409,
      );
      await tx.stockReturn.update({
        where: { id },
        data: { status: "CANCELLED" },
      });
      await audit(
        tx,
        actor,
        "return.cancelled",
        "StockReturn",
        id,
        { number: r.number },
        r.regionId,
      );
    });
    return this.get(actor, id);
  }

  // ───────────────────────────── The admin decides ─────────────────────────────

  /**
   * Approve. The admin may correct the quantities on the way, and may choose to move them to another
   * para instead of only taking them out (`toPdvId`).
   */
  async approve(
    actor: Actor,
    id: string,
    input: { note?: string; lines?: ReturnLineInput[]; toPdvId?: string },
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
      const r = await this.mine(tx, actor, id);
      requireRule(
        r.status === "PENDING",
        "INVALID_STATE",
        "This return is not waiting any more.",
        409,
      );
      const lines =
        wanted ??
        r.lines.map((l) => ({ productId: l.productId, quantity: l.quantity }));
      if (wanted) await this.revise(tx, actor, r, wanted);
      const para = await tx.pdv.findUniqueOrThrow({ where: { id: r.pdvId } });
      // Moved instead of only taken out: the receiving para is chosen now.
      let target: StockReturn = r;
      let toName = "";
      if (input.toPdvId) {
        requireRule(
          r.action === "REMOVE",
          "INVALID_ACTION",
          "Only a return to take out can be moved.",
        );
        const to = await this.destination(r.pdvId, input.toPdvId);
        toName = to.name;
        target = await tx.stockReturn.update({
          where: { id },
          data: { action: "MOVE", toPdvId: to.id },
        });
      } else if (r.toPdvId) {
        toName =
          (
            await tx.pdv.findUnique({
              where: { id: r.toPdvId },
              select: { name: true },
            })
          )?.name ?? "";
      }
      // What the para holds right now (a sale may have taken some since it was asked).
      this.shortage(
        lines,
        await this.held(
          tx,
          r.pdvId,
          lines.map((l) => l.productId),
        ),
        await this.products(lines.map((l) => l.productId)),
        para.name,
      );
      await this.apply(tx, actor, target, lines);
      const units = lines.reduce((s, l) => s + l.quantity, 0);
      const done = await tx.stockReturn.update({
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
        "return.approved",
        "StockReturn",
        id,
        {
          number: r.number,
          units,
          action: target.action,
          changed: wanted !== null,
        },
        r.regionId,
      );
      await notify(tx, await this.audience(tx, done, actor.id), {
        key: this.outcomeKey(target.action),
        params: { number: r.number, para: para.name, to: toName, units },
        entityType: "StockReturn",
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
      const r = await this.mine(tx, actor, id);
      requireRule(
        r.status === "PENDING",
        "INVALID_STATE",
        "This return is not waiting any more.",
        409,
      );
      const done = await tx.stockReturn.update({
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
        "return.rejected",
        "StockReturn",
        id,
        { number: r.number, note: input.note.trim() },
        r.regionId,
      );
      await notify(tx, await this.audience(tx, done, actor.id), {
        key: "return.rejected",
        params: { number: r.number, note: input.note.trim() },
        entityType: "StockReturn",
        entityId: id,
      });
    });
    return this.get(actor, id);
  }

  // ───────────────────────────── Reading ─────────────────────────────

  async list(actor: Actor, filter: { status?: ReturnStatus; pdvId?: string }) {
    requireRule(
      actor.role === "RESPONSABLE" ||
        actor.role === "ADMIN" ||
        actor.role === "ORDERS",
      "FORBIDDEN",
      "Only a responsable, the order manager or the admin sees returns.",
      403,
    );
    const rows = await this.db.run(actor, (tx) =>
      tx.stockReturn.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.pdvId && { pdvId: filter.pdvId }),
        },
        include: { lines: true },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: 100,
      }),
    );
    return this.present(actor, rows, false);
  }

  async get(actor: Actor, id: string) {
    requireRule(
      actor.role === "RESPONSABLE" ||
        actor.role === "ADMIN" ||
        actor.role === "ORDERS",
      "FORBIDDEN",
      "Only a responsable, the order manager or the admin sees returns.",
      403,
    );
    const row = await this.db.run(actor, (tx) =>
      tx.stockReturn.findUnique({
        where: { id },
        include: { lines: true, revisions: { orderBy: { version: "asc" } } },
      }),
    );
    if (!row) throw notFound("Return");
    return (await this.present(actor, [row], true))[0]!;
  }

  private async present(actor: Actor, rows: Full[], detail: boolean) {
    const productIds = [
      ...new Set(
        rows.flatMap((r) => [
          ...r.lines.map((l) => l.productId),
          ...(r.revisions ?? []).flatMap((rev) => [
            ...(rev.before as unknown as { productId: string }[]).map(
              (l) => l.productId,
            ),
            ...(rev.after as unknown as { productId: string }[]).map(
              (l) => l.productId,
            ),
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
    const [paras, products, people, regions] = await this.db.run(
      "SYSTEM",
      (tx) =>
        Promise.all([
          tx.pdv.findMany({
            where: {
              id: {
                in: rows.flatMap((r) => [
                  r.pdvId,
                  ...(r.toPdvId ? [r.toPdvId] : []),
                ]),
              },
            },
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
          tx.region.findMany({
            where: { id: { in: rows.map((r) => r.regionId) } },
            select: { id: true, name: true },
          }),
        ]),
    );
    const para = new Map(paras.map((p) => [p.id, p]));
    const product = new Map(products.map((p) => [p.id, p]));
    const person = new Map(people.map((p) => [p.id, p]));
    const region = new Map(regions.map((r) => [r.id, r.name]));
    const who = (id: string | null) =>
      id
        ? { id, name: person.get(id)?.name ?? "?", role: person.get(id)?.role }
        : null;
    return rows.map((r) => ({
      id: r.id,
      number: r.number,
      status: r.status,
      region: region.get(r.regionId) ?? "",
      action: r.action,
      to: r.toPdvId
        ? {
            id: r.toPdvId,
            name: para.get(r.toPdvId)?.name ?? "?",
            address: para.get(r.toPdvId)?.address ?? "",
            city: para.get(r.toPdvId)?.city ?? "",
          }
        : null,
      para: {
        id: r.pdvId,
        name: para.get(r.pdvId)?.name ?? "?",
        address: para.get(r.pdvId)?.address ?? "",
        city: para.get(r.pdvId)?.city ?? "",
      },
      createdBy: who(r.createdById),
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      note: r.note,
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
      canEdit: r.status === "PENDING" && actor.role !== "ORDERS",
      canCancel: r.status === "PENDING" && actor.role !== "ORDERS",
      canDecide: r.status === "PENDING" && actor.role === "ADMIN",
      changes: detail
        ? (r.revisions ?? []).map((rev) => ({
            version: rev.version,
            at: rev.createdAt,
            by: who(rev.editorId),
            before: (rev.before as unknown as ReturnLineInput[]).map((l) => ({
              name: product.get(l.productId)?.name ?? "?",
              quantity: l.quantity,
            })),
            after: (rev.after as unknown as ReturnLineInput[]).map((l) => ({
              name: product.get(l.productId)?.name ?? "?",
              quantity: l.quantity,
            })),
          }))
        : undefined,
    }));
  }

  // ───────────────────────────── Housekeeping ─────────────────────────────

  /** Returns the admin did not decide in time are dropped, and whoever asked is told. */
  async expire(now = new Date()) {
    await this.db.run("SYSTEM", async (tx) => {
      const rows = await tx.$queryRaw<
        { id: string; number: string; createdById: string; regionId: string }[]
      >`
        UPDATE "StockReturn" SET status = 'EXPIRED', "updatedAt" = now()
        WHERE status = 'PENDING' AND "expiresAt" <= ${now}
        RETURNING id, number, "createdById", "regionId"`;
      for (const r of rows) {
        await notify(
          tx,
          [r.createdById, ...(await responsableIds(tx, r.regionId))],
          {
            key: "return.expired",
            params: { number: r.number },
            entityType: "StockReturn",
            entityId: r.id,
          },
        );
        await audit(
          tx,
          null,
          "return.expired",
          "StockReturn",
          r.id,
          { number: r.number },
          r.regionId,
        );
      }
    });
  }
}
