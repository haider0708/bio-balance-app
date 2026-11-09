import type { Database } from "../core/database";
import { purgeOldVisits } from "./visits";

const DAY = 86_400_000;

/** Delete a table's expired rows a thousand at a time, so cleanup never holds long locks. */
async function purge(run: () => Promise<number>) {
  for (;;) if ((await run()) < 1000) return;
}

/** Remove short-lived credentials and telemetry. Business history is never touched. */
export async function cleanup(db: Database, now = new Date()) {
  const day = new Date(now.getTime() - DAY);
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "LoginAttempt" WHERE key IN (SELECT key FROM "LoginAttempt" WHERE "windowStart" < ${day} LIMIT 1000)`,
  );
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "Session" WHERE id IN (SELECT id FROM "Session" WHERE "expiresAt" < ${new Date(now.getTime() - 7 * DAY)} OR "revokedAt" < ${new Date(now.getTime() - 7 * DAY)} LIMIT 1000)`,
  );
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "AccessToken" WHERE id IN (SELECT id FROM "AccessToken" WHERE "expiresAt" < ${new Date(now.getTime() - 7 * DAY)} LIMIT 1000)`,
  );
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "Job" WHERE id IN (SELECT id FROM "Job" WHERE status = 'completed' AND "createdAt" < ${new Date(now.getTime() - 14 * DAY)} LIMIT 1000)`,
  );
  // A message that failed for good (its content is already wiped below) is dropped after two weeks;
  // the monitor only warns about the last three days.
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "Job" WHERE id IN (SELECT id FROM "Job" WHERE status = 'failed' AND kind IN ('email', 'whatsapp') AND "createdAt" < ${new Date(now.getTime() - 14 * DAY)} LIMIT 1000)`,
  );
  // One-time authenticator links (a new administrator's): gone a week after they expire.
  await db.$executeRaw`DELETE FROM "SetupLink" WHERE "expiresAt" < ${new Date(now.getTime() - 7 * DAY)}`;
  // App error reports are kept a month.
  await purge(
    () =>
      db.$executeRaw`DELETE FROM "ClientError" WHERE id IN (SELECT id FROM "ClientError" WHERE "lastSeen" < ${new Date(now.getTime() - 30 * DAY)} LIMIT 1000)`,
  );
  // Calendar links expire after a year (a week of grace before the row goes).
  await db.$executeRaw`DELETE FROM "CalendarFeed" WHERE "createdAt" < ${new Date(now.getTime() - 372 * DAY)}`;
  // Planned visits and their check-ins: 12 months.
  await purgeOldVisits(db);
  // Failed email jobs may still carry a code from older attempts.
  await db.$executeRaw`UPDATE "Job" SET payload = '{}'::jsonb WHERE kind IN ('email', 'whatsapp') AND status = 'failed' AND payload <> '{}'::jsonb`;
}

export async function scheduleCleanup(db: Database, now = new Date()) {
  await db.job.createMany({
    data: [
      {
        kind: "cleanup",
        key: `cleanup:${now.toISOString().slice(0, 13)}`,
        payload: {},
      },
    ],
    skipDuplicates: true,
  });
}
