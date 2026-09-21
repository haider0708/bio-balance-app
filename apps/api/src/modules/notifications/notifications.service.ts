import { randomUUID, createHash } from "node:crypto";
import { requireRule } from "../../shared/domain/errors";
import { Injectable } from "@nestjs/common";
import { Database } from "../../shared/infrastructure/database";
import { WorkspaceService } from "../tenancy/workspace.service";
import { Actor } from "../operations/domain/contracts";
@Injectable()
export class NotificationsService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async list(actor: Actor, after?: string) {
    const stores = await this.workspace.stores(actor);
    return this.db.notification.findMany({
      where: {
        userId: actor.id,
        OR: [{ storeId: null }, { storeId: { in: stores.map((s) => s.id) } }],
        ...(after ? { createdAt: { lt: new Date(after) } } : {}),
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: 100,
    });
  }
  read(actor: Actor, id: string) {
    return this.db.notification.updateMany({
      where: { id, userId: actor.id },
      data: { readAt: new Date() },
    });
  }
  removeDevice(actor: Actor, token: string) {
    return this.db.deviceToken.deleteMany({
      where: { userId: actor.id, token },
    });
  }
  device(actor: Actor, token: string, platform: string) {
    return this.db.deviceToken.upsert({
      where: { token },
      create: { userId: actor.id, token, platform, sessionId: actor.sessionId },
      update: { userId: actor.id, platform, sessionId: actor.sessionId },
    });
  }
  announce(
    actor: Actor,
    organizationId: string,
    storeId: string,
    title: string,
    body: string,
    audience: "all" | "salespeople",
    id: string = randomUUID(),
  ) {
    const payloadHash = createHash("sha256")
      .update(JSON.stringify({ title, body, audience }))
      .digest("hex");
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      requireRule(
        scope.permissions.includes("manage"),
        "FORBIDDEN",
        "Accès réservé au responsable.",
        403,
      );
      await tx.storeCursor.upsert({
        where: { storeId },
        create: { storeId, organizationId },
        update: {},
      });
      await tx.$queryRaw`SELECT "storeId" FROM "StoreCursor" WHERE "storeId"=${storeId}::uuid FOR UPDATE`;
      const prior = await tx.announcement.findFirst({
        where: { id, storeId, organizationId },
      });
      if (prior) {
        requireRule(
          prior.authorId === actor.id && prior.payloadHash === payloadHash,
          "SUBMISSION_REUSED",
          "Cette annonce a déjà été envoyée avec un autre contenu.",
          409,
        );
        return { id: prior.id, recipients: prior.recipientCount };
      }
      const members = await tx.membership.findMany({
        where: {
          storeId,
          organizationId,
          active: true,
          ...(audience === "salespeople"
            ? { permissions: { has: "sell" } }
            : {}),
        },
      });
      const users = await tx.user.findMany({
        where: { id: { in: members.map((m) => m.userId) }, disabled: false },
        select: { id: true },
      });
      await tx.announcement.create({
        data: {
          id,
          organizationId,
          storeId,
          authorId: actor.id,
          title,
          body,
          audience,
          payloadHash,
          recipientCount: users.length,
        },
      });
      for (const user of users) {
        const notification = await tx.notification.create({
          data: {
            organizationId,
            storeId,
            userId: user.id,
            title,
            body,
            eventKey: id,
          },
        });
        await tx.job.create({
          data: {
            kind: "push",
            key: `push:${notification.id}`,
            payload: { notificationId: notification.id, userId: user.id },
          },
        });
      }
      await tx.auditEntry.create({
        data: {
          organizationId,
          storeId,
          actorId: actor.id,
          action: "announcement.send",
          targetId: id,
          operationId: id,
          details: { audience, recipients: users.length },
        },
      });
      const cursor = await tx.storeCursor.update({
        where: { storeId },
        data: { value: { increment: 1 } },
      });
      await tx.change.create({
        data: {
          id,
          organizationId,
          storeId,
          cursor: cursor.value,
          entity: "announcement.send",
          entityId: id,
        },
      });
      return { id, recipients: users.length };
    });
  }
}
