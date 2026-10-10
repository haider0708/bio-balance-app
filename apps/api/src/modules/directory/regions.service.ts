import { refuseDeleted } from "../auth/deleted";
import { Injectable } from "@nestjs/common";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, responsableIds } from "../../core/notifier";

const OPEN_ORDERS = ["REQUESTED", "ASSIGNED", "SHIPPED", "RECEIVED"] as const;

function adminOnly(actor: Actor, what: string) {
  requireRule(
    actor.role === "ADMIN",
    "FORBIDDEN",
    `Only the admin ${what}.`,
    403,
  );
}

/** An internal code from a name: "Grand Tunis" → "GRAND-TUNIS". Never shown; only has to be unique. */
function slug(name: string) {
  return (
    name
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 30) || "REGION"
  );
}

/**
 * Regions are stable; what changes is who looks after them and what belongs to them. The admin
 * names them and moves responsables, groups, stores and grossistes between them.
 * A move carries the thing's whole history along, so the new region's responsable sees it all.
 */
@Injectable()
export class RegionsService {
  constructor(private readonly db: Database) {}

  // ───────────────────────── Regions ─────────────────────────

  /** Every region with its responsable and what it holds. */
  overview(actor: Actor) {
    adminOnly(actor, "manages regions");
    return this.db.run(actor, async (tx) => {
      const [regions, responsables, pdvs, groups, depots, members] =
        await Promise.all([
          tx.region.findMany({ orderBy: { name: "asc" } }),
          tx.user.findMany({
            where: {
              role: "RESPONSABLE",
              status: { in: ["PENDING", "ACTIVE"] },
            },
            select: {
              id: true,
              name: true,
              email: true,
              phone: true,
              status: true,
              regionId: true,
            },
          }),
          tx.pdv.groupBy({ by: ["regionId"], _count: { _all: true } }),
          tx.group.groupBy({ by: ["regionId"], _count: { _all: true } }),
          tx.depot.groupBy({ by: ["regionId"], _count: { _all: true } }),
          tx.user.groupBy({
            by: ["regionId"],
            where: { role: "VENDEUR" },
            _count: { _all: true },
          }),
        ]);
      const count = (
        rows: { regionId: string | null; _count: { _all: number } }[],
        id: string,
      ) => rows.find((r) => r.regionId === id)?._count._all ?? 0;
      return regions.map((r) => {
        const counts = {
          pdvs: count(pdvs, r.id),
          groups: count(groups, r.id),
          grossistes: count(depots, r.id),
          members: count(members, r.id),
        };
        const responsable =
          responsables.find((u) => u.regionId === r.id) ?? null;
        return {
          id: r.id,
          code: r.code,
          name: r.name,
          responsable,
          ...counts,
          /** Only a region with nothing left in it can be deleted. */
          deletable:
            !responsable && Object.values(counts).every((n) => n === 0),
        };
      });
    });
  }

  create(actor: Actor, name: string) {
    adminOnly(actor, "creates regions");
    return this.db.run(actor, async (tx) => {
      await this.assertNameFree(tx, name);
      const base = slug(name);
      let code = base;
      for (let n = 2; await tx.region.findUnique({ where: { code } }); n++)
        code = `${base}-${n}`;
      const region = await tx.region.create({ data: { code, name } });
      await audit(
        tx,
        actor,
        "region.created",
        "Region",
        region.id,
        { name },
        region.id,
      );
      return region;
    });
  }

  rename(actor: Actor, id: string, name: string) {
    adminOnly(actor, "renames regions");
    return this.db.run(actor, async (tx) => {
      const region = await tx.region.findUnique({ where: { id } });
      if (!region) throw notFound("Region");
      await this.assertNameFree(tx, name, id);
      const updated = await tx.region.update({ where: { id }, data: { name } });
      await audit(
        tx,
        actor,
        "region.renamed",
        "Region",
        id,
        { from: region.name, to: name },
        id,
      );
      return updated;
    });
  }

  /** A region is deleted only when nothing is left in it: move or remove everything first. */
  remove(actor: Actor, id: string) {
    adminOnly(actor, "deletes regions");
    return this.db.run(actor, async (tx) => {
      const region = await tx.region.findUnique({ where: { id } });
      if (!region) throw notFound("Region");
      const [pdvs, groups, depots, people, sales, orders] = await Promise.all([
        tx.pdv.count({ where: { regionId: id } }),
        tx.group.count({ where: { regionId: id } }),
        tx.depot.count({ where: { regionId: id } }),
        tx.user.count({ where: { regionId: id } }),
        tx.sale.count({ where: { regionId: id } }),
        tx.restockOrder.count({
          where: { OR: [{ regionId: id }, { supplierRegionId: id }] },
        }),
      ]);
      requireRule(
        pdvs + groups + depots + people + sales + orders === 0,
        "REGION_NOT_EMPTY",
        `${region.name} still holds ${pdvs} stores, ${groups} groups, ${depots} grossistes and ${people} people. Move them to another region first.`,
        409,
      );
      await tx.region.delete({ where: { id } });
      await audit(tx, actor, "region.deleted", "Region", id, {
        name: region.name,
      });
      return { ok: true };
    });
  }

  // ───────────────────────── Responsables ─────────────────────────

  /**
   * A responsable always looks after exactly one region. Moving one into a region that already has
   * a responsable swaps the two (only when `swap` is set, so nobody is moved by accident).
   */
  moveResponsable(
    actor: Actor,
    userId: string,
    regionId: string,
    swap: boolean,
  ) {
    adminOnly(actor, "moves responsables");
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "User", userId);
      const user = await tx.user.findUnique({ where: { id: userId } });
      requireRule(
        user?.role === "RESPONSABLE",
        "NOT_A_RESPONSABLE",
        "Only a responsable can be moved.",
        422,
      );
      refuseDeleted(user!);
      const target = await tx.region.findUnique({ where: { id: regionId } });
      requireRule(target, "REGION_NOT_FOUND", "Unknown region.", 404);
      requireRule(
        user!.regionId !== regionId,
        "SAME_REGION",
        "Already looking after this region.",
        409,
      );
      const from = user!.regionId;
      // Only active (or invited) responsables take a seat; a suspended one can go anywhere.
      const mover = ["PENDING", "ACTIVE"].includes(user!.status);
      const occupant = mover
        ? await tx.user.findFirst({
            where: {
              role: "RESPONSABLE",
              regionId,
              status: { in: ["PENDING", "ACTIVE"] },
              id: { not: userId },
            },
          })
        : null;
      if (occupant) {
        requireRule(
          swap,
          "REGION_HAS_RESPONSABLE",
          `${target.name} already has ${occupant.name}. Swap the two, or move ${occupant.name} first.`,
          409,
        );
        // Park the other one while the first takes the seat (one active responsable per region).
        await tx.user.update({
          where: { id: occupant.id },
          data: { status: "SUSPENDED" },
        });
      }
      await tx.user.update({ where: { id: userId }, data: { regionId } });
      if (occupant)
        await tx.user.update({
          where: { id: occupant.id },
          data: { regionId: from, status: occupant.status },
        });
      await audit(
        tx,
        actor,
        "user.moved",
        "User",
        userId,
        { to: target.name, swappedWith: occupant?.name ?? null },
        regionId,
      );
      await notify(tx, [userId], {
        key: "responsable.moved",
        params: { region: target.name },
        entityType: "Region",
        entityId: regionId,
      });
      if (occupant && from) {
        const old = await tx.region.findUnique({ where: { id: from } });
        await notify(tx, [occupant.id], {
          key: "responsable.moved",
          params: { region: old?.name ?? "" },
          entityType: "Region",
          entityId: from,
        });
      }
      return { ok: true };
    });
  }

  // ───────────────────────── Moving places ─────────────────────────

  /** A store goes to another region with its team, stock, sales and deliveries; it leaves its group (or joins one of the new region). */
  movePdv(
    actor: Actor,
    id: string,
    input: { regionId: string; groupId?: string | null },
  ) {
    adminOnly(actor, "moves stores");
    return this.db.run(actor, async (tx) => {
      const pdv = await tx.pdv.findUnique({ where: { id } });
      if (!pdv) throw notFound("Point of sale");
      const target = await this.target(tx, pdv.regionId, input.regionId);
      if (input.groupId) {
        const group = await tx.group.findUnique({
          where: { id: input.groupId },
        });
        requireRule(
          group && group.regionId === input.regionId,
          "GROUP_OTHER_REGION",
          "Choose a group of the new region.",
          422,
        );
      }
      await this.assertNothingOpen(tx, [id], pdv.name);
      await this.restampPlace(tx, id, "PDV", input.regionId);
      await tx.pdv.update({
        where: { id },
        data: { regionId: input.regionId, groupId: input.groupId ?? null },
      });
      await this.finish(
        tx,
        actor,
        "pdv.moved",
        "Pdv",
        id,
        pdv.name,
        pdv.regionId,
        target,
      );
      return { ok: true };
    });
  }

  /** A group goes with all of its stores. */
  moveGroup(actor: Actor, id: string, regionId: string) {
    adminOnly(actor, "moves groups");
    return this.db.run(actor, async (tx) => {
      const group = await tx.group.findUnique({ where: { id } });
      if (!group) throw notFound("Group");
      const target = await this.target(tx, group.regionId, regionId);
      const pdvs = await tx.pdv.findMany({
        where: { groupId: id },
        select: { id: true },
      });
      await this.assertNothingOpen(
        tx,
        pdvs.map((p) => p.id),
        group.name,
      );
      for (const p of pdvs) {
        await this.restampPlace(tx, p.id, "PDV", regionId);
        await tx.pdv.update({ where: { id: p.id }, data: { regionId } });
      }
      await tx.group.update({ where: { id }, data: { regionId } });
      await this.finish(
        tx,
        actor,
        "group.moved",
        "Group",
        id,
        group.name,
        group.regionId,
        target,
      );
      return { ok: true, stores: pdvs.length };
    });
  }

  /** A grossiste goes to another region with its stock; the orders it supplies follow it. */
  moveDepot(actor: Actor, id: string, regionId: string) {
    adminOnly(actor, "moves grossistes");
    return this.db.run(actor, async (tx) => {
      const depot = await tx.depot.findUnique({ where: { id } });
      if (!depot) throw notFound("Grossiste");
      const target = await this.target(tx, depot.regionId, regionId);
      await this.assertNothingOpen(tx, [id], depot.name);
      await this.restampPlace(tx, id, "DEPOT", regionId);
      await tx.depot.update({ where: { id }, data: { regionId } });
      await this.finish(
        tx,
        actor,
        "depot.moved",
        "Depot",
        id,
        depot.name,
        depot.regionId,
        target,
      );
      return { ok: true };
    });
  }

  // ───────────────────────── Helpers ─────────────────────────

  private async assertNameFree(tx: Tx, name: string, except?: string) {
    const same = await tx.region.findFirst({
      where: {
        name: { equals: name, mode: "insensitive" },
        ...(except && { id: { not: except } }),
      },
    });
    requireRule(
      !same,
      "REGION_NAME_TAKEN",
      "A region already has this name.",
      409,
    );
  }

  private async target(tx: Tx, from: string, to: string) {
    const region = await tx.region.findUnique({ where: { id: to } });
    requireRule(region, "REGION_NOT_FOUND", "Unknown region.", 404);
    requireRule(
      from !== to,
      "SAME_REGION",
      "It already belongs to this region.",
      409,
    );
    return region;
  }

  /** Deliveries on the road or counts waiting would end up half in each region: finish them first. */
  private async assertNothingOpen(tx: Tx, placeIds: string[], name: string) {
    const [orders, counts, recounts] = await Promise.all([
      tx.restockOrder.count({
        where: {
          OR: [
            { destId: { in: placeIds } },
            { supplierDepotId: { in: placeIds } },
          ],
          status: { in: [...OPEN_ORDERS] },
        },
      }),
      tx.stockDeclaration.count({
        where: { locationId: { in: placeIds }, status: "PENDING" },
      }),
      tx.stockRecount.count({
        where: { locationId: { in: placeIds }, status: "PENDING" },
      }),
    ]);
    if (orders + counts + recounts > 0)
      throw new DomainError(
        "REGION_MOVE_BLOCKED",
        `${name} has ${orders} open restocks, ${counts} counts and ${recounts} recount requests waiting. Finish or cancel them first.`,
        409,
      );
  }

  /**
   * Everything that belongs to a place carries its region: its stock and the history of it, its
   * counts, its deliveries, the sales and people of a store, the photos on its records.
   * The stock history only accepts this change while `app.region_move` is on.
   */
  private async restampPlace(
    tx: Tx,
    id: string,
    kind: "PDV" | "DEPOT",
    regionId: string,
  ) {
    await tx.$executeRaw`SELECT set_config('app.region_move', 'on', true)`;
    await tx.stock.updateMany({
      where: { locationId: id },
      data: { regionId },
    });
    await tx.stockMovement.updateMany({
      where: { locationId: id },
      data: { regionId },
    });
    await tx.stockDeclaration.updateMany({
      where: { locationId: id },
      data: { regionId },
    });
    await tx.stockRecount.updateMany({
      where: { locationId: id },
      data: { regionId },
    });
    await tx.restockOrder.updateMany({
      where: { destId: id },
      data: { regionId },
    });
    if (kind === "DEPOT")
      await tx.restockOrder.updateMany({
        where: { supplierDepotId: id },
        data: { supplierRegionId: regionId },
      });
    else {
      const people = await tx.user.findMany({
        where: { pdvId: id },
        select: { id: true },
      });
      await tx.user.updateMany({ where: { pdvId: id }, data: { regionId } });
      await tx.sale.updateMany({ where: { pdvId: id }, data: { regionId } });
      await tx.payoutRequest.updateMany({
        where: { userId: { in: people.map((p) => p.id) } },
        data: { regionId },
      });
    }
    // Proof photos are readable by the region they were filed under.
    const [declarations, orders, depot] = await Promise.all([
      tx.stockDeclaration.findMany({
        where: { locationId: id },
        select: { photoId: true, photoIds: true },
      }),
      tx.restockOrder.findMany({
        where: { destId: id },
        select: { receiptPhotoId: true, receiptPhotoIds: true },
      }),
      kind === "DEPOT"
        ? tx.depot.findUnique({ where: { id }, select: { photoIds: true } })
        : null,
    ]);
    const photos = new Set<string>([
      ...declarations.flatMap((d) => [
        ...d.photoIds,
        ...(d.photoId ? [d.photoId] : []),
      ]),
      ...orders.flatMap((o) => [
        ...o.receiptPhotoIds,
        ...(o.receiptPhotoId ? [o.receiptPhotoId] : []),
      ]),
      ...(depot?.photoIds ?? []),
    ]);
    if (photos.size)
      await tx.mediaAsset.updateMany({
        where: { id: { in: [...photos] }, purpose: "PROOF" },
        data: { regionId },
      });
  }

  private async finish(
    tx: Tx,
    actor: Actor,
    key: string,
    entityType: string,
    id: string,
    name: string,
    from: string,
    to: { id: string; name: string },
  ) {
    const old = await tx.region.findUnique({ where: { id: from } });
    await audit(
      tx,
      actor,
      key,
      entityType,
      id,
      { name, from: old?.name ?? null, to: to.name },
      to.id,
    );
    // Both regions' responsables hear about it: one lost it, the other gained it.
    await notify(tx, await responsableIds(tx, to.id), {
      key: `${key}.in`,
      params: { name, from: old?.name ?? "" },
      entityType,
      entityId: id,
    });
    await notify(tx, await responsableIds(tx, from), {
      key: `${key}.out`,
      params: { name, to: to.name },
      entityType,
      entityId: id,
    });
  }
}
