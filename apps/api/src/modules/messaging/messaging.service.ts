import { Injectable } from "@nestjs/common";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, json, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { decodeCursor, page } from "../../core/pagination";
import { type Audience, resolveAudience } from "./audience";

export interface MessageInput {
  title: string;
  body: string;
  audience: Audience;
  pinned?: boolean;
  scheduledFor?: Date | null;
}

@Injectable()
export class MessagingService {
  constructor(private readonly db: Database) {}

  // ───────────────────────── Inbox (everyone) ─────────────────────────

  inbox(
    actor: Actor,
    filter: { limit: number; cursor?: string; unreadOnly?: boolean },
  ) {
    return this.db.run(actor, async (tx) => {
      const after = decodeCursor(filter.cursor);
      const rows = await tx.notification.findMany({
        where: {
          userId: actor.id,
          ...(filter.unreadOnly && { readAt: null }),
          ...(after && {
            OR: [
              { createdAt: { lt: after.createdAt } },
              { createdAt: after.createdAt, id: { lt: after.id } },
            ],
          }),
        },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: filter.limit + 1,
      });
      const result = page(rows, filter.limit);
      // Pinned announcements stay on top of the first page.
      const pinned = filter.cursor
        ? []
        : await tx.notification.findMany({
            where: { userId: actor.id, pinned: true },
            orderBy: { createdAt: "desc" },
            take: 5,
          });
      return {
        ...result,
        pinned,
        unread: await tx.notification.count({
          where: { userId: actor.id, readAt: null },
        }),
      };
    });
  }

  unreadCount(actor: Actor) {
    return this.db.run(actor, async (tx) => ({
      unread: await tx.notification.count({
        where: { userId: actor.id, readAt: null },
      }),
    }));
  }

  markRead(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => {
      const result = await tx.notification.updateMany({
        where: { id, userId: actor.id, readAt: null },
        data: { readAt: new Date() },
      });
      if (
        !result.count &&
        !(await tx.notification.findFirst({ where: { id, userId: actor.id } }))
      )
        throw notFound("Notification");
      return { ok: true };
    });
  }

  markAllRead(actor: Actor) {
    return this.db.run(actor, async (tx) => {
      const result = await tx.notification.updateMany({
        where: { userId: actor.id, readAt: null },
        data: { readAt: new Date() },
      });
      return { marked: result.count };
    });
  }

  // ───────────────────────── Announcements (admin) ─────────────────────────

  /** How many people (and which roles) a message would reach, before sending. */
  async preview(actor: Actor, audience: Audience) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sends announcements.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const users = await resolveAudience(tx, audience);
      const byRole: Record<string, number> = {};
      for (const u of users) byRole[u.role] = (byRole[u.role] ?? 0) + 1;
      return { recipients: users.length, byRole };
    });
  }

  async send(actor: Actor, input: MessageInput) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sends announcements.",
      403,
    );
    const scheduled =
      input.scheduledFor && input.scheduledFor.getTime() > Date.now() + 30_000
        ? input.scheduledFor
        : null;
    return this.db.run(actor, async (tx) => {
      const users = await resolveAudience(tx, input.audience);
      requireRule(
        users.length > 0,
        "NO_RECIPIENTS",
        "This audience has nobody in it yet.",
      );
      const message = await tx.message.create({
        data: {
          authorId: actor.id,
          title: input.title,
          body: input.body,
          audience: json(input.audience),
          pinned: input.pinned ?? false,
          scheduledFor: scheduled,
          recipientCount: users.length,
        },
      });
      if (scheduled)
        await tx.job.create({
          data: {
            kind: "message-send",
            key: `message:${message.id}`,
            payload: { messageId: message.id },
            availableAt: scheduled,
          },
        });
      else
        await this.deliver(
          tx,
          message.id,
          users.map((u) => u.id),
        );
      await audit(
        tx,
        actor,
        scheduled ? "message.scheduled" : "message.sent",
        "Message",
        message.id,
        { recipients: users.length },
      );
      return this.describe(tx, message.id);
    });
  }

  /** Called by the worker for scheduled messages. Safe to run twice. */
  async deliverScheduled(messageId: string) {
    await this.db.run("SYSTEM", async (tx) => {
      await this.db.lock(tx, "Message", messageId);
      const message = await tx.message.findUnique({ where: { id: messageId } });
      if (!message || message.sentAt) return;
      const users = await resolveAudience(tx, message.audience as Audience);
      await tx.message.update({
        where: { id: messageId },
        data: { recipientCount: users.length },
      });
      await this.deliver(
        tx,
        messageId,
        users.map((u) => u.id),
      );
    });
  }

  list(actor: Actor) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sees announcements.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const messages = await tx.message.findMany({
        orderBy: { createdAt: "desc" },
        take: 100,
      });
      const reads = await tx.notification.groupBy({
        by: ["messageId"],
        where: {
          messageId: { in: messages.map((m) => m.id) },
          readAt: { not: null },
        },
        _count: { _all: true },
      });
      const read = new Map(reads.map((r) => [r.messageId, r._count._all]));
      return messages.map((m) => ({
        id: m.id,
        title: m.title,
        body: m.body,
        audience: m.audience,
        pinned: m.pinned,
        scheduledFor: m.scheduledFor,
        sentAt: m.sentAt,
        createdAt: m.createdAt,
        recipientCount: m.recipientCount,
        readCount: read.get(m.id) ?? 0,
        status: m.sentAt ? "SENT" : "SCHEDULED",
      }));
    });
  }

  /** Who got the message and who has read it. */
  recipients(actor: Actor, id: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sees announcements.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const message = await this.describe(tx, id);
      const rows = await tx.notification.findMany({
        where: { messageId: id },
        select: { userId: true, readAt: true },
      });
      const users = await tx.user.findMany({
        where: { id: { in: rows.map((r) => r.userId) } },
        select: { id: true, name: true, role: true },
      });
      const user = new Map(users.map((u) => [u.id, u]));
      return {
        message,
        recipients: rows
          .map((r) => ({
            userId: r.userId,
            name: user.get(r.userId)?.name ?? "",
            role: user.get(r.userId)?.role,
            readAt: r.readAt,
          }))
          .sort((a, b) => a.name.localeCompare(b.name)),
      };
    });
  }

  /** A scheduled message can be withdrawn until it is sent. */
  cancelScheduled(actor: Actor, id: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sends announcements.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "Message", id);
      const message = await tx.message.findUnique({ where: { id } });
      if (!message) throw notFound("Announcement");
      requireRule(
        !message.sentAt,
        "ALREADY_SENT",
        "This announcement was already sent.",
        409,
      );
      await tx.job.deleteMany({
        where: { key: `message:${id}`, status: "pending" },
      });
      await tx.message.delete({ where: { id } });
      await audit(tx, actor, "message.cancelled", "Message", id, {});
      return { ok: true };
    });
  }

  // ───────────────────────── Helpers ─────────────────────────

  private async deliver(tx: Tx, messageId: string, userIds: string[]) {
    const message = await tx.message.findUniqueOrThrow({
      where: { id: messageId },
    });
    for (let i = 0; i < userIds.length; i += 1000)
      await tx.notification.createMany({
        data: userIds.slice(i, i + 1000).map((userId) => ({
          userId,
          kind: "MESSAGE",
          messageId,
          title: message.title,
          body: message.body,
          pinned: message.pinned,
        })),
        skipDuplicates: true,
      });
    await tx.message.update({
      where: { id: messageId },
      data: { sentAt: new Date() },
    });
  }

  private async describe(tx: Tx, id: string) {
    const m = await tx.message.findUnique({ where: { id } });
    if (!m) throw new DomainError("NOT_FOUND", "Announcement not found.", 404);
    const readCount = await tx.notification.count({
      where: { messageId: id, readAt: { not: null } },
    });
    return {
      id: m.id,
      title: m.title,
      body: m.body,
      audience: m.audience,
      pinned: m.pinned,
      scheduledFor: m.scheduledFor,
      sentAt: m.sentAt,
      createdAt: m.createdAt,
      recipientCount: m.recipientCount,
      readCount,
      status: m.sentAt ? "SENT" : "SCHEDULED",
    };
  }
}
