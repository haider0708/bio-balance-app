import { NotificationPolicy } from "./infrastructure/notification-policy";
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
    return this.db.authenticated(actor, async (tx, current) => {
      const stores = await this.workspace.storesInTransaction(tx, current);
      const managed = stores
        .filter((s) => s.permissions.includes("manage"))
        .map((s) => s.id);
      const selling = stores
        .filter((s) => s.permissions.includes("sell"))
        .map((s) => s.id);
      return tx.notification.findMany({
        where: {
          userId: actor.id,
          ...(current.platformAdmin
            ? {}
            : {
                OR: [
                  { kind: "operational", storeId: { in: managed } },
                  {
                    kind: "announcement",
                    audience: "all",
                    storeId: { in: stores.map((s) => s.id) },
                  },
                  {
                    kind: "announcement",
                    audience: "salespeople",
                    storeId: { in: selling },
                  },
                ],
              }),
          ...(after ? { createdAt: { lt: new Date(after) } } : {}),
        },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: 100,
      });
    });
  }
  get(actor: Actor, id: string) {
    return this.db.authenticated(actor, (tx) =>
      this.authorizedNotification(tx, actor, id),
    );
  }
  private async authorizedNotification(
    tx: import("@prisma/client").Prisma.TransactionClient,
    actor: Actor,
    id: string,
  ) {
    const n = await tx.notification.findFirst({
      where: { id, userId: actor.id },
    });
    requireRule(
      n && (await new NotificationPolicy(tx).allows(n)),
      "NOT_FOUND",
      "Notification indisponible.",
      404,
    );
    return n!;
  }
  read(actor: Actor, id: string) {
    return this.db.authenticated(actor, async (tx) => {
      await this.authorizedNotification(tx, actor, id);
      return tx.notification.updateMany({
        where: { id, userId: actor.id },
        data: { readAt: new Date() },
      });
    });
  }
  removeDevice(actor: Actor, token: string) {
    return this.db.authenticated(actor, (tx) =>
      tx.deviceToken.deleteMany({
        where: { userId: actor.id, token, sessionId: actor.sessionId },
      }),
    );
  }
  async device(actor: Actor, token: string, platform: string) {
    return this.db.authenticated(actor, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "User" WHERE id=${actor.id}::uuid FOR UPDATE`;
      const user = await tx.user.findUnique({ where: { id: actor.id } });
      requireRule(
        user && !user.disabled,
        "ACCESS_DISABLED",
        "Accès désactivé.",
        403,
      );
      requireRule(actor.sessionId, "SESSION_EXPIRED", "Reconnectez-vous.", 401);
      // Serialize a token transfer and keep late registrations from older sessions
      // from taking the installation back after a successful account switch.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${token},0))`;
      const prior = await tx.deviceToken.findUnique({ where: { token } });
      if (prior?.sessionId && prior.sessionId !== actor.sessionId) {
        const old = await tx.session.findUnique({
          where: { id: prior.sessionId },
        });
        const current = await tx.session.findUniqueOrThrow({
          where: { id: actor.sessionId! },
        });
        requireRule(
          !old || old.createdAt <= current.createdAt,
          "DEVICE_SESSION_OUTDATED",
          "Cet appareil utilise une session plus récente.",
          409,
        );
      }
      // A renewed token replaces the old token for this installation/session.
      await tx.deviceToken.deleteMany({
        where: {
          userId: actor.id,
          sessionId: actor.sessionId,
          platform,
          token: { not: token },
        },
      });
      await tx.$executeRaw`DELETE FROM "DeviceToken" d WHERE d."userId"=${actor.id}::uuid AND
        NOT EXISTS (SELECT 1 FROM "Session" s WHERE s.id=d."sessionId" AND s."userId"=d."userId" AND s."revokedAt" IS NULL AND s."expiresAt">now())`;
      const count = await tx.deviceToken.count({
        where: { userId: actor.id, token: { not: token } },
      });
      requireRule(
        count < 10,
        "DEVICE_LIMIT",
        "Dix appareils sont déjà enregistrés. Déconnectez un ancien appareil avant de continuer.",
        409,
      );
      return tx.deviceToken.upsert({
        where: { token },
        create: {
          userId: actor.id,
          token,
          platform,
          sessionId: actor.sessionId,
        },
        update: { userId: actor.id, platform, sessionId: actor.sessionId },
      });
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
            kind: "announcement",
            audience,
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
