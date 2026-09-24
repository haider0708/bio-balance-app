import { WorkspaceLifecycle, lifecycleRequest } from "./lifecycle";
import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import { z } from "zod";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";
import { GroupRequests } from "./group.contracts";
import { WorkspaceService } from "./workspace.service";

@Injectable()
export class GroupService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  lifecycleImpact(actor: Actor, organizationId: string, storeId?: string) {
    return new WorkspaceLifecycle(this.db).impact(
      actor,
      organizationId,
      storeId,
    );
  }
  lifecycle(
    actor: Actor,
    organizationId: string,
    storeId: string | undefined,
    input: z.infer<typeof lifecycleRequest>,
  ) {
    return new WorkspaceLifecycle(this.db).change(
      actor,
      organizationId,
      storeId,
      input,
    );
  }
  list(actor: Actor, after?: string, search?: string) {
    return this.db.authenticated(actor, async (tx, current) => {
      const memberships = await tx.organizationMembership.findMany({
        where: { userId: current.id, active: true },
      });
      const stores = await this.workspace.storesInTransaction(tx, current);
      const ids = [
        ...new Set([
          ...memberships.map((m) => m.organizationId),
          ...stores.map((s) => s.organizationId),
        ]),
      ];
      const rows = await tx.organization.findMany({
        where: {
          ...(!current.platformAdmin ? { status: "active" } : {}),
          ...(!current.platformAdmin
            ? { id: { in: ids, ...(after ? { gt: after } : {}) } }
            : after
              ? { id: { gt: after } }
              : {}),
          ...(search
            ? { name: { contains: search, mode: "insensitive" as const } }
            : {}),
        },
        orderBy: { id: "asc" },
        take: 51,
      });
      const items = rows.slice(0, 50).map((g) => ({
        ...g,
        canManage:
          current.platformAdmin ||
          memberships.some((m) => m.organizationId === g.id),
        storeCount: stores.filter((s) => s.organizationId === g.id).length,
      }));
      const grants = await tx.groupCreationGrant.findMany({
        where: { userId: current.id, organizationId: null },
        select: { id: true },
        orderBy: { createdAt: "asc" },
      });
      return {
        items,
        nextCursor: rows.length > 50 ? items.at(-1)!.id : null,
        creationGrants: grants,
      };
    });
  }
  create(actor: Actor, input: z.infer<typeof GroupRequests.Create>) {
    return this.db.authenticated(actor, async (tx, current) => {
      await tx.$queryRaw`SELECT id FROM "GroupCreationGrant" WHERE id=${input.grantId}::uuid FOR UPDATE`;
      const grant = await tx.groupCreationGrant.findUnique({
        where: { id: input.grantId },
      });
      requireRule(
        grant?.userId === current.id,
        "FORBIDDEN",
        "Autorisation de création de groupe requise.",
        403,
      );
      const hash = createHash("sha256")
        .update(JSON.stringify([input.name, input.phone ?? null]))
        .digest("hex");
      if (grant.organizationId) {
        requireRule(
          grant.creationOperationId === input.operationId &&
            grant.creationPayloadHash === hash,
          "GRANT_USED",
          "Cette autorisation a déjà servi à créer un groupe.",
          409,
        );
        requireRule(
          (
            await tx.organizationMembership.findUnique({
              where: {
                organizationId_userId: {
                  organizationId: grant.organizationId,
                  userId: current.id,
                },
              },
            })
          )?.active,
          "GROUP_ACCESS_REVOKED",
          "Ce groupe n’est plus accessible.",
          403,
        );
        return tx.organization.findUniqueOrThrow({
          where: { id: grant.organizationId },
        });
      }
      const issuer = await tx.user.findUnique({
        where: { id: grant.createdBy },
      });
      requireRule(
        issuer?.platformAdmin && !issuer.disabled,
        "FORBIDDEN",
        "Cette autorisation n’est plus active.",
        403,
      );
      const group = await tx.organization.create({
        data: { name: input.name, phone: input.phone },
      });
      await tx.organizationMembership.create({
        data: { organizationId: group.id, userId: current.id },
      });
      await tx.groupCreationGrant.update({
        where: { id: grant.id },
        data: {
          organizationId: group.id,
          creationOperationId: input.operationId,
          creationPayloadHash: hash,
        },
      });
      await tx.auditEntry.create({
        data: {
          organizationId: group.id,
          actorId: current.id,
          action: "group.create",
          targetId: group.id,
          details: json(input),
        },
      });
      return group;
    });
  }
  update(
    actor: Actor,
    id: string,
    input: z.infer<typeof GroupRequests.Update>,
  ) {
    return this.db.group(actor, id, async (tx, current) => {
      const old = await tx.organization.findUniqueOrThrow({ where: { id } });
      requireRule(
        old.status !== "archived",
        "WORKSPACE_ARCHIVED",
        "Ce groupe est archivé. Son historique reste consultable.",
        409,
      );
      requireRule(
        old.version === input.expectedVersion,
        "VERSION_CONFLICT",
        "Ce groupe a changé. Actualisez les données.",
        409,
      );
      if (input.imageId) {
        const media = await tx.mediaAsset.findUnique({
          where: { id: input.imageId },
        });
        requireRule(
          media?.purpose === "group" &&
            media.organizationId === id &&
            media.status === "ready" &&
            ["image/jpeg", "image/png"].includes(media.mime),
          "MEDIA_SCOPE",
          "Image traitée de ce groupe requise.",
          403,
        );
      }
      const { expectedVersion, ...data } = input;
      const group = await tx.organization.update({
        where: { id },
        data: { ...data, version: { increment: 1 } },
      });
      await tx.auditEntry.create({
        data: {
          organizationId: id,
          actorId: current.id,
          action: "group.update",
          targetId: id,
          details: json(group),
        },
      });
      return group;
    });
  }
  stores(actor: Actor, id: string) {
    return this.db.authenticated(actor, async (tx, current) => {
      const stores = (
        await this.workspace.storesInTransaction(tx, current)
      ).filter((s) => s.organizationId === id);
      const manager = await tx.organizationMembership.findUnique({
        where: {
          organizationId_userId: { organizationId: id, userId: current.id },
        },
      });
      requireRule(
        current.platformAdmin || manager?.active || stores.length > 0,
        "GROUP_ACCESS_REVOKED",
        "Ce groupe n’est plus accessible.",
        403,
      );
      return stores;
    });
  }
  team(actor: Actor, id: string) {
    return this.db.group(actor, id, async (tx) => {
      const managers = await tx.organizationMembership.findMany({
        where: { organizationId: id },
      });
      const members = await tx.membership.findMany({
        where: { organizationId: id },
      });
      const ids = [
        ...new Set([
          ...managers.map((m) => m.userId),
          ...members.map((m) => m.userId),
        ]),
      ];
      const users = await tx.user.findMany({
        where: { id: { in: ids }, platformAdmin: false },
        select: { id: true, name: true, email: true, disabled: true },
      });
      const invitations = await tx.accessToken.findMany({
        where: {
          organizationId: id,
          purpose: "invite",
          usedAt: null,
          expiresAt: { gt: new Date() },
        },
        select: {
          id: true,
          email: true,
          kind: true,
          storeIds: true,
          storeId: true,
          expiresAt: true,
        },
      });
      return {
        members: users.map((u) => {
          const manager = managers.find((m) => m.userId === u.id);
          const assigned = members.filter((m) => m.userId === u.id && m.active);
          return {
            id: u.id,
            name: u.name,
            email: u.email,
            role: manager?.active ? "responsible" : "salesperson",
            active: !u.disabled && (!!manager?.active || assigned.length > 0),
            storeIds: assigned.map((m) => m.storeId),
          };
        }),
        invitations,
      };
    });
  }
  member(
    actor: Actor,
    id: string,
    userId: string,
    input: z.infer<typeof GroupRequests.Member>,
  ) {
    return this.db.group(actor, id, async (tx, current) => {
      const target = await tx.user.findUnique({ where: { id: userId } });
      requireRule(
        current.platformAdmin || current.id !== userId,
        "SELF_ACCESS_CHANGE",
        "Vous ne pouvez pas modifier votre propre rôle ou votre propre accès. Adressez-vous à un autre responsable ou à BioBalance.",
        403,
      );
      requireRule(
        target && !target.platformAdmin,
        "FORBIDDEN",
        "Compte non modifiable dans ce groupe.",
        403,
      );
      const manager = await tx.organizationMembership.findUnique({
        where: { organizationId_userId: { organizationId: id, userId } },
      });
      const assigned = await tx.membership.findMany({
        where: { organizationId: id, userId },
      });
      requireRule(
        manager || assigned.length,
        "NOT_FOUND",
        "Membre introuvable.",
        404,
      );
      requireRule(
        !input.active || !target.disabled,
        "ACCESS_DISABLED",
        "Ce compte est désactivé.",
        409,
      );
      if (manager?.active && (!input.active || input.role !== "responsible")) {
        const [remaining] = await tx.$queryRaw<
          { count: bigint }[]
        >`SELECT COUNT(*) AS count FROM "OrganizationMembership" m JOIN "User" u ON u.id=m."userId" WHERE m."organizationId"=${id}::uuid AND m.active AND NOT u.disabled AND u.id<>${userId}::uuid`;
        requireRule(
          remaining!.count > 0n,
          "LAST_RESPONSIBLE",
          "Conservez au moins un responsable actif.",
        );
      }
      const stores = await tx.store.findMany({ where: { organizationId: id } });
      requireRule(
        input.storeIds.every((s) => stores.some((store) => store.id === s)),
        "STORE_SCOPE",
        "Choisissez les magasins de ce groupe.",
      );
      requireRule(
        !input.active ||
          input.role === "responsible" ||
          input.storeIds.length === 1,
        "STORE_REQUIRED",
        "Choisissez un seul magasin pour ce vendeur.",
      );
      if (input.role === "responsible" || manager)
        await tx.organizationMembership.upsert({
          where: { organizationId_userId: { organizationId: id, userId } },
          create: {
            organizationId: id,
            userId,
            active: input.active && input.role === "responsible",
          },
          update: { active: input.active && input.role === "responsible" },
        });
      // Release old assignments before activating the selected store. Both phases
      // commit together, so transfers preserve the one-store invariant and history.
      for (const store of stores) {
        await tx.$executeRaw`SELECT set_config('app.store_id',${store.id},true)`;
        await tx.membership.updateMany({
          where: { storeId: store.id, userId },
          data: { active: false },
        });
      }
      if (input.active && input.role === "salesperson") {
        const storeId = input.storeIds[0]!;
        requireRule(
          stores.some((s) => s.id === storeId && s.status === "active"),
          "STORE_ACCESS_REVOKED",
          "Choisissez un magasin actif.",
          409,
        );
        await tx.$executeRaw`SELECT set_config('app.store_id',${storeId},true)`;
        await tx.membership.upsert({
          where: { storeId_userId: { storeId, userId } },
          create: {
            organizationId: id,
            storeId,
            userId,
            permissions: ["sell"],
          },
          update: { active: true, permissions: ["sell"] },
        });
      }
      await tx.auditEntry.create({
        data: {
          organizationId: id,
          actorId: current.id,
          action: "group.membership",
          targetId: userId,
          details: json(input),
        },
      });
      return { ok: true };
    });
  }
}
