import { Database } from "../infrastructure/database";

/** Retain audit/operation records; prune only expired authentication telemetry. */
export async function cleanupAuthentication(db: Database, now = new Date()) {
  // Bounded deletes keep maintenance from holding locks over the whole table.
  for (;;) {
    const removed = await db.$executeRaw`DELETE FROM "LoginAttempt" WHERE key IN
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
