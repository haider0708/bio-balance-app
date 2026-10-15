import type { Client } from "pg";

export interface ClearResult {
  /** The stored names of the photos and documents removed, to delete from the media folder. */
  files: string[];
  counts: Record<string, number>;
  region: { id: string; code: string; name: string };
}

/** The history tables refuse changes (append-only): these guards are lifted inside the clearing only. */
const APPEND_ONLY = [
  ["StockMovement", "StockMovement_append_only"],
  ["SaleRevision", "SaleRevision_append_only"],
  ["WalletEntry", "WalletEntry_append_only"],
  ["AuditEntry", "AuditEntry_append_only"],
] as const;

/**
 * Empties ONE region (a real one) and keeps the region itself: its stores, groups, grossistes,
 * people, sales, stock, restocks, rewards earned, payouts, photos and every history line. Nothing of
 * any other region changes, and neither do the admins, the catalogue, the reward rates, the courses
 * and the announcements. A test region (the store reviewers') is refused. One transaction, all or
 * nothing; the database's integrity checks stay on, so a forgotten link aborts the whole thing, and
 * only the append-only guards of the history are lifted, only inside it. Needs the database owner.
 */
export async function clearRegion(
  owner: Client,
  code: string,
): Promise<ClearResult> {
  const counts: Record<string, number> = {};
  const found = await owner.query<{
    id: string;
    code: string;
    name: string;
    sandbox: boolean;
  }>(`SELECT id, code, name, sandbox FROM "Region" WHERE code = $1`, [code]);
  const region = found.rows[0];
  if (!region) throw new Error(`There is no region with the code ${code}.`);
  if (region.sandbox)
    throw new Error(
      "This is a test region: remove it with the purge command, not this one.",
    );

  const run = async (name: string, sql: string, values: unknown[]) => {
    counts[name] = (await owner.query(sql, values)).rowCount ?? 0;
  };
  const list = async (sql: string, values: unknown[]) =>
    (await owner.query<{ id: string }>(sql, values)).rows.map((r) => r.id);

  await owner.query("BEGIN");
  try {
    for (const [table, trigger] of APPEND_ONLY)
      await owner.query(`ALTER TABLE "${table}" DISABLE TRIGGER "${trigger}"`);

    const r = region.id;
    const users = await list(`SELECT id FROM "User" WHERE "regionId" = $1`, [
      r,
    ]);
    const pdvs = await list(`SELECT id FROM "Pdv" WHERE "regionId" = $1`, [r]);
    const depots = await list(`SELECT id FROM "Depot" WHERE "regionId" = $1`, [
      r,
    ]);
    const places = [...pdvs, ...depots];
    const sales = await list(
      `SELECT id FROM "Sale" WHERE "regionId" = $1 OR "pdvId" = ANY($2::uuid[]) OR "sellerId" = ANY($3::uuid[])`,
      [r, pdvs, users],
    );
    const declarations = await list(
      `SELECT id FROM "StockDeclaration" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
      [r, places],
    );
    const orders = await list(
      `SELECT id FROM "RestockOrder" WHERE "regionId" = $1 OR "supplierRegionId" = $1
         OR "destId" = ANY($2::uuid[]) OR "supplierDepotId" = ANY($3::uuid[])`,
      [r, places, depots],
    );
    const groups = await list(`SELECT id FROM "Group" WHERE "regionId" = $1`, [
      r,
    ]);

    // Photos and documents: those filed under the region, owned by its people, or used by what goes.
    const used = await owner.query<{ id: string }>(
      `SELECT unnest("photoIds") AS id FROM "Depot" WHERE id = ANY($1::uuid[])
       UNION SELECT unnest("photoIds") FROM "StockDeclaration" WHERE id = ANY($2::uuid[])
       UNION SELECT "photoId" FROM "StockDeclaration" WHERE id = ANY($2::uuid[]) AND "photoId" IS NOT NULL
       UNION SELECT unnest("receiptPhotoIds") FROM "RestockOrder" WHERE id = ANY($3::uuid[])
       UNION SELECT "receiptPhotoId" FROM "RestockOrder" WHERE id = ANY($3::uuid[]) AND "receiptPhotoId" IS NOT NULL`,
      [depots, declarations, orders],
    );
    const photos = (
      await owner.query<{ id: string; path: string }>(
        `SELECT id, path FROM "MediaAsset" WHERE purpose = 'PROOF'
           AND ("regionId" = $1 OR "ownerId" = ANY($2::uuid[]) OR id = ANY($3::uuid[]))`,
        [r, users, used.rows.map((x) => x.id)],
      )
    ).rows;
    const everything = [
      r,
      ...users,
      ...places,
      ...sales,
      ...declarations,
      ...orders,
      ...groups,
    ];

    // Alerts of the people who go, and the admin's alerts about what goes.
    await run(
      "Notification",
      `DELETE FROM "Notification" WHERE "userId" = ANY($1::uuid[]) OR "entityId" = ANY($2::uuid[])`,
      [users, everything.filter(Boolean)],
    );
    await run(
      "LessonProgress",
      `DELETE FROM "LessonProgress" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "PushDevice",
      `DELETE FROM "PushDevice" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "Session",
      `DELETE FROM "Session" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "AccessToken",
      `DELETE FROM "AccessToken" WHERE "userId" = ANY($1::uuid[])`,
      [users],
    );
    await run(
      "Job",
      `DELETE FROM "Job" WHERE payload->>'userId' = ANY($1::text[])`,
      [users],
    );

    await run(
      "SaleRevision",
      `DELETE FROM "SaleRevision" WHERE "saleId" = ANY($1::uuid[])`,
      [sales],
    );
    await run(
      "SaleLine",
      `DELETE FROM "SaleLine" WHERE "saleId" = ANY($1::uuid[])`,
      [sales],
    );
    await run(
      "WalletEntry",
      `DELETE FROM "WalletEntry" WHERE "saleId" = ANY($1::uuid[]) OR "userId" = ANY($2::uuid[])`,
      [sales, users],
    );
    await run("Sale", `DELETE FROM "Sale" WHERE id = ANY($1::uuid[])`, [sales]);
    await run(
      "PayoutRequest",
      `DELETE FROM "PayoutRequest" WHERE "regionId" = $1 OR "userId" = ANY($2::uuid[])`,
      [r, users],
    );

    await run(
      "StockMovement",
      `DELETE FROM "StockMovement" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
      [r, places],
    );
    await run(
      "Stock",
      `DELETE FROM "Stock" WHERE "regionId" = $1 OR "locationId" = ANY($2::uuid[])`,
      [r, places],
    );
    await run(
      "StockDeclarationLine",
      `DELETE FROM "StockDeclarationLine" WHERE "declarationId" = ANY($1::uuid[])`,
      [declarations],
    );
    await run(
      "StockDeclaration",
      `DELETE FROM "StockDeclaration" WHERE id = ANY($1::uuid[])`,
      [declarations],
    );
    await run(
      "StockRecount",
      `DELETE FROM "StockRecount" WHERE "locationId" = ANY($1::uuid[]) OR "regionId" = $2`,
      [places, r],
    );
    await run(
      "RestockLine",
      `DELETE FROM "RestockLine" WHERE "orderId" = ANY($1::uuid[])`,
      [orders],
    );
    await run(
      "RestockOrder",
      `DELETE FROM "RestockOrder" WHERE id = ANY($1::uuid[])`,
      [orders],
    );

    await run(
      "AuditEntry",
      `DELETE FROM "AuditEntry" WHERE "regionId" = $1 OR "actorId" = ANY($2::uuid[]) OR "entityId" = ANY($3::text[])`,
      [r, users, everything],
    );
    await run(
      "MediaAsset",
      `DELETE FROM "MediaAsset" WHERE id = ANY($1::uuid[])`,
      [photos.map((p) => p.id)],
    );

    await run("User", `DELETE FROM "User" WHERE id = ANY($1::uuid[])`, [users]);
    await run("Pdv", `DELETE FROM "Pdv" WHERE id = ANY($1::uuid[])`, [pdvs]);
    await run("Group", `DELETE FROM "Group" WHERE id = ANY($1::uuid[])`, [
      groups,
    ]);
    await run("Depot", `DELETE FROM "Depot" WHERE id = ANY($1::uuid[])`, [
      depots,
    ]);

    for (const [table, trigger] of APPEND_ONLY)
      await owner.query(`ALTER TABLE "${table}" ENABLE TRIGGER "${trigger}"`);
    await owner.query("COMMIT");
    return {
      files: photos.map((p) => p.path),
      counts,
      region: { id: r, code: region.code, name: region.name },
    };
  } catch (error) {
    await owner.query("ROLLBACK");
    throw error;
  }
}
