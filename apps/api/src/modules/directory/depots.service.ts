import { Injectable } from "@nestjs/common";
import type { Status } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";
import { ownedProofs } from "../media/proofs";

export interface DepotInput {
  regionId: string;
  name: string;
  address: string;
  city: string;
  phone?: string | null;
  photoIds?: string[];
}

/**
 * Grossistes: warehouses of a region. They hold stock but have no account. The admin
 * creates and edits them; the region's responsable sees them and manages their stock.
 */
@Injectable()
export class DepotsService {
  constructor(private readonly db: Database) {}

  list(actor: Actor, filter: { regionId?: string; status?: Status } = {}) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const depots = await tx.depot.findMany({
        where: {
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
          ...(filter.status && { status: filter.status }),
        },
        orderBy: { name: "asc" },
      });
      return this.present(tx, depots);
    });
  }

  get(actor: Actor, id: string) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const depot = await tx.depot.findUnique({ where: { id } });
      if (!depot) throw notFound("Grossiste");
      return (await this.present(tx, [depot]))[0]!;
    });
  }

  create(actor: Actor, input: DepotInput) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin creates a grossiste.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      requireRule(
        await tx.region.findUnique({ where: { id: input.regionId } }),
        "REGION_NOT_FOUND",
        "Unknown region.",
        404,
      );
      const photoIds = await ownedProofs(
        tx,
        actor,
        input.photoIds ?? [],
        "Add a photo of the grossiste.",
        { regionId: input.regionId, min: 0 },
      );
      const depot = await tx.depot.create({
        data: {
          regionId: input.regionId,
          name: input.name,
          address: input.address,
          city: input.city,
          phone: input.phone ?? null,
          photoIds,
        },
      });
      await audit(
        tx,
        actor,
        "depot.created",
        "Depot",
        depot.id,
        { name: depot.name },
        depot.regionId,
      );
      return (await this.present(tx, [depot]))[0]!;
    });
  }

  update(
    actor: Actor,
    id: string,
    input: Partial<Omit<DepotInput, "regionId">> & { status?: Status },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin edits a grossiste.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const depot = await tx.depot.findUnique({ where: { id } });
      if (!depot) throw notFound("Grossiste");
      requireRule(
        !input.status || ["ACTIVE", "SUSPENDED"].includes(input.status),
        "INVALID_STATE",
        "A grossiste is either active or suspended.",
        422,
      );
      const photoIds = input.photoIds
        ? await ownedProofsOrKept(tx, actor, input.photoIds, depot)
        : undefined;
      const updated = await tx.depot.update({
        where: { id },
        data: {
          ...(input.name !== undefined && { name: input.name }),
          ...(input.address !== undefined && { address: input.address }),
          ...(input.city !== undefined && { city: input.city }),
          ...(input.phone !== undefined && { phone: input.phone }),
          ...(input.status !== undefined && { status: input.status }),
          ...(photoIds && { photoIds }),
        },
      });
      await audit(
        tx,
        actor,
        "depot.updated",
        "Depot",
        id,
        { ...input, photoIds: undefined },
        depot.regionId,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** A grossiste that never held stock or took part in an order can be removed; otherwise suspend it. */
  remove(actor: Actor, id: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin removes a grossiste.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const depot = await tx.depot.findUnique({ where: { id } });
      if (!depot) throw notFound("Grossiste");
      const used =
        (await tx.stock.count({ where: { locationId: id } })) +
        (await tx.stockMovement.count({ where: { locationId: id } })) +
        (await tx.stockDeclaration.count({ where: { locationId: id } })) +
        (await tx.restockOrder.count({
          where: { OR: [{ supplierDepotId: id }, { destId: id }] },
        }));
      requireRule(
        used === 0,
        "ALREADY_USED",
        "This grossiste already has activity. Suspend it instead.",
        409,
      );
      await tx.depot.delete({ where: { id } });
      await audit(
        tx,
        actor,
        "depot.removed",
        "Depot",
        id,
        { name: depot.name },
        depot.regionId,
      );
      return { ok: true };
    });
  }

  /** Each grossiste with its region and a summary of what it holds. */
  private async present(
    tx: Tx,
    depots: {
      id: string;
      regionId: string;
      name: string;
      address: string;
      city: string;
      phone: string | null;
      photoIds: string[];
      status: Status;
      createdAt: Date;
    }[],
  ) {
    const ids = depots.map((d) => d.id);
    const [regions, held, declarations] = await Promise.all([
      tx.region.findMany({ select: { id: true, name: true } }),
      tx.stock.groupBy({
        by: ["locationId"],
        where: { locationId: { in: ids }, quantity: { gt: 0 } },
        _sum: { quantity: true },
        _count: { _all: true },
      }),
      tx.stockDeclaration.findMany({
        where: { locationId: { in: ids } },
        select: { locationId: true, status: true },
      }),
    ]);
    const regionName = new Map(regions.map((r) => [r.id, r.name]));
    const stock = new Map(held.map((h) => [h.locationId, h]));
    return depots.map((d) => {
      const mine = declarations.filter((x) => x.locationId === d.id);
      return {
        ...d,
        region: { id: d.regionId, name: regionName.get(d.regionId) ?? "" },
        units: stock.get(d.id)?._sum.quantity ?? 0,
        products: stock.get(d.id)?._count._all ?? 0,
        /** Whether its first stock was entered and approved. */
        counted: mine.some((x) => x.status === "APPROVED"),
        /** Whether a count is waiting for the admin. */
        countPending: mine.some((x) => x.status === "PENDING"),
      };
    });
  }
}

/** New photos must belong to the admin; photos the grossiste already shows stay as they are. */
async function ownedProofsOrKept(
  tx: Tx,
  actor: Actor,
  ids: string[],
  depot: { regionId: string; photoIds: string[] },
) {
  const fresh = ids.filter((i) => !depot.photoIds.includes(i));
  const checked = new Set(
    await ownedProofs(tx, actor, fresh, "Add a photo of the grossiste.", {
      regionId: depot.regionId,
      min: 0,
    }),
  );
  requireRule(
    ids.length <= 5 && new Set(ids).size === ids.length,
    "TOO_MANY_PHOTOS",
    "Add between 1 and 5 different photos.",
    422,
  );
  return ids.filter((i) => checked.has(i) || depot.photoIds.includes(i));
}
