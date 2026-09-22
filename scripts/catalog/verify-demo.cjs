const assert = require("node:assert/strict");
const { Database } = require(
  process.env.BIOBALANCE_DIST + "/shared/infrastructure/database.js",
);
const db = new Database();
(async () => {
  const admin = await db.user.findFirstOrThrow({
    where: { platformAdmin: true, disabled: false },
  });
  const stores = await db.store.findMany({
    where: { name: { startsWith: "DÉMO — " } },
    orderBy: { name: "asc" },
  });
  assert.equal(stores.length, 5);
  const results = [];
  for (const store of stores) {
    results.push(
      await db.scoped(admin, store.organizationId, store.id, async (tx) => {
        const [stock] =
          await tx.$queryRaw`SELECT count(*)::int n FROM "InventoryLot" l LEFT JOIN (SELECT "lotId",sum(quantity) FILTER(WHERE bucket='sellable') q,sum(quantity) FILTER(WHERE bucket='damaged') d,count(*) c FROM "StockMovement" WHERE "storeId"=${store.id}::uuid GROUP BY "lotId")m ON m."lotId"=l.id WHERE l."storeId"=${store.id}::uuid AND (l.sellable<>COALESCE(m.q,0) OR l.damaged<>COALESCE(m.d,0) OR l.version<>1+COALESCE(m.c,0))`;
        assert.equal(stock.n, 0, "Stock and versions");
        const [points] =
          await tx.$queryRaw`SELECT count(*)::int n FROM "PointsAccount" a LEFT JOIN (SELECT "userId",sum(amount) balance FROM "PointsEntry" WHERE "storeId"=${store.id}::uuid GROUP BY "userId")p ON p."userId"=a."userId" WHERE a."storeId"=${store.id}::uuid AND a.balance<>COALESCE(p.balance,0)`;
        assert.equal(points.n, 0, "Points ledger");
        const [reserved] =
          await tx.$queryRaw`SELECT count(*)::int n FROM "PointsAccount" a LEFT JOIN (SELECT "userId",sum(cost) reserved FROM "RewardClaim" WHERE "storeId"=${store.id}::uuid AND status='requested' GROUP BY "userId")c ON c."userId"=a."userId" WHERE a."storeId"=${store.id}::uuid AND a.reserved<>COALESCE(c.reserved,0)`;
        assert.equal(reserved.n, 0, "Reservations");
        assert.equal(
          await tx.storeProduct.count({ where: { storeId: store.id } }),
          51,
          "All catalog products have a store price and points configuration",
        );
        const sales = await tx.sale.count({ where: { storeId: store.id } });
        assert.equal(sales, 20);
        const revisions = await tx.saleRevision.count({
          where: { storeId: store.id },
        });
        assert.equal(revisions, 22);
        assert.equal(
          await tx.rewardClaim.count({
            where: { storeId: store.id, status: "fulfilled" },
          }),
          1,
        );
        assert.equal(
          await tx.rewardClaim.count({
            where: { storeId: store.id, status: "requested" },
          }),
          1,
        );
        const receipts = await tx.deliveryReceipt.count({
          where: { storeId: store.id },
        });
        await tx.auditEntry.create({
          data: {
            actorId: admin.id,
            organizationId: store.organizationId,
            storeId: store.id,
            action: "demo.verification",
            targetId: store.id,
            details: {
              stock: true,
              points: true,
              reservations: true,
              sales,
              revisions,
            },
          },
        });
        return {
          store: store.name,
          sales,
          revisions,
          receipts,
          stockConsistent: true,
          pointsConsistent: true,
          reservationsConsistent: true,
        };
      }),
    );
  }
  const products = await db.product.count();
  assert.equal(products, 51);
  const images = await db.product.count({ where: { imageId: { not: null } } });
  assert.equal(images, 51);
  assert.equal(await db.product.count({ where: { active: true } }), 51);
  const sampleProducts = await db.product.findMany({
    where: { name: { endsWith: " — prix démo" } },
  });
  assert.equal(sampleProducts.length, 7);
  assert.ok(
    sampleProducts.every((product) =>
      product.description.includes("PRIX DE DÉMONSTRATION"),
    ),
  );
  const codes = await db.product.count({ where: { barcode: { not: null } } });
  assert.equal(codes, 39);
  const [jobs] =
    await db.$queryRaw`SELECT count(*)::int n FROM "Job" WHERE kind='email' AND payload::text LIKE '%@demo.biobalance.invalid%'`;
  assert.equal(jobs.n, 0, "No demo account emails");
  console.log(
    JSON.stringify(
      { products, images, barcodes: codes, stores: results },
      null,
      2,
    ),
  );
})()
  .catch((e) => {
    console.error("Demo verification failed:", e.name, e.message);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
