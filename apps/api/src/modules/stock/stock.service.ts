import { ownedProofs } from "../media/proofs";
import { Injectable } from "@nestjs/common";
import type { Approval, Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { randomUUID } from "node:crypto";
import {
  currentQuantity,
  findLocation,
  setStock,
  type Location,
} from "./ledger";

export interface DeclarationLineInput {
  productId: string;
  quantity: number;
}

const LOW_STOCK = 5;

@Injectable()
export class StockService {
  constructor(private readonly db: Database) {}

  /** May this person look at or declare the stock of this place? */
  private async authorize(
    tx: Tx,
    actor: Actor,
    locationId: string,
  ): Promise<Location> {
    const location = await findLocation(tx, locationId);
    const ok =
      actor.role === "ADMIN" ||
      (actor.role === "RESPONSABLE" &&
        location.stockRegionId !== null &&
        location.stockRegionId === actor.regionId) ||
      (actor.role === "GROSSISTE" &&
        location.kind === "DEPOT" &&
        location.id === actor.depotId) ||
      // A team member reads their own store's stock (to see what can be sold), nothing else.
      (actor.role === "VENDEUR" &&
        location.kind === "PDV" &&
        location.id === actor.pdvId);
    if (!ok) throw notFound("Location");
    return location;
  }

  /** Quantities at one place, with product details; low and negative stock flagged. */
  async levels(actor: Actor, locationId: string) {
    return this.db.run(actor, async (tx) => {
      const location = await this.authorize(tx, actor, locationId);
      const rows = await tx.stock.findMany({ where: { locationId } });
      const products = await tx.product.findMany({
        where: { id: { in: rows.map((r) => r.productId) } },
      });
      const byId = new Map(products.map((p) => [p.id, p]));
      return {
        location: {
          id: location.id,
          kind: location.kind,
          name: location.name,
          status: location.status,
        },
        items: rows
          .map((r) => {
            const p = byId.get(r.productId)!;
            return {
              productId: r.productId,
              name: p.name,
              family: p.family,
              imageId: p.imageId,
              quantity: r.quantity,
              level:
                r.quantity < 0
                  ? "NEGATIVE"
                  : r.quantity <= LOW_STOCK
                    ? "LOW"
                    : "OK",
              updatedAt: r.updatedAt,
            };
          })
          .sort((a, b) => a.name.localeCompare(b.name)),
      };
    });
  }

  /** Recent movements of one product at one place. */
  async movements(actor: Actor, locationId: string, productId: string) {
    return this.db.run(actor, async (tx) => {
      await this.authorize(tx, actor, locationId);
      return tx.stockMovement.findMany({
        where: { locationId, productId },
        orderBy: { createdAt: "desc" },
        take: 100,
      });
    });
  }

  // ───────────────────────── Declarations ─────────────────────────

  async declare(
    actor: Actor,
    input: {
      locationId: string;
      photoId?: string;
      photoIds?: string[];
      note?: string;
      lines: DeclarationLineInput[];
    },
  ) {
    requireRule(
      ["RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Only a responsable or grossiste declares stock.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const location = await this.authorize(tx, actor, input.locationId);
      requireRule(
        ["PENDING", "ACTIVE"].includes(location.status),
        "INVALID_STATE",
        "This place cannot receive stock now.",
        409,
      );
      // Counted once. A place that was counted (or is being counted) can only be
      // counted again after the admin allowed it, and the permission is used once.
      const open = await tx.stockDeclaration.findFirst({
        where: {
          locationId: location.id,
          status: { in: ["PENDING", "REVIEW"] },
        },
      });
      requireRule(
        !open,
        "ALREADY_COUNTED",
        "The stock of this place was already declared.",
        409,
      );
      const counted = await tx.stockDeclaration.findFirst({
        where: { locationId: location.id, status: "APPROVED" },
      });
      const permit = counted
        ? await tx.stockRecount.findFirst({
            where: {
              locationId: location.id,
              status: "APPROVED",
              declarationId: null,
            },
            orderBy: { decidedAt: "asc" },
          })
        : null;
      requireRule(
        !counted || permit,
        "ALREADY_COUNTED",
        "The stock of this place was already declared.",
        409,
      );
      // Photos prove what is on the shelves (one to five); a place with nothing needs none.
      const photoIds =
        input.lines.length > 0
          ? await ownedProofs(
              tx,
              actor,
              input.photoIds ?? (input.photoId ? [input.photoId] : []),
              "Add a photo of the stock.",
            )
          : [];
      const ids = input.lines.map((l) => l.productId);
      requireRule(
        new Set(ids).size === ids.length,
        "DUPLICATE_PRODUCT",
        "A product appears twice.",
      );
      const found = await tx.product.count({
        where: { id: { in: ids }, active: true },
      });
      requireRule(
        found === ids.length,
        "PRODUCT_NOT_FOUND",
        "Unknown or inactive product.",
        404,
      );
      // A grossiste's count is checked by the responsable of the region before it reaches the admin.
      const regionBoss =
        actor.role === "GROSSISTE" && location.stockRegionId
          ? await responsableIds(tx, location.stockRegionId)
          : [];
      const toReview = regionBoss.length > 0;
      const declaration = await tx.stockDeclaration.create({
        data: {
          kind: counted ? "COUNT" : "INITIAL",
          status: toReview ? "REVIEW" : "PENDING",
          locationId: location.id,
          locationKind: location.kind,
          regionId: location.stockRegionId,
          photoId: photoIds[0] ?? null,
          photoIds,
          note: input.note?.trim() || null,
          createdById: actor.id,
          lines: {
            create: input.lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
            })),
          },
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "stock.declared",
        "StockDeclaration",
        declaration.id,
        { location: location.name, lines: input.lines.length },
        location.regionId,
      );
      if (permit)
        await tx.stockRecount.update({
          where: { id: permit.id },
          data: { declarationId: declaration.id },
        });
      const notice = {
        key: toReview ? "stock.to_review" : "stock.submitted",
        params: {
          place: location.name,
          by: actor.name,
          kind: declaration.kind,
        },
        entityType: "StockDeclaration",
        entityId: declaration.id,
      };
      if (toReview) await notify(tx, regionBoss, notice);
      else await notifyAdmins(tx, notice);
      return (await this.present(tx, [declaration]))[0]!;
    });
  }

  list(
    actor: Actor,
    filter: { status?: Approval; regionId?: string; locationId?: string },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.stockDeclaration.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.locationId && { locationId: filter.locationId }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
        },
        include: { lines: true },
        orderBy: { createdAt: "desc" },
        take: 200,
      });
      return this.present(tx, rows);
    });
  }

  async get(actor: Actor, id: string) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const row = await tx.stockDeclaration.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!row) throw notFound("Stock declaration");
      return (await this.present(tx, [row]))[0]!;
    });
  }

  /** The admin approves the quantities as declared, or corrects some of them first. */
  approve(
    actor: Actor,
    id: string,
    input: { lines?: DeclarationLineInput[]; note?: string },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can approve.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockDeclaration", id);
      const declaration = await tx.stockDeclaration.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!declaration) throw notFound("Stock declaration");
      requireRule(
        declaration.status === "PENDING",
        "INVALID_STATE",
        "This declaration was already decided.",
        409,
      );
      const overrides = new Map(
        (input.lines ?? []).map((l) => [l.productId, l.quantity]),
      );
      for (const productId of overrides.keys())
        requireRule(
          declaration.lines.some((l) => l.productId === productId),
          "PRODUCT_NOT_FOUND",
          "That product is not in the declaration.",
          422,
        );
      const location = await findLocation(tx, declaration.locationId);
      let amended = 0;
      for (const line of declaration.lines) {
        const approved = overrides.get(line.productId) ?? line.quantity;
        if (approved !== line.quantity) amended++;
        await tx.stockDeclarationLine.update({
          where: { id: line.id },
          data: { approvedQuantity: approved },
        });
        await setStock(tx, location, line.productId, approved, {
          reason: "DECLARATION",
          refType: "StockDeclaration",
          refId: id,
          actorId: actor.id,
        });
      }
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          status: "APPROVED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: input.note?.trim() || null,
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "stock.approved",
        "StockDeclaration",
        id,
        { amended },
        declaration.regionId,
      );
      await this.tell(
        tx,
        declaration,
        "stock.approved",
        location.name,
        input.note,
        amended,
      );
      return (await this.present(tx, [updated]))[0]!;
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
      await this.db.lock(tx, "StockDeclaration", id);
      const declaration = await tx.stockDeclaration.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!declaration) throw notFound("Stock declaration");
      requireRule(
        declaration.status === "PENDING",
        "INVALID_STATE",
        "This declaration was already decided.",
        409,
      );
      const location = await findLocation(tx, declaration.locationId);
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          status: "REJECTED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: note,
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "stock.rejected",
        "StockDeclaration",
        id,
        { note },
        declaration.regionId,
      );
      await this.tell(
        tx,
        declaration,
        "stock.rejected",
        location.name,
        note,
        0,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /**
   * The responsable of the region checks a grossiste's count (photos and numbers)
   * and passes it to the admin, or sends it back.
   */
  review(
    actor: Actor,
    id: string,
    input: { action: "approve" | "reject"; note?: string },
  ) {
    requireRule(
      actor.role === "RESPONSABLE" && actor.regionId,
      "FORBIDDEN",
      "Only the responsable of the region checks this.",
      403,
    );
    requireRule(
      input.action === "approve" || input.note?.trim(),
      "NOTE_REQUIRED",
      "Explain what is wrong.",
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockDeclaration", id);
      const declaration = await tx.stockDeclaration.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!declaration || declaration.regionId !== actor.regionId)
        throw notFound("Stock declaration");
      requireRule(
        declaration.status === "REVIEW",
        "INVALID_STATE",
        "This count is not waiting for your check.",
        409,
      );
      const location = await findLocation(tx, declaration.locationId);
      const passed = input.action === "approve";
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          status: passed ? "PENDING" : "REJECTED",
          reviewedById: actor.id,
          reviewedAt: new Date(),
          reviewNote: input.note?.trim() || null,
          ...(passed
            ? {}
            : {
                decidedById: actor.id,
                decidedAt: new Date(),
                decisionNote: input.note?.trim(),
              }),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        passed ? "stock.reviewed" : "stock.review_rejected",
        "StockDeclaration",
        id,
        { note: input.note ?? null },
        declaration.regionId,
      );
      if (passed)
        await notifyAdmins(tx, {
          key: "stock.submitted",
          params: {
            place: location.name,
            by: actor.name,
            kind: declaration.kind,
          },
          entityType: "StockDeclaration",
          entityId: id,
        });
      else
        await notify(tx, [declaration.createdById], {
          key: "stock.rejected",
          params: { place: location.name, note: input.note ?? null },
          entityType: "StockDeclaration",
          entityId: id,
        });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /**
   * The admin corrects a place's quantities directly (a mistake found later, goods lost).
   * Each change is a movement in the history, with the reason, and the people in charge are told.
   */
  adjust(
    actor: Actor,
    input: {
      locationId: string;
      reason: string;
      lines: DeclarationLineInput[];
    },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin corrects stock.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const location = await findLocation(tx, input.locationId);
      const ids = input.lines.map((l) => l.productId);
      requireRule(
        new Set(ids).size === ids.length,
        "DUPLICATE_PRODUCT",
        "A product appears twice.",
      );
      requireRule(
        (await tx.product.count({ where: { id: { in: ids } } })) === ids.length,
        "PRODUCT_NOT_FOUND",
        "Unknown product.",
        404,
      );
      const ref = randomUUID();
      let changed = 0;
      for (const line of input.lines) {
        const before = await currentQuantity(tx, location.id, line.productId);
        if (before === line.quantity) continue;
        changed++;
        await setStock(tx, location, line.productId, line.quantity, {
          reason: "ADJUSTMENT",
          refType: "Adjustment",
          refId: ref,
          actorId: actor.id,
        });
      }
      await audit(
        tx,
        actor,
        "stock.adjusted",
        "Location",
        location.id,
        { reason: input.reason, changed },
        location.stockRegionId,
      );
      if (changed > 0) {
        const owner =
          location.kind === "DEPOT"
            ? (await tx.depot.findUnique({ where: { id: location.id } }))
                ?.userId
            : null;
        await notify(
          tx,
          [
            ...(owner ? [owner] : []),
            ...(location.stockRegionId
              ? await responsableIds(tx, location.stockRegionId)
              : []),
          ],
          {
            key: "stock.adjusted",
            params: {
              place: location.name,
              note: input.reason,
              amended: changed,
            },
            entityType: "Location",
            entityId: location.id,
          },
        );
      }
      return { changed };
    });
  }

  // ───────────────────────── Counting again ─────────────────────────

  /** Ask the admin for permission to count a place again. */
  requestRecount(actor: Actor, input: { locationId: string; reason: string }) {
    requireRule(
      ["RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const location = await this.authorize(tx, actor, input.locationId);
      requireRule(
        await tx.stockDeclaration.findFirst({
          where: { locationId: location.id, status: "APPROVED" },
        }),
        "NOT_COUNTED_YET",
        "This place has not been counted yet: declare its stock first.",
        409,
      );
      requireRule(
        !(await tx.stockDeclaration.findFirst({
          where: {
            locationId: location.id,
            status: { in: ["PENDING", "REVIEW"] },
          },
        })),
        "DECLARATION_PENDING",
        "A count is already waiting.",
        409,
      );
      requireRule(
        !(await tx.stockRecount.findFirst({
          where: {
            locationId: location.id,
            OR: [
              { status: "PENDING" },
              { status: "APPROVED", declarationId: null },
            ],
          },
        })),
        "RECOUNT_PENDING",
        "A recount was already asked for this place.",
        409,
      );
      const row = await tx.stockRecount.create({
        data: {
          locationId: location.id,
          locationKind: location.kind,
          regionId: location.stockRegionId,
          requestedById: actor.id,
          reason: input.reason.trim(),
        },
      });
      await audit(
        tx,
        actor,
        "stock.recount_requested",
        "StockRecount",
        row.id,
        { place: location.name },
        location.stockRegionId,
      );
      await notifyAdmins(tx, {
        key: "recount.requested",
        params: { place: location.name, by: actor.name },
        entityType: "StockRecount",
        entityId: row.id,
      });
      return (await this.presentRecounts(tx, [row]))[0]!;
    });
  }

  listRecounts(
    actor: Actor,
    filter: { status?: Approval; locationId?: string },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) =>
      this.presentRecounts(
        tx,
        await tx.stockRecount.findMany({
          where: {
            ...(filter.status && { status: filter.status }),
            ...(filter.locationId && { locationId: filter.locationId }),
          },
          orderBy: { createdAt: "desc" },
          take: 100,
        }),
      ),
    );
  }

  decideRecount(
    actor: Actor,
    id: string,
    action: "approve" | "reject",
    note?: string,
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin decides.",
      403,
    );
    requireRule(
      action === "approve" || note?.trim(),
      "NOTE_REQUIRED",
      "Explain your decision.",
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockRecount", id);
      const row = await tx.stockRecount.findUnique({ where: { id } });
      if (!row) throw notFound("Recount request");
      requireRule(
        row.status === "PENDING",
        "INVALID_STATE",
        "This request was already decided.",
        409,
      );
      const location = await findLocation(tx, row.locationId);
      const updated = await tx.stockRecount.update({
        where: { id },
        data: {
          status: action === "approve" ? "APPROVED" : "REJECTED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: note?.trim() || null,
        },
      });
      await audit(
        tx,
        actor,
        `stock.recount_${action}d`,
        "StockRecount",
        id,
        { note: note ?? null },
        row.regionId,
      );
      await notify(
        tx,
        [
          row.requestedById,
          ...(row.regionId ? await responsableIds(tx, row.regionId) : []),
        ],
        {
          key: action === "approve" ? "recount.approved" : "recount.rejected",
          params: { place: location.name, note: note ?? null },
          entityType: "StockRecount",
          entityId: id,
        },
      );
      return (await this.presentRecounts(tx, [updated]))[0]!;
    });
  }

  private async presentRecounts(
    tx: Tx,
    rows: Prisma.StockRecountGetPayload<object>[],
  ) {
    if (!rows.length) return [];
    const [pdvs, depots, users] = await Promise.all([
      tx.pdv.findMany({
        where: { id: { in: rows.map((r) => r.locationId) } },
        select: { id: true, name: true },
      }),
      tx.depot.findMany({
        where: { id: { in: rows.map((r) => r.locationId) } },
        select: { id: true, name: true },
      }),
      tx.user.findMany({
        where: { id: { in: rows.map((r) => r.requestedById) } },
        select: { id: true, name: true },
      }),
    ]);
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    const who = new Map(users.map((u) => [u.id, u.name]));
    return rows.map((r) => ({
      id: r.id,
      status: r.status,
      place: {
        id: r.locationId,
        kind: r.locationKind,
        name: place.get(r.locationId) ?? "",
      },
      regionId: r.regionId,
      reason: r.reason,
      requestedBy: {
        id: r.requestedById,
        name: who.get(r.requestedById) ?? "",
      },
      createdAt: r.createdAt,
      decidedAt: r.decidedAt,
      decisionNote: r.decisionNote,
      used: r.declarationId !== null,
    }));
  }

  private async tell(
    tx: Tx,
    d: { id: string; createdById: string; regionId: string | null },
    key: string,
    place: string,
    note: string | undefined,
    amended: number,
  ) {
    const recipients = [
      d.createdById,
      ...(d.regionId ? await responsableIds(tx, d.regionId) : []),
    ];
    await notify(tx, recipients, {
      key,
      params: { place, note: note ?? null, amended },
      entityType: "StockDeclaration",
      entityId: d.id,
    });
  }

  private async present(
    tx: Tx,
    rows: Prisma.StockDeclarationGetPayload<{ include: { lines: true } }>[],
  ) {
    if (!rows.length) return [];
    const productIds = [
      ...new Set(rows.flatMap((r) => r.lines.map((l) => l.productId))),
    ];
    const locationIds = [...new Set(rows.map((r) => r.locationId))];
    const userIds = [
      ...new Set(
        rows.flatMap((r) =>
          [r.createdById, r.decidedById].filter((x): x is string => !!x),
        ),
      ),
    ];
    const [products, pdvs, depots, users] = await Promise.all([
      tx.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, name: true, family: true },
      }),
      tx.pdv.findMany({
        where: { id: { in: locationIds } },
        select: { id: true, name: true },
      }),
      tx.depot.findMany({
        where: { id: { in: locationIds } },
        select: { id: true, name: true },
      }),
      tx.user.findMany({
        where: { id: { in: userIds } },
        select: { id: true, name: true },
      }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    const user = new Map(users.map((u) => [u.id, u.name]));
    return rows.map((r) => ({
      id: r.id,
      kind: r.kind,
      status: r.status,
      location: {
        id: r.locationId,
        kind: r.locationKind,
        name: place.get(r.locationId) ?? "",
      },
      regionId: r.regionId,
      photoId: r.photoId,
      photoIds: r.photoIds.length ? r.photoIds : r.photoId ? [r.photoId] : [],
      note: r.note,
      createdBy: { id: r.createdById, name: user.get(r.createdById) ?? "" },
      createdAt: r.createdAt,
      decidedBy: r.decidedById
        ? { id: r.decidedById, name: user.get(r.decidedById) ?? "" }
        : null,
      decidedAt: r.decidedAt,
      decisionNote: r.decisionNote,
      reviewedAt: r.reviewedAt,
      reviewNote: r.reviewNote,
      lines: r.lines
        .map((l) => ({
          productId: l.productId,
          name: product.get(l.productId)?.name ?? "",
          family: product.get(l.productId)?.family ?? "",
          quantity: l.quantity,
          approvedQuantity: l.approvedQuantity,
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    }));
  }
}
