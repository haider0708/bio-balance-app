import { Injectable } from "@nestjs/common";
import type { Role, Status } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { nextStatus, type StatusAction } from "../../core/approval";
import { Database } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins } from "../../core/notifier";
import { issueCode } from "../auth/codes";

export interface NewMember {
  name: string;
  email: string;
  phone?: string | null;
}
export interface DepotInput {
  name: string;
  address: string;
  city: string;
  phone?: string | null;
}

const publicUser = {
  id: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  status: true,
  regionId: true,
  pdvId: true,
  passwordHash: true,
  createdAt: true,
  decisionNote: true,
  createdById: true,
} as const;

function present<T extends { passwordHash: string | null }>(user: T) {
  const { passwordHash, ...rest } = user;
  return { ...rest, activated: passwordHash !== null };
}

/** People: responsables and grossistes (admin), team members (responsable, approved by the admin). */
@Injectable()
export class UsersService {
  constructor(private readonly db: Database) {}

  /** The admin creates a responsable or a grossiste. Both are active at once and receive an invitation. */
  async createByAdmin(
    actor: Actor,
    input:
      | ({ role: "RESPONSABLE"; regionId: string } & NewMember)
      | ({ role: "GROSSISTE"; regionId: string; depot: DepotInput } & NewMember)
      | ({ role: "VENDEUR"; pdvId: string } & NewMember),
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin can do this.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      await this.assertEmailFree(tx, input.email);
      let regionId: string | null = null;
      let pdvId: string | null = null;
      if (input.role === "GROSSISTE")
        requireRule(
          await tx.region.findUnique({ where: { id: input.regionId } }),
          "REGION_NOT_FOUND",
          "Unknown region.",
          404,
        );
      if (input.role === "RESPONSABLE") {
        regionId = input.regionId;
        requireRule(
          await tx.region.findUnique({ where: { id: regionId } }),
          "REGION_NOT_FOUND",
          "Unknown region.",
          404,
        );
        requireRule(
          !(await tx.user.findFirst({
            where: {
              role: "RESPONSABLE",
              regionId,
              status: { in: ["PENDING", "ACTIVE"] },
            },
          })),
          "REGION_HAS_RESPONSABLE",
          "This region already has a responsable.",
          409,
        );
      }
      if (input.role === "VENDEUR") {
        const pdv = await tx.pdv.findUnique({ where: { id: input.pdvId } });
        requireRule(pdv, "PDV_NOT_FOUND", "Point of sale not found.", 404);
        regionId = pdv.regionId;
        pdvId = pdv.id;
      }
      const user = await tx.user.create({
        data: {
          email: input.email,
          name: input.name,
          phone: input.phone ?? null,
          role: input.role,
          status: "ACTIVE",
          regionId,
          pdvId,
          createdById: actor.id,
          decidedById: actor.id,
          decidedAt: new Date(),
        },
      });
      if (input.role === "GROSSISTE")
        await tx.depot.create({
          data: {
            userId: user.id,
            regionId: input.regionId,
            name: input.depot.name,
            address: input.depot.address,
            city: input.depot.city,
            phone: input.depot.phone ?? null,
          },
        });
      await issueCode(tx, user.id, "invite");
      await audit(
        tx,
        actor,
        "user.created",
        "User",
        user.id,
        { role: input.role, email: input.email },
        regionId ?? (input.role === "GROSSISTE" ? input.regionId : null),
      );
      return present(user);
    });
  }

  /** A responsable adds a vendeur to a point of sale of their region. The admin must approve. */
  async addMember(actor: Actor, pdvId: string, input: NewMember) {
    requireRule(
      actor.role === "RESPONSABLE" && actor.regionId,
      "FORBIDDEN",
      "Only a responsable adds team members.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const pdv = await tx.pdv.findUnique({ where: { id: pdvId } });
      if (!pdv) throw notFound("Point of sale");
      await this.assertEmailFree(tx, input.email);
      const user = await tx.user.create({
        data: {
          email: input.email,
          name: input.name,
          phone: input.phone ?? null,
          role: "VENDEUR",
          status: "PENDING",
          regionId: pdv.regionId,
          pdvId: pdv.id,
          createdById: actor.id,
        },
      });
      await audit(
        tx,
        actor,
        "member.created",
        "User",
        user.id,
        { pdvId, name: input.name },
        pdv.regionId,
      );
      await notifyAdmins(tx, {
        key: "member.submitted",
        params: { name: user.name, pdv: pdv.name, by: actor.name },
        entityType: "User",
        entityId: user.id,
      });
      return present(user);
    });
  }

  list(
    actor: Actor,
    filter: {
      role?: Role;
      status?: Status;
      regionId?: string;
      pdvId?: string;
      q?: string;
    },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const users = await tx.user.findMany({
        where: {
          // A responsable only ever sees the vendeurs of their own region.
          ...(actor.role === "RESPONSABLE"
            ? { role: "VENDEUR" as Role, regionId: actor.regionId }
            : {
                ...(filter.role && { role: filter.role }),
                ...(filter.regionId && { regionId: filter.regionId }),
              }),
          ...(filter.status && { status: filter.status }),
          ...(filter.pdvId && { pdvId: filter.pdvId }),
          ...(filter.q && {
            OR: [
              { name: { contains: filter.q, mode: "insensitive" } },
              { email: { contains: filter.q, mode: "insensitive" } },
            ],
          }),
        },
        select: publicUser,
        orderBy: [{ name: "asc" }],
        take: 500,
      });
      return users.map(present);
    });
  }

  async get(actor: Actor, id: string) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const user = await this.db.user.findUnique({
      where: { id },
      select: publicUser,
    });
    const visible =
      user &&
      (actor.role === "ADMIN" ||
        (user.role === "VENDEUR" && user.regionId === actor.regionId));
    if (!visible) throw notFound("User");
    return present(user);
  }

  async update(
    actor: Actor,
    id: string,
    input: { name?: string; phone?: string | null; pdvId?: string },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const user = await tx.user.findUnique({ where: { id } });
      const visible =
        user &&
        (actor.role === "ADMIN" ||
          (user.role === "VENDEUR" && user.regionId === actor.regionId));
      if (!user || !visible) throw notFound("User");
      if (input.pdvId) {
        requireRule(
          user.role === "VENDEUR",
          "INVALID_STATE",
          "Only team members can move.",
          409,
        );
        const pdv = await tx.pdv.findUnique({ where: { id: input.pdvId } });
        requireRule(
          pdv && pdv.regionId === user.regionId,
          "PDV_NOT_FOUND",
          "Choose a point of sale of this region.",
          404,
        );
      }
      const updated = await tx.user.update({
        where: { id },
        data: {
          ...(input.name !== undefined && { name: input.name }),
          ...(input.phone !== undefined && { phone: input.phone }),
          ...(input.pdvId !== undefined && { pdvId: input.pdvId }),
        },
      });
      await audit(
        tx,
        actor,
        "user.updated",
        "User",
        id,
        { ...input },
        user.regionId,
      );
      return present(updated);
    });
  }

  /**
   * Approve, reject, suspend, reactivate — the admin. A responsable can only
   * suspend (deactivate) a vendeur of their own region.
   */
  async decide(actor: Actor, id: string, action: StatusAction, note?: string) {
    const allowed =
      actor.role === "ADMIN" ||
      (actor.role === "RESPONSABLE" && action === "suspend");
    requireRule(allowed, "FORBIDDEN", "Not allowed.", 403);
    requireRule(
      action !== "reject" || note?.trim(),
      "NOTE_REQUIRED",
      "Explain the rejection.",
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "User", id);
      const user = await tx.user.findUnique({ where: { id } });
      const visible =
        user &&
        (actor.role === "ADMIN" ||
          (user.role === "VENDEUR" && user.regionId === actor.regionId));
      if (!user || !visible) throw notFound("User");
      requireRule(
        user.id !== actor.id,
        "SELF_ACTION",
        "You cannot change your own access.",
        403,
      );
      requireRule(
        user.role !== "ADMIN",
        "FORBIDDEN",
        "Administrators are not managed here.",
        403,
      );
      const status = nextStatus(user.status, action);
      if (action === "reactivate" && user.role === "RESPONSABLE")
        requireRule(
          !(await tx.user.findFirst({
            where: {
              role: "RESPONSABLE",
              regionId: user.regionId,
              status: { in: ["PENDING", "ACTIVE"] },
              id: { not: id },
            },
          })),
          "REGION_HAS_RESPONSABLE",
          "This region already has a responsable.",
          409,
        );
      const updated = await tx.user.update({
        where: { id },
        data: {
          status,
          decisionNote: note?.trim() || null,
          decidedById: actor.id,
          decidedAt: new Date(),
        },
      });
      if (status === "ACTIVE" && action === "approve")
        await issueCode(tx, id, "invite");
      if (status === "SUSPENDED")
        await tx.session.updateMany({
          where: { userId: id, revokedAt: null },
          data: { revokedAt: new Date() },
        });
      await audit(
        tx,
        actor,
        `user.${action}`,
        "User",
        id,
        { note: note ?? null },
        user.regionId,
      );
      const key = {
        approve: "member.approved",
        reject: "member.rejected",
        suspend: "member.suspended",
        reactivate: "member.reactivated",
        resubmit: "member.submitted",
      }[action];
      if (user.createdById && user.createdById !== actor.id)
        await notify(tx, [user.createdById], {
          key,
          params: { name: user.name, note: note ?? null },
          entityType: "User",
          entityId: id,
        });
      return present(updated);
    });
  }

  /** Send a new activation code to someone who was approved but has not set a password. */
  async resendInvite(actor: Actor, id: string) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const user = await tx.user.findUnique({ where: { id } });
      const visible =
        user &&
        (actor.role === "ADMIN" ||
          (user.role === "VENDEUR" && user.regionId === actor.regionId));
      if (!user || !visible) throw notFound("User");
      requireRule(
        user.status === "ACTIVE" && !user.passwordHash,
        "INVALID_STATE",
        "This person already has an account or is not approved.",
        409,
      );
      await issueCode(tx, id, "invite");
      return { ok: true };
    });
  }

  // ───────────────────────── Depots ─────────────────────────

  async listDepots(actor: Actor) {
    requireRule(
      ["ADMIN", "RESPONSABLE", "GROSSISTE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const depots = await tx.depot.findMany({ orderBy: { name: "asc" } });
      const owners = await tx.user.findMany({
        where: { id: { in: depots.map((d) => d.userId) } },
        select: {
          id: true,
          name: true,
          email: true,
          phone: true,
          status: true,
        },
      });
      const byId = new Map(owners.map((o) => [o.id, o]));
      const regions = new Map(
        (await tx.region.findMany()).map((r) => [r.id, r.name]),
      );
      return depots.map((d) => ({
        ...d,
        region: { id: d.regionId, name: regions.get(d.regionId) ?? "" },
        grossiste: byId.get(d.userId) ?? null,
      }));
    });
  }

  async updateDepot(actor: Actor, id: string, input: Partial<DepotInput>) {
    return this.db.run(actor, async (tx) => {
      const depot = await tx.depot.findUnique({ where: { id } });
      if (!depot) throw notFound("Depot");
      requireRule(
        actor.role === "ADMIN" || depot.userId === actor.id,
        "FORBIDDEN",
        "Not allowed.",
        403,
      );
      const updated = await tx.depot.update({
        where: { id },
        data: {
          ...(input.name !== undefined && { name: input.name }),
          ...(input.address !== undefined && { address: input.address }),
          ...(input.city !== undefined && { city: input.city }),
          ...(input.phone !== undefined && { phone: input.phone }),
        },
      });
      await audit(tx, actor, "depot.updated", "Depot", id, { ...input });
      return updated;
    });
  }

  private async assertEmailFree(
    tx: Parameters<Parameters<Database["run"]>[1]>[0],
    email: string,
  ) {
    if (await tx.user.findUnique({ where: { email }, select: { id: true } }))
      throw new DomainError(
        "EMAIL_TAKEN",
        "This email already has an account.",
        409,
      );
  }
}
