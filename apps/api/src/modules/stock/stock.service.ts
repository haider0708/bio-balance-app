import { Injectable } from "@nestjs/common";
import type { Approval, Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { decisionLocked, withinDecisionWindow } from "../../core/approval";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { randomUUID } from "node:crypto";
import { ownedProofs } from "../media/proofs";
import {
  adjustStock,
  currentQuantity,
  findLocation,
  setStock,
  type Location,
  type MovementRef,
} from "./ledger";

export interface DeclarationLineInput {
  productId: string;
  quantity: number;
}

const LOW_STOCK = 5;
/** A waiting count stays on hold this long while its responsable corrects it (renewed while they work). */
const EDIT_HOLD_MS = 30 * 60_000;
/** After its approval, the responsable may still correct a count for this long. */
const CORRECTION_WINDOW_MS = 3 * 86_400_000;

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
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Only the admin or a responsable declares stock.",
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
          status: "PENDING",
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
      // The admin counts a place once; later changes are corrections (see `adjust`).
      requireRule(
        actor.role !== "ADMIN" || !counted,
        "ALREADY_COUNTED",
        "This place was already counted: correct its stock instead.",
        409,
      );
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
              { regionId: location.stockRegionId },
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
      // The admin's own count needs nobody's approval; a responsable's goes to the admin.
      const byAdmin = actor.role === "ADMIN";
      const declaration = await tx.stockDeclaration.create({
        data: {
          kind: counted ? "COUNT" : "INITIAL",
          status: byAdmin ? "APPROVED" : "PENDING",
          ...(byAdmin && { decidedById: actor.id, decidedAt: new Date() }),
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
              appliedQuantity: l.quantity,
              ...(byAdmin && { approvedQuantity: l.quantity }),
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
        location.stockRegionId,
      );
      if (permit)
        await tx.stockRecount.update({
          where: { id: permit.id },
          data: { declarationId: declaration.id },
        });
      // The count reaches the stock at once, so the sellers can sell; the admin's approval verifies it.
      for (const line of declaration.lines)
        await setStock(tx, location, line.productId, line.quantity, {
          reason: "DECLARATION",
          refType: "StockDeclaration",
          refId: declaration.id,
          actorId: actor.id,
        });
      if (byAdmin) {
        await audit(
          tx,
          actor,
          "stock.approved",
          "StockDeclaration",
          declaration.id,
          { amended: 0 },
          location.stockRegionId,
        );
        if (location.stockRegionId)
          await notify(tx, await responsableIds(tx, location.stockRegionId), {
            key: "stock.approved",
            params: { place: location.name, note: null, amended: 0 },
            entityType: "StockDeclaration",
            entityId: declaration.id,
          });
      } else
        await notifyAdmins(tx, location.stockRegionId, {
          key: "stock.submitted",
          params: {
            place: location.name,
            by: actor.name,
            kind: declaration.kind,
          },
          entityType: "StockDeclaration",
          entityId: declaration.id,
        });
      return (await this.present(tx, [declaration]))[0]!;
    });
  }

  list(
    actor: Actor,
    filter: { status?: Approval; regionId?: string; locationId?: string },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
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
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
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

  /**
   * The admin verifies a count: as declared, or with quantities changed and products added. The
   * count is already in the stock, so only the difference is applied (the sales made since are
   * never overwritten).
   */
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
      const declaration = await this.lockDeclaration(tx, id);
      const location = await findLocation(tx, declaration.locationId);
      const amended = await this.applyDecision(
        tx,
        actor,
        declaration,
        location,
        input.lines ?? [],
      );
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

  /** The admin rejects a count: the stock it put in is taken back (what already left stays sold). */
  reject(actor: Actor, id: string, note: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can reject.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockDeclaration(tx, id);
      const location = await findLocation(tx, declaration.locationId);
      let removed = 0;
      for (const line of declaration.lines) {
        const applied = line.appliedQuantity ?? 0;
        if (applied <= 0) continue;
        // Never more than is there: units sold meanwhile are not taken back twice.
        await tx.$queryRaw`SELECT 1 FROM "Stock" WHERE "locationId"=${location.id}::uuid AND "productId"=${line.productId}::uuid FOR UPDATE`;
        const take = Math.min(
          applied,
          await currentQuantity(tx, location.id, line.productId),
        );
        if (take > 0)
          await adjustStock(tx, location, line.productId, -take, {
            reason: "DECLARATION_REMOVED",
            refType: "StockDeclaration",
            refId: id,
            actorId: actor.id,
          });
        removed += take;
        await tx.stockDeclarationLine.update({
          where: { id: line.id },
          data: { appliedQuantity: 0 },
        });
      }
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
        { note, removed },
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
   * Puts the admin's quantities for a count into the stock: only the difference from what the
   * count already put in, products added by the admin included. Returns how many lines changed.
   */
  private async applyDecision(
    tx: Tx,
    actor: Actor,
    declaration: Prisma.StockDeclarationGetPayload<{
      include: { lines: true };
    }>,
    location: Location,
    lines: DeclarationLineInput[],
  ) {
    const overrides = new Map(lines.map((l) => [l.productId, l.quantity]));
    requireRule(
      overrides.size === lines.length,
      "DUPLICATE_PRODUCT",
      "A product appears twice.",
    );
    const known = new Set(declaration.lines.map((l) => l.productId));
    const added = [...overrides.keys()].filter((p) => !known.has(p));
    // The admin may add products the responsable left out.
    requireRule(
      (await tx.product.count({
        where: { id: { in: added }, active: true },
      })) === added.length,
      "PRODUCT_NOT_FOUND",
      "Unknown or inactive product.",
      404,
    );
    const changes = [
      ...declaration.lines.map((l) => ({
        productId: l.productId,
        applied: l.appliedQuantity,
        target: overrides.get(l.productId) ?? l.approvedQuantity ?? l.quantity,
      })),
      ...added.map((productId) => ({
        productId,
        applied: null,
        target: overrides.get(productId)!,
      })),
    ];
    await this.assertRoomToReduce(tx, location, changes);
    const ref: MovementRef = {
      reason: "DECLARATION_CORRECTION",
      refType: "StockDeclaration",
      refId: declaration.id,
      actorId: actor.id,
    };
    let amended = 0;
    for (const line of declaration.lines) {
      const approved =
        overrides.get(line.productId) ?? line.approvedQuantity ?? line.quantity;
      if (approved !== (line.approvedQuantity ?? line.quantity)) amended++;
      await this.applyLine(
        tx,
        location,
        line.productId,
        line.appliedQuantity,
        approved,
        ref,
      );
      await tx.stockDeclarationLine.update({
        where: { id: line.id },
        data: { approvedQuantity: approved, appliedQuantity: approved },
      });
    }
    for (const productId of added) {
      amended++;
      const quantity = overrides.get(productId)!;
      await this.applyLine(tx, location, productId, null, quantity, ref);
      await tx.stockDeclarationLine.create({
        data: {
          declarationId: declaration.id,
          productId,
          quantity: 0,
          approvedQuantity: quantity,
          appliedQuantity: quantity,
          addedByAdmin: true,
        },
      });
    }
    return amended;
  }

  /**
   * The admin corrects the quantities of a count they approved less than 6 hours ago (adding
   * products if needed). Only the difference reaches the stock; the sales since are kept.
   */
  amend(
    actor: Actor,
    id: string,
    input: { lines: DeclarationLineInput[]; note?: string },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can amend.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockAny(tx, id);
      requireRule(
        declaration.status === "APPROVED",
        "INVALID_STATE",
        "Only an approved count can be amended.",
        409,
      );
      if (!withinDecisionWindow(declaration.decidedAt)) throw decisionLocked();
      const location = await findLocation(tx, declaration.locationId);
      const before = declaration.lines.map((l) => ({
        productId: l.productId,
        quantity: l.approvedQuantity ?? l.quantity,
      }));
      const amended = await this.applyDecision(
        tx,
        actor,
        declaration,
        location,
        input.lines,
      );
      const updated = await tx.stockDeclaration.findUniqueOrThrow({
        where: { id },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        "stock.amended",
        "StockDeclaration",
        id,
        { before, after: input.lines, note: input.note ?? null },
        declaration.regionId,
      );
      await this.tell(
        tx,
        declaration,
        "stock.amended",
        location.name,
        input.note,
        amended,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /**
   * The admin puts a count back to waiting (approved or rejected less than 6 hours ago) to decide
   * again. A rejected count gets its stock back, as a waiting count has it.
   */
  reopen(actor: Actor, id: string) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockAny(tx, id);
      requireRule(
        declaration.status === "APPROVED" || declaration.status === "REJECTED",
        "INVALID_STATE",
        "Only a decided count can be taken back.",
        409,
      );
      if (!withinDecisionWindow(declaration.decidedAt)) throw decisionLocked();
      const location = await findLocation(tx, declaration.locationId);
      if (declaration.status === "REJECTED") {
        // Another count of this place may have been made since: two would count twice.
        requireRule(
          !(await tx.stockDeclaration.findFirst({
            where: {
              locationId: declaration.locationId,
              id: { not: id },
              status: { not: "REJECTED" },
              createdAt: { gt: declaration.createdAt },
            },
          })),
          "DECLARATION_EXISTS",
          "This place was counted again since: that count stands.",
          409,
        );
        const ref: MovementRef = {
          reason: "DECLARATION_CORRECTION",
          refType: "StockDeclaration",
          refId: id,
          actorId: actor.id,
        };
        for (const line of declaration.lines) {
          await this.applyLine(
            tx,
            location,
            line.productId,
            line.appliedQuantity ?? 0,
            line.quantity,
            ref,
          );
          await tx.stockDeclarationLine.update({
            where: { id: line.id },
            data: { appliedQuantity: line.quantity },
          });
        }
      }
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          status: "PENDING",
          decidedById: null,
          decidedAt: null,
          decisionNote: null,
        },
        include: { lines: true },
      });
      await tx.stockDeclarationLine.updateMany({
        where: { declarationId: id, addedByAdmin: false },
        data: { approvedQuantity: null },
      });
      await audit(
        tx,
        actor,
        "stock.reopened",
        "StockDeclaration",
        id,
        { was: declaration.status },
        declaration.regionId,
      );
      await this.tell(
        tx,
        declaration,
        "decision.reopened",
        location.name,
        undefined,
        0,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** The admin takes back a recount decision made in the last 6 hours (not yet used). */
  reopenRecount(actor: Actor, id: string) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockRecount", id);
      const row = await tx.stockRecount.findUnique({ where: { id } });
      if (!row) throw notFound("Recount request");
      requireRule(
        (row.status === "APPROVED" && row.declarationId === null) ||
          row.status === "REJECTED",
        "INVALID_STATE",
        "Only a decision not yet used can be taken back.",
        409,
      );
      if (!withinDecisionWindow(row.decidedAt)) throw decisionLocked();
      const location = await findLocation(tx, row.locationId);
      const updated = await tx.stockRecount.update({
        where: { id },
        data: {
          status: "PENDING",
          decidedById: null,
          decidedAt: null,
          decisionNote: null,
        },
      });
      await audit(
        tx,
        actor,
        "stock.recount_reopened",
        "StockRecount",
        id,
        { was: row.status },
        row.regionId,
      );
      await notify(tx, [row.requestedById], {
        key: "decision.reopened",
        params: { name: location.name },
        entityType: "StockRecount",
        entityId: id,
      });
      return (await this.presentRecounts(tx, [updated]))[0]!;
    });
  }

  // ───────────────────────── Correcting a count ─────────────────────────

  /**
   * The responsable opens a waiting count to correct it: it goes on hold, so the admin cannot
   * decide it meanwhile. Calling it again renews the hold (30 minutes), and it ends when they
   * save, cancel, or stop.
   */
  startEdit(actor: Actor, id: string) {
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockAny(tx, id);
      await this.authorize(tx, actor, declaration.locationId);
      requireRule(
        declaration.status === "PENDING",
        "INVALID_STATE",
        "Only a count waiting for the admin can be put on hold.",
        409,
      );
      this.assertNotHeldByOther(declaration, actor.id);
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          editingById: actor.id,
          editingUntil: new Date(Date.now() + EDIT_HOLD_MS),
        },
        include: { lines: true },
      });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** The responsable gives up correcting: the count goes back to the admin as it was. */
  cancelEdit(actor: Actor, id: string) {
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockAny(tx, id);
      await this.authorize(tx, actor, declaration.locationId);
      const updated =
        declaration.editingById === actor.id
          ? await tx.stockDeclaration.update({
              where: { id },
              data: { editingById: null, editingUntil: null },
              include: { lines: true },
            })
          : declaration;
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /**
   * The responsable saves a corrected count, with the new quantities in full. A waiting count goes
   * back to the admin (after the hold); an approved one (up to three days after its approval,
   * with a reason) is corrected at once, without a new approval, and the admin is told. Either
   * way only the difference reaches the stock, and a quantity cannot go below what already left.
   */
  edit(
    actor: Actor,
    id: string,
    input: {
      lines: DeclarationLineInput[];
      photoIds?: string[];
      note?: string;
      reason?: string;
    },
  ) {
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const declaration = await this.lockAny(tx, id);
      const location = await this.authorize(tx, actor, declaration.locationId);
      const author = await tx.user.findUnique({
        where: { id: declaration.createdById },
        select: { role: true },
      });
      requireRule(
        author?.role === "RESPONSABLE",
        "FORBIDDEN",
        "A count made by the admin is corrected by the admin.",
        403,
      );
      const approved = declaration.status === "APPROVED";
      if (approved) {
        requireRule(
          input.reason?.trim(),
          "REASON_REQUIRED",
          "Say what was wrong: an approved count needs a reason to be corrected.",
        );
        requireRule(
          declaration.decidedAt &&
            Date.now() - declaration.decidedAt.getTime() <=
              CORRECTION_WINDOW_MS,
          "STOCK_CORRECTION_CLOSED",
          "A count can be corrected for 3 days after its approval. Ask the admin.",
          403,
        );
        const later = await tx.stockDeclaration.findFirst({
          where: {
            locationId: declaration.locationId,
            createdAt: { gt: declaration.createdAt },
          },
        });
        requireRule(
          !later,
          "NOT_LATEST",
          "A newer count of this place exists: correct that one.",
          409,
        );
      } else {
        requireRule(
          declaration.status === "PENDING",
          "INVALID_STATE",
          "This count was rejected: declare it again.",
          409,
        );
        this.assertNotHeldByOther(declaration, actor.id);
      }
      const ids = input.lines.map((l) => l.productId);
      requireRule(
        new Set(ids).size === ids.length,
        "DUPLICATE_PRODUCT",
        "A product appears twice.",
      );
      requireRule(
        (await tx.product.count({
          where: { id: { in: ids }, active: true },
        })) === ids.length,
        "PRODUCT_NOT_FOUND",
        "Unknown or inactive product.",
        404,
      );
      // The photos kept stay valid; new ones must be the responsable's own.
      const kept = new Set([
        ...declaration.photoIds,
        ...(declaration.photoId ? [declaration.photoId] : []),
      ]);
      const wanted = input.photoIds ?? [...kept];
      const fresh = wanted.filter((p) => !kept.has(p));
      const photoIds =
        input.lines.length > 0
          ? [
              ...(await ownedProofs(
                tx,
                actor,
                fresh,
                "Add a photo of the stock.",
                {
                  regionId: location.stockRegionId,
                  min: 0,
                },
              )),
              ...wanted.filter((p) => kept.has(p)),
            ]
          : [];
      requireRule(
        input.lines.length === 0 || photoIds.length >= 1,
        "PHOTO_REQUIRED",
        "Add a photo of the stock.",
        422,
      );
      requireRule(
        photoIds.length <= 5,
        "TOO_MANY_PHOTOS",
        "Add between 1 and 5 different photos or documents.",
        422,
      );

      const current = new Map(declaration.lines.map((l) => [l.productId, l]));
      const next = new Map(input.lines.map((l) => [l.productId, l.quantity]));
      const changes = [
        ...declaration.lines.map((l) => ({
          productId: l.productId,
          applied: l.appliedQuantity,
          target: next.get(l.productId) ?? 0,
        })),
        ...input.lines
          .filter((l) => !current.has(l.productId))
          .map((l) => ({
            productId: l.productId,
            applied: null,
            target: l.quantity,
          })),
      ];
      await this.assertRoomToReduce(tx, location, changes);
      const ref: MovementRef = {
        reason: "DECLARATION_CORRECTION",
        refType: "StockDeclaration",
        refId: id,
        actorId: actor.id,
      };
      const before = declaration.lines.map((l) => ({
        productId: l.productId,
        quantity: l.quantity,
      }));
      for (const line of declaration.lines) {
        const target = next.get(line.productId);
        if (target === undefined) {
          // Left out of the corrected count: its units come out of the stock again.
          await this.applyLine(
            tx,
            location,
            line.productId,
            line.appliedQuantity,
            0,
            ref,
          );
          await tx.stockDeclarationLine.delete({ where: { id: line.id } });
          continue;
        }
        await this.applyLine(
          tx,
          location,
          line.productId,
          line.appliedQuantity,
          target,
          ref,
        );
        await tx.stockDeclarationLine.update({
          where: { id: line.id },
          data: {
            quantity: target,
            appliedQuantity: target,
            ...(approved && { approvedQuantity: target }),
          },
        });
      }
      for (const l of input.lines.filter((x) => !current.has(x.productId))) {
        await this.applyLine(tx, location, l.productId, null, l.quantity, ref);
        await tx.stockDeclarationLine.create({
          data: {
            declarationId: id,
            productId: l.productId,
            quantity: l.quantity,
            appliedQuantity: l.quantity,
            ...(approved && { approvedQuantity: l.quantity }),
          },
        });
      }
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: {
          photoId: photoIds[0] ?? null,
          photoIds,
          ...(input.note !== undefined && { note: input.note.trim() || null }),
          editingById: null,
          editingUntil: null,
          ...(approved && { correctedAt: new Date() }),
        },
        include: { lines: true },
      });
      await audit(
        tx,
        actor,
        approved ? "stock.corrected" : "stock.edited",
        "StockDeclaration",
        id,
        {
          location: location.name,
          reason: input.reason?.trim() ?? null,
          before,
          after: input.lines,
        },
        location.stockRegionId,
      );
      await notifyAdmins(tx, location.stockRegionId, {
        key: approved ? "stock.corrected" : "stock.edited",
        params: {
          place: location.name,
          by: actor.name,
          reason: input.reason?.trim() ?? "",
        },
        entityType: "StockDeclaration",
        entityId: id,
      });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /**
   * Puts a line's quantity into the stock: the first time as the counted quantity, afterwards only
   * the difference from what it already put in.
   */
  private applyLine(
    tx: Tx,
    location: Location,
    productId: string,
    applied: number | null,
    target: number,
    ref: MovementRef,
  ) {
    if (applied === null) return setStock(tx, location, productId, target, ref);
    if (target === applied) return Promise.resolve();
    return adjustStock(tx, location, productId, target - applied, ref);
  }

  /**
   * A line cannot be lowered below what already left the place (sold or shipped): the stock never
   * goes negative. Says which products, and how low each may go.
   */
  private async assertRoomToReduce(
    tx: Tx,
    location: Location,
    changes: { productId: string; applied: number | null; target: number }[],
  ) {
    const tooLow: { productId: string; name: string; minimum: number }[] = [];
    for (const c of changes) {
      if (c.applied === null || c.target >= c.applied) continue;
      await tx.$queryRaw`SELECT 1 FROM "Stock" WHERE "locationId"=${location.id}::uuid AND "productId"=${c.productId}::uuid FOR UPDATE`;
      const have = await currentQuantity(tx, location.id, c.productId);
      if (have + (c.target - c.applied) < 0) {
        const product = await tx.product.findUnique({
          where: { id: c.productId },
          select: { name: true },
        });
        tooLow.push({
          productId: c.productId,
          name: product?.name ?? "",
          minimum: c.applied - have,
        });
      }
    }
    if (tooLow.length)
      throw new DomainError(
        "BELOW_SOLD",
        "Some of these units already left this place (sold or shipped): a quantity cannot go below what was used.",
        409,
        { products: tooLow },
      );
  }

  private assertNotHeldByOther(
    declaration: { editingById: string | null; editingUntil: Date | null },
    actorId: string,
  ) {
    const held =
      declaration.editingById &&
      declaration.editingUntil &&
      declaration.editingUntil.getTime() > Date.now();
    requireRule(
      !held || declaration.editingById === actorId,
      "EDITING",
      "Someone else is correcting this count.",
      409,
    );
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
        await notify(
          tx,
          location.stockRegionId
            ? await responsableIds(tx, location.stockRegionId)
            : [],
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
    requireRule(actor.role === "RESPONSABLE", "FORBIDDEN", "Not allowed.", 403);
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
            status: "PENDING",
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
      await notifyAdmins(tx, location.stockRegionId, {
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
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
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

  /** Locks a declaration, whatever its state. */
  private async lockAny(tx: Tx, id: string) {
    await this.db.lock(tx, "StockDeclaration", id);
    const declaration = await tx.stockDeclaration.findUnique({
      where: { id },
      include: { lines: true },
    });
    if (!declaration) throw notFound("Stock declaration");
    return declaration;
  }

  /**
   * Locks a declaration for the admin's decision and checks nobody decided it yet and that its
   * responsable is not correcting it (a count on hold cannot be decided).
   */
  private async lockDeclaration(tx: Tx, id: string) {
    const declaration = await this.lockAny(tx, id);
    requireRule(
      declaration.status === "PENDING",
      "INVALID_STATE",
      "This declaration was already decided.",
      409,
    );
    requireRule(
      !(
        declaration.editingUntil &&
        declaration.editingUntil.getTime() > Date.now()
      ),
      "EDITING",
      "The responsable is correcting this count: wait for them to finish.",
      409,
    );
    return declaration;
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
          [r.createdById, r.decidedById, r.editingById].filter(
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
        where: { id: { in: locationIds } },
        select: { id: true, name: true },
      }),
      tx.depot.findMany({
        where: { id: { in: locationIds } },
        select: { id: true, name: true },
      }),
      tx.user.findMany({
        where: { id: { in: userIds } },
        select: { id: true, name: true, role: true },
      }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    const user = new Map(users.map((u) => [u.id, u.name]));
    const role = new Map(users.map((u) => [u.id, u.role]));
    const now = Date.now();
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
      /** The responsable is correcting it: the admin cannot decide it until they finish. */
      editing:
        r.editingById && r.editingUntil && r.editingUntil.getTime() > now
          ? {
              by: { id: r.editingById, name: user.get(r.editingById) ?? "" },
              until: r.editingUntil,
            }
          : null,
      /** Until when its responsable may still correct it without a new approval (null: no more). */
      correctableUntil:
        r.status === "APPROVED" &&
        r.decidedAt &&
        role.get(r.createdById) === "RESPONSABLE" &&
        r.decidedAt.getTime() + CORRECTION_WINDOW_MS > now
          ? new Date(r.decidedAt.getTime() + CORRECTION_WINDOW_MS)
          : null,
      correctedAt: r.correctedAt,
      lines: r.lines
        .map((l) => ({
          productId: l.productId,
          name: product.get(l.productId)?.name ?? "",
          family: product.get(l.productId)?.family ?? "",
          quantity: l.quantity,
          approvedQuantity: l.approvedQuantity,
          addedByAdmin: l.addedByAdmin,
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    }));
  }
}
