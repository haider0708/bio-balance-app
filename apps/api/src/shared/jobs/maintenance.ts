import { Database } from "../infrastructure/database";

/** Retain business histories; expire temporary pages, credentials and telemetry. */
export async function cleanupAuthentication(db: Database, now = new Date()) {
  // Expiring snapshots must be cleaned even when their original user never
  // returns. The narrow database capability exposes no other tenant's pages.
  // Remove credentials retained by terminal failures from older releases.
  // Keep pending email intact so delivery retries still work.
  for (;;) {
    const removed =
      await db.$executeRaw`UPDATE "Job" SET payload='{}'::jsonb WHERE id IN
      (SELECT id FROM "Job" WHERE kind='email' AND status='failed' AND payload<>'{}'::jsonb LIMIT 1000)`;
    if (removed < 1000) break;
  }
  for (;;) {
    const [result] = await db.$queryRaw<{ removed: number }[]>`
      SELECT prune_expired_sync_snapshots() AS removed`;
    if (!result || result.removed < 1000) break;
  }
  for (;;) {
    const removed =
      await db.$executeRaw`DELETE FROM "RequestBudget" WHERE "windowStart" < ${new Date(now.getTime() - 86400000)} AND key IN
      (SELECT key FROM "RequestBudget" WHERE "windowStart" < ${new Date(now.getTime() - 86400000)} LIMIT 1000)`;
    if (removed < 1000) break;
  }
  // Bounded deletes keep maintenance from holding locks over the whole table.
  for (;;) {
    const removed =
      await db.$executeRaw`DELETE FROM "LoginAttempt" WHERE "windowStart" < ${new Date(now.getTime() - 86400000)} AND key IN
      (SELECT key FROM "LoginAttempt" WHERE "windowStart" < ${new Date(now.getTime() - 86400000)} LIMIT 1000)`;
    if (removed < 1000) break;
  }
  for (;;) {
    const removed = await db.$executeRaw`DELETE FROM "DeviceToken" WHERE id IN
      (SELECT d.id FROM "DeviceToken" d WHERE NOT EXISTS
        (SELECT 1 FROM "Session" s WHERE s.id=d."sessionId" AND s."userId"=d."userId"
          AND s."revokedAt" IS NULL AND s."expiresAt">${now}) LIMIT 1000)`;
    if (removed < 1000) break;
  }
  // Older releases did not cap registrations. Keep only the newest ten endpoints.
  for (;;) {
    const removed = await db.$executeRaw`DELETE FROM "DeviceToken" WHERE id IN
      (SELECT id FROM (SELECT id,ROW_NUMBER() OVER (PARTITION BY "userId" ORDER BY "updatedAt" DESC,id DESC) AS position
        FROM "DeviceToken") ranked WHERE position>10 LIMIT 1000)`;
    if (removed < 1000) break;
  }
}

export async function scheduleMaintenance(
  db: Database,
  media: boolean,
  now = new Date(),
) {
  const kind = media ? "media-cleanup" : "auth-cleanup";
  await db.job.createMany({
    data: [
      { kind, key: `${kind}:${now.toISOString().slice(0, 13)}`, payload: {} },
    ],
    skipDuplicates: true,
  });
}
