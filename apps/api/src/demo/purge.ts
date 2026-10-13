import type { Client } from "pg";
import {
  DEMO_FILE,
  DEMO_NOTE,
  DEMO_REGION_CODE,
  DEMO_REGION_NAME,
} from "./seed";

export interface PurgeResult {
  /** Whether a demonstration region was found. */
  found: boolean;
  /** The stored names of the demonstration photos, to delete from the media folder. */
  files: string[];
  counts: Record<string, number>;
}

/**
 * Removes everything the demonstration made: its region, stores, people, stock, sales, wallets,
 * restocks, payouts, announcement, photos and the reward periods it added. The history is
 * append-only, so this needs the database owner; it runs as one transaction (all or nothing) and
 * touches nothing that belongs to the real network.
 */
export async function purgeDemo(owner: Client): Promise<PurgeResult> {
  const counts: Record<string, number> = {};
  const { rows } = await owner.query<{ id: string }>(
    `SELECT id FROM "Region" WHERE sandbox OR (code = $1 AND name = $2)`,
    [DEMO_REGION_CODE, DEMO_REGION_NAME],
  );
  if (!rows[0]) return { found: false, files: [], counts };
  const region = rows[0].id;
  await owner.query("BEGIN");
  try {
    await owner.query(`SET LOCAL session_replication_role = replica`);
    const ids = async (sql: string) =>
      (await owner.query<{ id: string }>(sql, [region])).rows.map((r) => r.id);
    const users = await ids(`SELECT id FROM "User" WHERE "regionId" = $1`);
    const places = [
      ...(await ids(`SELECT id FROM "Pdv" WHERE "regionId" = $1`)),
      ...(await ids(`SELECT id FROM "Depot" WHERE "regionId" = $1`)),
    ];
    const sales = await ids(`SELECT id FROM "Sale" WHERE "regionId" = $1`);
    const declarations = (
      await owner.query<{ id: string }>(
        `SELECT id FROM "StockDeclaration" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
        [region, places],
      )
    ).rows.map((r) => r.id);
    const messages = (
      await owner.query<{ id: string }>(
        `SELECT id FROM "Message" WHERE audience @> $1::jsonb`,
        [JSON.stringify({ regionIds: [region] })],
      )
    ).rows.map((r) => r.id);
    const orders = await ids(
      `SELECT id FROM "RestockOrder" WHERE "regionId" = $1 OR "supplierRegionId" = $1`,
    );
    const rules = (
      await owner.query<{ id: string }>(
        `SELECT id FROM "RewardRule" WHERE note = $1`,
        [DEMO_NOTE],
      )
    ).rows.map((r) => r.id);
    const photos = (
      await owner.query<{ id: string; path: string }>(
        `SELECT id, path FROM "MediaAsset" WHERE "fileName" = $1`,
        [DEMO_FILE],
      )
    ).rows;
    const run = async (name: string, sql: string, values: unknown[]) => {
      counts[name] = (await owner.query(sql, values)).rowCount ?? 0;
    };
    await run(
      "SaleLine",
      `DELETE FROM "SaleLine" WHERE "saleId" = ANY($1::uuid[])`,
      [sales],
    );
    await run(
      "SaleRevision",
      `DELETE FROM "SaleRevision" WHERE "saleId" = ANY($1::uuid[])`,
      [sales],
    );
    await run("Sale", `DELETE FROM "Sale" WHERE id = ANY($1::uuid[])`, [sales]);
    await run(
      "WalletEntry",
      `DELETE FROM "WalletEntry" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "PayoutRequest",
      `DELETE FROM "PayoutRequest" WHERE "userId" = ANY($1::uuid[]) OR "regionId" = $2`,
      [users, region],
    );
    await run(
      "StockMovement",
      `DELETE FROM "StockMovement" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
      [region, places],
    );
    await run(
      "Stock",
      `DELETE FROM "Stock" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
      [region, places],
    );
    await run(
      "StockDeclarationLine",
      `DELETE FROM "StockDeclarationLine" WHERE "declarationId" = ANY($1::uuid[])`,
      [declarations],
    );
    await run(
      "StockDeclaration",
      `DELETE FROM "StockDeclaration" WHERE id = ANY($1::uuid[]) OR "locationId" = ANY($2::uuid[])`,
      [declarations, places],
    );
    await run(
      "StockRecount",
      `DELETE FROM "StockRecount" WHERE "locationId" = ANY($1::uuid[])`,
      [places],
    );
    await run(
      "RestockLine",
      `DELETE FROM "RestockLine" WHERE "orderId" = ANY($1::uuid[])`,
      [orders],
    );
    await run(
      "RestockOrder",
      `DELETE FROM "RestockOrder" WHERE id = ANY($1::uuid[]) OR "destId" = ANY($2::uuid[])`,
      [orders, places],
    );
    await run(
      "Notification",
      `DELETE FROM "Notification" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run("Message", `DELETE FROM "Message" WHERE audience @> $1::jsonb`, [
      JSON.stringify({ regionIds: [region] }),
    ]);
    await run("MediaAsset", `DELETE FROM "MediaAsset" WHERE "fileName" = $1`, [
      DEMO_FILE,
    ]);
    // Audit lines of what is removed: by region, by actor and by the id of what they describe.
    const everything = [
      region,
      ...users,
      ...places,
      ...sales,
      ...declarations,
      ...orders,
      ...rules,
      ...messages,
    ];
    await run(
      "AuditEntry",
      `DELETE FROM "AuditEntry" WHERE "regionId" = $1 OR "actorId" = ANY($2::uuid[]) OR "entityId" = ANY($3::text[])`,
      [region, users, everything],
    );
    await run(
      "RewardRule",
      `DELETE FROM "RewardRule" WHERE id = ANY($1::uuid[])`,
      [rules],
    );
    await run(
      "Session",
      `DELETE FROM "Session" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "PushDevice",
      `DELETE FROM "PushDevice" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "AccessToken",
      `DELETE FROM "AccessToken" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "LessonProgress",
      `DELETE FROM "LessonProgress" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "Job",
      `DELETE FROM "Job" WHERE payload->>'userId' = ANY($1::text[])`,
      [users],
    );
    await run("User", `DELETE FROM "User" WHERE id = ANY($1::uuid[])`, [users]);
    await run("Pdv", `DELETE FROM "Pdv" WHERE "regionId" = $1`, [region]);
    await run("Group", `DELETE FROM "Group" WHERE "regionId" = $1`, [region]);
    await run("Depot", `DELETE FROM "Depot" WHERE "regionId" = $1`, [region]);
    await run("Region", `DELETE FROM "Region" WHERE id = $1`, [region]);
    await owner.query("COMMIT");
    return { found: true, files: photos.map((p) => p.path), counts };
  } catch (error) {
    await owner.query("ROLLBACK");
    throw error;
  }
}
