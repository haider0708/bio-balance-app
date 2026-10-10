import type { Database } from "../core/database";
import { noticeText } from "../core/notice-text";
import type { PushMessage, PushTransport } from "./apns";

interface Claimed {
  id: string;
  userId: string;
  kind: string;
  key: string | null;
  params: Record<string, unknown> | null;
  title: string | null;
  /** Created in the last half hour: older ones are only marked, never pushed. */
  fresh: boolean;
}

interface Device {
  token: string;
  userId: string;
  sandbox: boolean;
  locale: string;
}

/** Above this many new alerts for one person at once, one summary is sent instead. */
const MAX_SEPARATE = 3;
/** Alerts sent at the same time. */
const PARALLEL = 20;

/**
 * Hands new notifications to the push service, each one once. Rows are claimed and marked
 * before sending, so two workers never send the same alert. Without a push service the rows
 * are only marked, which keeps the pending index empty.
 */
export class PushDelivery {
  constructor(
    private readonly db: Database,
    private readonly transport: PushTransport | null,
  ) {}

  /** Returns how many notifications were handled (0 when there is nothing new). */
  async tick(): Promise<number> {
    const claimed = await this.db.run(
      "SYSTEM",
      (tx) =>
        tx.$queryRaw<Claimed[]>`
        UPDATE "Notification" SET "pushedAt" = (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
        WHERE id IN (
          SELECT id FROM "Notification" WHERE "pushedAt" IS NULL
          ORDER BY "createdAt" LIMIT 200 FOR UPDATE SKIP LOCKED)
        RETURNING id, "userId", kind, key, params, title,
          "createdAt" > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - interval '30 minutes' AS fresh`,
    );
    const fresh = claimed.filter((n) => n.fresh);
    if (this.transport && fresh.length) await this.send(fresh);
    return claimed.length;
  }

  private async send(notices: Claimed[]) {
    const users = [...new Set(notices.map((n) => n.userId))];
    const { devices, unread } = await this.db.run("SYSTEM", async (tx) => ({
      devices: await tx.$queryRaw<Device[]>`
        SELECT d.token, d."userId", d.sandbox, u.locale FROM "PushDevice" d
        JOIN "Session" s ON s.id = d."sessionId" JOIN "User" u ON u.id = d."userId"
        WHERE d."userId" = ANY(${users}::uuid[]) AND u.status = 'ACTIVE'
          AND s."revokedAt" IS NULL AND s."expiresAt" > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`,
      unread: await tx.$queryRaw<{ userId: string; unread: number }[]>`
        SELECT "userId", COUNT(*)::int AS unread FROM "Notification"
        WHERE "readAt" IS NULL AND "userId" = ANY(${users}::uuid[]) GROUP BY 1`,
    }));
    if (!devices.length) return;
    const badge = new Map(unread.map((u) => [u.userId, u.unread]));
    const jobs: (() => Promise<void>)[] = [];
    const gone: string[] = [];
    for (const device of devices) {
      const locale = device.locale === "en" ? "en" : "fr";
      const mine = notices.filter((n) => n.userId === device.userId);
      const messages =
        mine.length > MAX_SEPARATE
          ? [summary(locale, mine.length)]
          : mine.map((n) => message(locale, n));
      for (const m of messages)
        jobs.push(async () => {
          const outcome = await this.transport!.send(device, {
            ...m,
            badge: badge.get(device.userId) ?? 0,
          });
          if (outcome === "gone") gone.push(device.token);
        });
    }
    for (let i = 0; i < jobs.length; i += PARALLEL)
      await Promise.all(jobs.slice(i, i + PARALLEL).map((job) => job()));
    if (gone.length)
      await this.db.run(
        "SYSTEM",
        (tx) =>
          tx.$executeRaw`DELETE FROM "PushDevice" WHERE token = ANY(${[...new Set(gone)]}::text[])`,
      );
  }
}

function message(
  locale: "fr" | "en",
  notice: Claimed,
): Omit<PushMessage, "badge"> {
  if (notice.kind === "MESSAGE")
    return {
      title: "BioBalance",
      body: clip(notice.title ?? ""),
      thread: "messages",
    };
  const text =
    (notice.key && noticeText(locale, notice.key, notice.params ?? {})) ||
    (locale === "fr" ? "Nouvelle notification" : "New notification");
  return {
    title: "BioBalance",
    body: clip(text),
    thread: notice.key?.split(".")[0] ?? "system",
  };
}

function summary(
  locale: "fr" | "en",
  count: number,
): Omit<PushMessage, "badge"> {
  return {
    title: "BioBalance",
    body:
      locale === "fr"
        ? `${count} nouvelles notifications`
        : `${count} new notifications`,
    thread: "system",
  };
}

/** Lock screens show a few lines; the whole text is in the app. */
const clip = (text: string) =>
  text.length > 240 ? `${text.slice(0, 239)}…` : text;
