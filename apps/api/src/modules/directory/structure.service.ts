import { Injectable } from "@nestjs/common";
import type { Status } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { nextStatus, type StatusAction } from "../../core/approval";
import { Database, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins, responsableIds } from "../../core/notifier";

export interface PlaceInput {
  name: string;
  address: string;
  city: string;
  phone?: string | null;
  groupId?: string | null;
}

/** Groups and points of sale (PDV). Created by a responsable, approved by the admin. */
@Injectable()
export class StructureService {
  constructor(private readonly db: Database) {}

  regions() {
    return this.db.region.findMany({ orderBy: { name: "asc" } });
  }

  // ───────────────────────── Groups ─────────────────────────

  /**
   * A responsable creates a group for their region and the admin approves it.
   * The admin creates one for any region and it is active at once.
   */
  async createGroup(actor: Actor, input: { name: string; regionId?: string }) {
    const byAdmin = actor.role === "ADMIN";
    requireRule(
      byAdmin || (actor.role === "RESPONSABLE" && actor.regionId),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const regionId = byAdmin ? input.regionId : actor.regionId;
    requireRule(regionId, "REGION_REQUIRED", "Choose a region.", 422);
    return this.db.run(actor, async (tx) => {
      requireRule(
        await tx.region.findUnique({ where: { id: regionId } }),
        "REGION_NOT_FOUND",
        "Unknown region.",
        404,
      );
      const group = await tx.group.create({
        data: {
          name: input.name,
          regionId,
          createdById: actor.id,
          ...(byAdmin && {
            status: "ACTIVE" as const,
            decidedById: actor.id,
            decidedAt: new Date(),
          }),
        },
      });
      await audit(
        tx,
        actor,
        "group.created",
        "Group",
        group.id,
        { name: group.name },
        group.regionId,
      );
      if (byAdmin)
        await notify(tx, await responsableIds(tx, group.regionId), {
          key: "group.approved",
          params: { name: group.name, note: null },
          entityType: "Group",
          entityId: group.id,
        });
      else
        await notifyAdmins(tx, {
          key: "group.submitted",
          params: { name: group.name, by: actor.name },
          entityType: "Group",
          entityId: group.id,
        });
      return group;
    });
  }

  listGroups(actor: Actor, filter: { status?: Status; regionId?: string }) {
    return this.db.run(actor, async (tx) => {
      const groups = await tx.group.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
        },
        orderBy: { name: "asc" },
      });
      const counts = await tx.pdv.groupBy({
        by: ["groupId"],
        where: { groupId: { in: groups.map((g) => g.id) } },
        _count: { _all: true },
      });
      const byGroup = new Map(counts.map((c) => [c.groupId, c._count._all]));
      return groups.map((g) => ({ ...g, pdvCount: byGroup.get(g.id) ?? 0 }));
    });
  }

  updateGroup(actor: Actor, id: string, input: { name: string }) {
    return this.db.run(actor, async (tx) => {
      const group = await tx.group.findUnique({ where: { id } });
      if (!group) throw notFound("Group");
      requireRule(
        ["ADMIN", "RESPONSABLE"].includes(actor.role),
        "FORBIDDEN",
        "Not allowed.",
        403,
      );
      const updated = await tx.group.update({
        where: { id },
        data: { name: input.name },
      });
      await audit(
        tx,
        actor,
        "group.updated",
        "Group",
        id,
        { name: input.name },
        group.regionId,
      );
      return updated;
    });
  }

  decideGroup(actor: Actor, id: string, action: StatusAction, note?: string) {
    return this.db.run(actor, async (tx) => {
      const group = await this.decide(tx, actor, "Group", id, action, note);
      return group;
    });
  }

  // ───────────────────────── Points of sale ─────────────────────────

  /** Same rule as groups: a responsable proposes, the admin creates for any region and it is active at once. */
  async createPdv(actor: Actor, input: PlaceInput & { regionId?: string }) {
    const byAdmin = actor.role === "ADMIN";
    requireRule(
      byAdmin || (actor.role === "RESPONSABLE" && actor.regionId),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const regionId = byAdmin ? input.regionId : actor.regionId;
    requireRule(regionId, "REGION_REQUIRED", "Choose a region.", 422);
    return this.db.run(actor, async (tx) => {
      requireRule(
        await tx.region.findUnique({ where: { id: regionId } }),
        "REGION_NOT_FOUND",
        "Unknown region.",
        404,
      );
      if (input.groupId) {
        const group = await tx.group.findUnique({
          where: { id: input.groupId },
        });
        requireRule(
          group && group.regionId === regionId,
          "GROUP_NOT_FOUND",
          "Choose a group of the same region.",
          404,
        );
      }
      const pdv = await tx.pdv.create({
        data: {
          name: input.name,
          address: input.address,
          city: input.city,
          phone: input.phone ?? null,
          groupId: input.groupId ?? null,
          regionId,
          createdById: actor.id,
          ...(byAdmin && {
            status: "ACTIVE" as const,
            decidedById: actor.id,
            decidedAt: new Date(),
          }),
        },
      });
      await audit(
        tx,
        actor,
        "pdv.created",
        "Pdv",
        pdv.id,
        { name: pdv.name },
        pdv.regionId,
      );
      if (byAdmin)
        await notify(tx, await responsableIds(tx, pdv.regionId), {
          key: "pdv.approved",
          params: { name: pdv.name, note: null },
          entityType: "Pdv",
          entityId: pdv.id,
        });
      else
        await notifyAdmins(tx, {
          key: "pdv.submitted",
          params: { name: pdv.name, by: actor.name },
          entityType: "Pdv",
          entityId: pdv.id,
        });
      return pdv;
    });
  }

  async listPdvs(
    actor: Actor,
    filter: {
      status?: Status;
      regionId?: string;
      groupId?: string;
      q?: string;
    },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "VENDEUR"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const pdvs = await tx.pdv.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(filter.groupId && { groupId: filter.groupId }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
          ...(filter.q && {
            name: { contains: filter.q, mode: "insensitive" },
          }),
        },
        orderBy: { name: "asc" },
      });
      return this.decorate(tx, pdvs);
    });
  }

  async getPdv(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => {
      const pdv = await tx.pdv.findUnique({ where: { id } });
      if (!pdv) throw notFound("Point of sale");
      return (await this.decorate(tx, [pdv]))[0]!;
    });
  }

  updatePdv(actor: Actor, id: string, input: Partial<PlaceInput>) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const pdv = await tx.pdv.findUnique({ where: { id } });
      if (!pdv) throw notFound("Point of sale");
      if (input.groupId) {
        const group = await tx.group.findUnique({
          where: { id: input.groupId },
        });
        requireRule(
          group && group.regionId === pdv.regionId,
          "GROUP_NOT_FOUND",
          "Choose a group of this region.",
          404,
        );
      }
      const updated = await tx.pdv.update({
        where: { id },
        data: {
          ...(input.name !== undefined && { name: input.name }),
          ...(input.address !== undefined && { address: input.address }),
          ...(input.city !== undefined && { city: input.city }),
          ...(input.phone !== undefined && { phone: input.phone }),
          ...(input.groupId !== undefined && { groupId: input.groupId }),
        },
      });
      await audit(
        tx,
        actor,
        "pdv.updated",
        "Pdv",
        id,
        { ...input },
        pdv.regionId,
      );
      return updated;
    });
  }

  decidePdv(actor: Actor, id: string, action: StatusAction, note?: string) {
    return this.db.run(actor, (tx) =>
      this.decide(tx, actor, "Pdv", id, action, note),
    );
  }

  // ───────────────────────── shared ─────────────────────────

  /** Admin decisions, plus a responsable re-submitting a rejected item. */
  private async decide(
    tx: Tx,
    actor: Actor,
    entity: "Group" | "Pdv",
    id: string,
    action: StatusAction,
    note?: string,
  ) {
    const isOwnerAction = action === "resubmit";
    requireRule(
      actor.role === "ADMIN" || (isOwnerAction && actor.role === "RESPONSABLE"),
      "FORBIDDEN",
      "Only the admin can decide.",
      403,
    );
    requireRule(
      action !== "reject" || note?.trim(),
      "NOTE_REQUIRED",
      "Explain the rejection.",
    );
    await this.db.lock(tx, entity, id);
    const row =
      entity === "Group"
        ? await tx.group.findUnique({ where: { id } })
        : await tx.pdv.findUnique({ where: { id } });
    if (!row) throw notFound(entity === "Group" ? "Group" : "Point of sale");
    const status = nextStatus(row.status, action);
    const data = {
      status,
      decisionNote: note?.trim() || null,
      ...(isOwnerAction
        ? {}
        : { decidedById: actor.id, decidedAt: new Date() }),
    };
    const updated =
      entity === "Group"
        ? await tx.group.update({ where: { id }, data })
        : await tx.pdv.update({ where: { id }, data });
    await audit(
      tx,
      actor,
      `${entity.toLowerCase()}.${action}`,
      entity,
      id,
      { note: note ?? null },
      row.regionId,
    );
    const key = `${entity === "Group" ? "group" : "pdv"}.${action === "approve" ? "approved" : action === "reject" ? "rejected" : action === "suspend" ? "suspended" : action === "reactivate" ? "reactivated" : "submitted"}`;
    const recipients = isOwnerAction
      ? []
      : [row.createdById, ...(await responsableIds(tx, row.regionId))];
    await notify(tx, recipients, {
      key,
      params: { name: row.name, note: note ?? null },
      entityType: entity,
      entityId: id,
    });
    if (isOwnerAction)
      await notifyAdmins(tx, {
        key,
        params: { name: row.name, by: actor.name },
        entityType: entity,
        entityId: id,
      });
    return updated;
  }

  /** Adds the group name, team size and stock state the screens need. */
  private async decorate(
    tx: Tx,
    pdvs: Awaited<ReturnType<Tx["pdv"]["findMany"]>>,
  ) {
    if (!pdvs.length) return [];
    const ids = pdvs.map((p) => p.id);
    const [members, declarations, groups] = await Promise.all([
      tx.user.groupBy({
        by: ["pdvId"],
        where: { pdvId: { in: ids }, status: { in: ["PENDING", "ACTIVE"] } },
        _count: { _all: true },
      }),
      tx.stockDeclaration.findMany({
        where: { locationId: { in: ids }, kind: "INITIAL" },
        select: { locationId: true, status: true },
        orderBy: { createdAt: "asc" },
      }),
      tx.group.findMany({
        where: {
          id: {
            in: pdvs.map((p) => p.groupId).filter((g): g is string => !!g),
          },
        },
        select: { id: true, name: true },
      }),
    ]);
    const memberCount = new Map(members.map((m) => [m.pdvId, m._count._all]));
    const groupName = new Map(groups.map((g) => [g.id, g.name]));
    // APPROVED beats PENDING beats REJECTED; NONE when nothing was declared.
    const rank = { APPROVED: 3, PENDING: 2, REJECTED: 1 } as const;
    const stock = new Map<
      string,
      "NONE" | "PENDING" | "APPROVED" | "REJECTED"
    >();
    for (const d of declarations) {
      const current = stock.get(d.locationId);
      if (!current || current === "NONE" || rank[d.status] > rank[current])
        stock.set(d.locationId, d.status);
    }
    return pdvs.map((p) => ({
      ...p,
      groupName: p.groupId ? (groupName.get(p.groupId) ?? null) : null,
      memberCount: memberCount.get(p.id) ?? 0,
      initialStock: stock.get(p.id) ?? "NONE",
    }));
  }
}
