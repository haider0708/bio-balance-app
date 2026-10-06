import { Injectable } from "@nestjs/common";
import type { Approval, Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";
import { findLocation, setStock, type Location } from "./ledger";

export interface DeclarationLineInput {
  productId: string;
  quantity: number;
}

const LOW_STOCK = 5;

@Injectable()
export class StockService {
  constructor(private readonly db: Database) {}

  /** May this person look at or declare the stock of this place? */
  private async authorize(tx: Tx, actor: Actor, locationId: string): Promise<Location> {
    const location = await findLocation(tx, locationId);
    const ok =
      actor.role === "ADMIN" ||
      (actor.role === "RESPONSABLE" && location.kind === "PDV" && location.regionId === actor.regionId) ||
      (actor.role === "GROSSISTE" && location.kind === "DEPOT" && location.id === actor.depotId);
    if (!ok) throw notFound("Location");
    return location;
  }

  /** Quantities at one place, with product details; low and negative stock flagged. */
  async levels(actor: Actor, locationId: string) {
    return this.db.run(actor, async (tx) => {
      const location = await this.authorize(tx, actor, locationId);
      const rows = await tx.stock.findMany({ where: { locationId } });
      const products = await tx.product.findMany({ where: { id: { in: rows.map((r) => r.productId) } } });
      const byId = new Map(products.map((p) => [p.id, p]));
      return {
        location: { id: location.id, kind: location.kind, name: location.name, status: location.status },
        items: rows
          .map((r) => {
            const p = byId.get(r.productId)!;
            return {
              productId: r.productId, name: p.name, family: p.family, imageId: p.imageId,
              quantity: r.quantity,
              level: r.quantity < 0 ? "NEGATIVE" : r.quantity <= LOW_STOCK ? "LOW" : "OK",
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

  async declare(actor: Actor, input: { locationId: string; photoId: string; note?: string; lines: DeclarationLineInput[] }) {
    requireRule(["RESPONSABLE", "GROSSISTE"].includes(actor.role), "FORBIDDEN", "Only a responsable or grossiste declares stock.", 403);
    return this.db.run(actor, async (tx) => {
      const location = await this.authorize(tx, actor, input.locationId);
      requireRule(["PENDING", "ACTIVE"].includes(location.status), "INVALID_STATE", "This place cannot receive stock now.", 409);
      const photo = await tx.mediaAsset.findUnique({ where: { id: input.photoId } });
      requireRule(photo?.purpose === "PROOF" && photo.ownerId === actor.id, "PHOTO_REQUIRED", "Add a photo of the stock.", 422);
      const ids = input.lines.map((l) => l.productId);
      requireRule(new Set(ids).size === ids.length, "DUPLICATE_PRODUCT", "A product appears twice.");
      const found = await tx.product.count({ where: { id: { in: ids }, active: true } });
      requireRule(found === ids.length, "PRODUCT_NOT_FOUND", "Unknown or inactive product.", 404);
      requireRule(
        !(await tx.stockDeclaration.findFirst({ where: { locationId: location.id, status: "PENDING" } })),
        "DECLARATION_PENDING",
        "A stock declaration is already waiting for approval.",
        409,
      );
      const hasInitial = await tx.stockDeclaration.findFirst({ where: { locationId: location.id, kind: "INITIAL", status: "APPROVED" } });
      const declaration = await tx.stockDeclaration.create({
        data: {
          kind: hasInitial ? "COUNT" : "INITIAL",
          locationId: location.id, locationKind: location.kind, regionId: location.regionId,
          photoId: input.photoId, note: input.note?.trim() || null, createdById: actor.id,
          lines: { create: input.lines.map((l) => ({ productId: l.productId, quantity: l.quantity })) },
        },
        include: { lines: true },
      });
      await audit(tx, actor, "stock.declared", "StockDeclaration", declaration.id, { location: location.name, lines: input.lines.length }, location.regionId);
      await notifyAdmins(tx, {
        key: "stock.submitted",
        params: { place: location.name, by: actor.name, kind: declaration.kind },
        entityType: "StockDeclaration",
        entityId: declaration.id,
      });
      return (await this.present(tx, [declaration]))[0]!;
    });
  }

  list(actor: Actor, filter: { status?: Approval; regionId?: string; locationId?: string }) {
    requireRule(["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role), "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const rows = await tx.stockDeclaration.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.locationId && { locationId: filter.locationId }),
          ...(actor.role === "ADMIN" && filter.regionId && { regionId: filter.regionId }),
        },
        include: { lines: true },
        orderBy: { createdAt: "desc" },
        take: 200,
      });
      return this.present(tx, rows);
    });
  }

  async get(actor: Actor, id: string) {
    requireRule(["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role), "FORBIDDEN", "Not allowed.", 403);
    return this.db.run(actor, async (tx) => {
      const row = await tx.stockDeclaration.findUnique({ where: { id }, include: { lines: true } });
      if (!row) throw notFound("Stock declaration");
      return (await this.present(tx, [row]))[0]!;
    });
  }

  /** The admin approves the quantities as declared, or corrects some of them first. */
  approve(actor: Actor, id: string, input: { lines?: DeclarationLineInput[]; note?: string }) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can approve.", 403);
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockDeclaration", id);
      const declaration = await tx.stockDeclaration.findUnique({ where: { id }, include: { lines: true } });
      if (!declaration) throw notFound("Stock declaration");
      requireRule(declaration.status === "PENDING", "INVALID_STATE", "This declaration was already decided.", 409);
      const overrides = new Map((input.lines ?? []).map((l) => [l.productId, l.quantity]));
      for (const productId of overrides.keys())
        requireRule(declaration.lines.some((l) => l.productId === productId), "PRODUCT_NOT_FOUND", "That product is not in the declaration.", 422);
      const location = await findLocation(tx, declaration.locationId);
      let amended = 0;
      for (const line of declaration.lines) {
        const approved = overrides.get(line.productId) ?? line.quantity;
        if (approved !== line.quantity) amended++;
        await tx.stockDeclarationLine.update({ where: { id: line.id }, data: { approvedQuantity: approved } });
        await setStock(tx, location, line.productId, approved, {
          reason: "DECLARATION", refType: "StockDeclaration", refId: id, actorId: actor.id,
        });
      }
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: { status: "APPROVED", decidedById: actor.id, decidedAt: new Date(), decisionNote: input.note?.trim() || null },
        include: { lines: true },
      });
      await audit(tx, actor, "stock.approved", "StockDeclaration", id, { amended }, declaration.regionId);
      await this.tell(tx, declaration, "stock.approved", location.name, input.note, amended);
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  reject(actor: Actor, id: string, note: string) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Only the admin can reject.", 403);
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "StockDeclaration", id);
      const declaration = await tx.stockDeclaration.findUnique({ where: { id }, include: { lines: true } });
      if (!declaration) throw notFound("Stock declaration");
      requireRule(declaration.status === "PENDING", "INVALID_STATE", "This declaration was already decided.", 409);
      const location = await findLocation(tx, declaration.locationId);
      const updated = await tx.stockDeclaration.update({
        where: { id },
        data: { status: "REJECTED", decidedById: actor.id, decidedAt: new Date(), decisionNote: note },
        include: { lines: true },
      });
      await audit(tx, actor, "stock.rejected", "StockDeclaration", id, { note }, declaration.regionId);
      await this.tell(tx, declaration, "stock.rejected", location.name, note, 0);
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  private async tell(tx: Tx, d: { id: string; createdById: string; regionId: string | null }, key: string, place: string, note: string | undefined, amended: number) {
    const recipients = [d.createdById, ...(d.regionId ? await responsableIds(tx, d.regionId) : [])];
    await notify(tx, recipients, { key, params: { place, note: note ?? null, amended }, entityType: "StockDeclaration", entityId: d.id });
  }

  private async present(
    tx: Tx,
    rows: Prisma.StockDeclarationGetPayload<{ include: { lines: true } }>[],
  ) {
    if (!rows.length) return [];
    const productIds = [...new Set(rows.flatMap((r) => r.lines.map((l) => l.productId)))];
    const locationIds = [...new Set(rows.map((r) => r.locationId))];
    const userIds = [...new Set(rows.flatMap((r) => [r.createdById, r.decidedById].filter((x): x is string => !!x)))];
    const [products, pdvs, depots, users] = await Promise.all([
      tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true, family: true } }),
      tx.pdv.findMany({ where: { id: { in: locationIds } }, select: { id: true, name: true } }),
      tx.depot.findMany({ where: { id: { in: locationIds } }, select: { id: true, name: true } }),
      tx.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const place = new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
    const user = new Map(users.map((u) => [u.id, u.name]));
    return rows.map((r) => ({
      id: r.id, kind: r.kind, status: r.status,
      location: { id: r.locationId, kind: r.locationKind, name: place.get(r.locationId) ?? "" },
      regionId: r.regionId, photoId: r.photoId, note: r.note,
      createdBy: { id: r.createdById, name: user.get(r.createdById) ?? "" }, createdAt: r.createdAt,
      decidedBy: r.decidedById ? { id: r.decidedById, name: user.get(r.decidedById) ?? "" } : null,
      decidedAt: r.decidedAt, decisionNote: r.decisionNote,
      lines: r.lines
        .map((l) => ({
          productId: l.productId, name: product.get(l.productId)?.name ?? "", family: product.get(l.productId)?.family ?? "",
          quantity: l.quantity, approvedQuantity: l.approvedQuantity,
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    }));
  }
}

