import type { Database } from "../core/database";

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
  // Failed email jobs may still carry a code from older attempts.
  await db.$executeRaw`UPDATE "Job" SET payload = '{}'::jsonb WHERE kind = 'email' AND status = 'failed' AND payload <> '{}'::jsonb`;
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
