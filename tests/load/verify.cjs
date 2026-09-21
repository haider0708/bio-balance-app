const { Client } = require("pg"),
  assert = require("node:assert/strict");
const url = process.env.LOAD_OWNER_DATABASE_URL;
if (!url || !new URL(url).pathname.endsWith("_load_test"))
  throw Error("Isolated load database required");
const db = new Client({ connectionString: url });
(async () => {
  await db.connect();
  for (const [name, sql] of Object.entries({
    stock: `SELECT count(*)::int n FROM "InventoryLot" l LEFT JOIN (SELECT "lotId",sum(quantity) FILTER(WHERE bucket='sellable') q,sum(quantity) FILTER(WHERE bucket='damaged') damaged,count(*) c FROM "StockMovement" GROUP BY "lotId")m ON m."lotId"=l.id WHERE l.sellable<>COALESCE(m.q,0) OR l.damaged<>COALESCE(m.damaged,0) OR l.version<>1+COALESCE(m.c,0)`,
    points: `SELECT count(*)::int n FROM "PointsAccount" a FULL JOIN (SELECT "storeId","userId",sum(amount) balance FROM "PointsEntry" GROUP BY "storeId","userId")p USING("storeId","userId") WHERE COALESCE(a.balance,0)<>COALESCE(p.balance,0)`,
    revisions: `SELECT count(*)::int n FROM "Sale" s LEFT JOIN "SaleRevision" r ON r."saleId"=s.id AND r.version=s.version WHERE r.id IS NULL`,
    identities: `SELECT count(*)::int n FROM "SaleRevision" r JOIN "Sale" s ON s.id=r."saleId" WHERE s."storeId"<>r."storeId" OR s."organizationId"<>r."organizationId"`,
  })) {
    const n = (await db.query(sql)).rows[0].n;
    assert.equal(n, 0, name);
    console.log(`PASS ${name}: zero inconsistent records`);
  }
  console.log(
    JSON.stringify(
      (
        await db.query(
          'SELECT (SELECT count(*) FROM "Store") stores,(SELECT count(*) FROM "User") users,(SELECT count(*) FROM "Sale") sales,(SELECT count(*) FROM "InventoryLot") lots',
        )
      ).rows[0],
    ),
  );
})()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.end());
