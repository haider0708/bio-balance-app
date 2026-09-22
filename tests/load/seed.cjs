/* Reproducible synthetic load data. Never targets an existing business database. */
const { Client } = require("pg"),
  { randomUUID, createHash } = require("node:crypto");
const { mkdir, writeFile } = require("node:fs/promises"),
  path = require("node:path");
const url = process.env.LOAD_OWNER_DATABASE_URL;
if (!url || !new URL(url).pathname.endsWith("_load_test"))
  throw Error(
    "LOAD_OWNER_DATABASE_URL must name an isolated *_load_test database",
  );
const db = new Client({ connectionString: url });
const count = Number(process.env.LOAD_SALES ?? 2000000);
if (!Number.isSafeInteger(count) || count < 2000000 || count % 500 !== 0)
  throw Error("Use at least 2,000,000 sales, a multiple of 500");
const output = path.resolve(
  process.env.LOAD_FIXTURES ?? ".artifacts/load-fixtures.json",
);
(async () => {
  await db.connect();
  const users = Number(
    (await db.query('SELECT count(*) FROM "User"')).rows[0].count,
  );
  let firstSale = 1;
  await db.query(
    `CREATE FUNCTION pg_temp.fid(kind text,n bigint) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT overlay(overlay(md5('biobalance-load-v1:'||kind||':'||n) placing '4' from 13 for 1) placing '8' from 17 for 1)::uuid $$;`,
  );
  if (users) {
    if (process.env.LOAD_RESUME_SEED !== "yes")
      throw Error("Database must be empty; existing records are never deleted");
    // Resume only an interrupted v1 batch seed before projections or sessions
    // exist. A database that has served even one API write cannot qualify.
    const {
      rows: [state],
    } = await db.query(`SELECT
      (SELECT count(*) FROM "User" WHERE email !~ '^load-[0-9]+@example.test$' OR "passwordHash"<>'!synthetic-session-only')::int foreign_users,
      (SELECT count(*) FROM "Store")::int stores,
      (SELECT count(*) FROM "Product")::int products,
      (SELECT count(*) FROM "InventoryLot")::int lots,
      (SELECT count(*) FROM "Sale")::int sales,
      (SELECT count(*) FROM "SaleRevision")::int revisions,
      (SELECT count(*) FROM "PointsEntry")::int points,
      (SELECT count(*) FROM "StockMovement")::int movements,
      (SELECT count(*) FROM "AuditEntry")::int audits,
      (SELECT count(*) FROM "Change")::int changes,
      (SELECT count(*) FROM "ProcessedOperation")::int operations,
      (SELECT count(*) FROM "ProcessedOperation" WHERE "payloadHash"<>repeat('0',64))::int accepted_api_operations,
      (SELECT count(*) FROM "Session")::int sessions,
      (SELECT count(*) FROM "PointsAccount")::int accounts,
      (SELECT count(*) FROM "StoreCursor")::int cursors`);
    if (
      users !== 5000 ||
      state.foreign_users ||
      state.stores !== 500 ||
      state.products !== 200 ||
      state.lots !== 300000 ||
      state.sessions ||
      state.accounts ||
      state.cursors ||
      state.accepted_api_operations ||
      state.sales >= count ||
      state.sales % 50000 !== 0 ||
      [
        state.revisions,
        state.points,
        state.audits,
        state.changes,
        state.operations,
      ].some((n) => n !== state.sales) ||
      state.movements !== state.sales + 300000
    )
      throw Error(
        "Resume requires an untouched synthetic dataset at a committed batch boundary",
      );
    firstSale = state.sales + 1;
    console.log(
      `Resuming synthetic history after ${state.sales} committed sales; no records removed.`,
    );
  } else {
    await db.query(`
 INSERT INTO "Organization" (id,name) SELECT pg_temp.fid('org',n),'Partenaire synthétique '||n FROM generate_series(1,125)n;
 INSERT INTO "User" (id,email,name,"passwordHash") SELECT pg_temp.fid('user',n),'load-'||n||'@example.test','Compte synthétique '||n,'!synthetic-session-only' FROM generate_series(1,5000)n;
 INSERT INTO "Store" (id,"organizationId",name,address,city,"onboardingStep") SELECT pg_temp.fid('store',n),pg_temp.fid('org',(n+3)/4),'Magasin synthétique '||n,'Adresse de test','Tunis',5 FROM generate_series(1,500)n;
 INSERT INTO "OrganizationMembership" (id,"organizationId","userId") SELECT pg_temp.fid('owner',n),pg_temp.fid('org',(n+3)/4),pg_temp.fid('user',(n-1)*10+1) FROM generate_series(1,500)n;
 INSERT INTO "Membership" (id,"organizationId","storeId","userId",permissions) SELECT pg_temp.fid('member',n),pg_temp.fid('org',(((n-1)/10+1)+3)/4),pg_temp.fid('store',(n-1)/10+1),pg_temp.fid('user',n),CASE WHEN (n-1)%10=0 THEN ARRAY['manage','sell','receive'] ELSE ARRAY['sell','receive'] END FROM generate_series(1,5000)n;
 INSERT INTO "Product" (id,reference,name,barcode,"updatedAt") SELECT pg_temp.fid('product',n),'LOAD-'||n,'Produit synthétique '||n,'619'||lpad(n::text,10,'0'),now() FROM generate_series(1,200)n;
 INSERT INTO "StoreProduct" (id,"organizationId","storeId","productId","priceMillimes",threshold,"pointsPerUnit","pointsConfigured") SELECT pg_temp.fid('config',(s-1)*200+p),pg_temp.fid('org',(s+3)/4),pg_temp.fid('store',s),pg_temp.fid('product',p),49900,5,10,true FROM generate_series(1,500)s CROSS JOIN generate_series(1,200)p;
 INSERT INTO "InventoryLot" (id,"organizationId","storeId","productId",batch,expiry,sellable,version) SELECT pg_temp.fid('lot',n),pg_temp.fid('org',(((n-1)/600+1)+3)/4),pg_temp.fid('store',(n-1)/600+1),pg_temp.fid('product',((n-1)%600)/3+1),'LOAD-'||((n-1)%3+1),(current_date+interval '2 years'+((n-1)%3)*interval '30 days')::date,1000,2 FROM generate_series(1,300000)n;
 INSERT INTO "StockMovement" (id,"organizationId","storeId","lotId",quantity,reason,"sourceId","actorId","operationId") SELECT pg_temp.fid('opening-movement',n),pg_temp.fid('org',(((n-1)/600+1)+3)/4),pg_temp.fid('store',(n-1)/600+1),pg_temp.fid('lot',n),1000,'opening',pg_temp.fid('opening',n),pg_temp.fid('user',((n-1)/600)*10+1),pg_temp.fid('opening',n) FROM generate_series(1,300000)n;
 `);
    console.log(
      "Seeded 125 organizations, 500 stores, 5,000 accounts, 200 products and 300,000 lots.",
    );
  }
  for (let start = firstSale; start <= count; start += 50000) {
    await db.query("BEGIN");
    try {
      await db.query(
        `CREATE TEMP TABLE load_batch ON COMMIT DROP AS
    WITH idx AS (SELECT g,(g-1)%500+1 AS s,(g-1)/500+1 AS k FROM generate_series($1::bigint,$2::bigint)g),
    refs AS (SELECT *,((k-1)%200)+1 AS p,((k-1)/200)%3+1 AS b FROM idx)
    SELECT g,s,k,pg_temp.fid('sale',g) AS id,pg_temp.fid('operation',g) AS op,
      pg_temp.fid('org',(s+3)/4) AS org,pg_temp.fid('store',s) AS store,
      pg_temp.fid('user',(s-1)*10+(k-1)%10+1) AS seller,
      pg_temp.fid('lot',(s-1)*600+(p-1)*3+b) AS lot,
      now()-($3::bigint/500-k)*interval '2 hours' AS occurred,
      jsonb_build_array(jsonb_build_object('id',pg_temp.fid('line',g),'productId',pg_temp.fid('product',p),'quantity',1,'unitPriceMillimes','49900','pointsPerUnit',10,'allocations',jsonb_build_array(jsonb_build_object('lotId',pg_temp.fid('lot',(s-1)*600+(p-1)*3+b),'quantity',1)))) AS lines
    FROM refs`,
        [start, Math.min(count, start + 49999), count],
      );
      await db.query(`
    INSERT INTO "Sale" (id,"organizationId","storeId","sellerId","occurredAt","acceptedAt","totalMillimes","earnedPoints",lines) SELECT id,org,store,seller,occurred,occurred,49900,10,lines FROM load_batch;
    INSERT INTO "SaleRevision" (id,"organizationId","storeId","saleId",version,"editorId",reason,"after","operationId","createdAt") SELECT pg_temp.fid('revision',g),org,store,id,1,seller,'Vente synthétique',jsonb_build_object('id',id,'sellerId',seller,'occurredAt',occurred,'version',1,'lines',lines,'returned','{}'::jsonb,'totalMillimes','49900','earnedPoints','10'),op,occurred FROM load_batch;
    INSERT INTO "StockMovement" (id,"organizationId","storeId","lotId",quantity,reason,"sourceId","actorId","operationId","createdAt") SELECT pg_temp.fid('movement',g),org,store,lot,-1,'sale',id,seller,op,occurred FROM load_batch;
    INSERT INTO "PointsEntry" (id,"organizationId","storeId","userId",amount,kind,"sourceId","operationId","createdAt") SELECT pg_temp.fid('points',g),org,store,seller,10,'earned',id,op,occurred FROM load_batch;
    INSERT INTO "AuditEntry" (id,"organizationId","storeId","actorId",action,"targetId","operationId",details,"createdAt") SELECT pg_temp.fid('audit',g),org,store,seller,'sale.create',id::text,op,'{"synthetic":true}'::jsonb,occurred FROM load_batch;
    INSERT INTO "Change" (id,"organizationId","storeId",cursor,entity,"entityId","createdAt") SELECT op,org,store,k,'sale.create',id::text,occurred FROM load_batch;
    INSERT INTO "ProcessedOperation" (id,"organizationId","storeId","actorId","payloadHash",result,"createdAt") SELECT op,org,store,seller,repeat('0',64),jsonb_build_object('operationId',op,'status','accepted','data',jsonb_build_object('id',id,'version',1),'committedCursor',k::text),occurred FROM load_batch;
   `);
      await db.query("COMMIT");
      console.log(
        `Historical sales and histories: ${Math.min(count, start + 49999)}/${count}`,
      );
    } catch (error) {
      await db.query("ROLLBACK");
      throw error;
    }
  }
  await db.query(`UPDATE "InventoryLot" l SET sellable=1000-x.units,version=2+x.units FROM (SELECT "lotId",(-sum(quantity))::int AS units FROM "StockMovement" WHERE reason='sale' GROUP BY "lotId")x WHERE l.id=x."lotId";
 INSERT INTO "PointsAccount" (id,"organizationId","storeId","userId",balance) SELECT pg_temp.fid('account',n),pg_temp.fid('org',(((n-1)/10+1)+3)/4),pg_temp.fid('store',(n-1)/10+1),pg_temp.fid('user',n),0 FROM generate_series(1,5000)n;
 UPDATE "PointsAccount" a SET balance=x.points FROM (SELECT "userId",sum(amount) AS points FROM "PointsEntry" GROUP BY "userId")x WHERE a."userId"=x."userId";
 INSERT INTO "StoreCursor" ("storeId","organizationId",value) SELECT id,"organizationId",${count / 500} FROM "Store";
 INSERT INTO "Reward" (id,"organizationId","storeId",title,cost) SELECT pg_temp.fid('reward',n),pg_temp.fid('org',(n+3)/4),pg_temp.fid('store',n),'Cadeau synthétique',100 FROM generate_series(1,500)n;
 ANALYZE;`);
  const fixtures = [];
  for (const row of (
    await db.query(
      `SELECT n,pg_temp.fid('user',n) AS "userId",pg_temp.fid('store',(n-1)/10+1) AS "storeId",pg_temp.fid('org',(((n-1)/10+1)+3)/4) AS "organizationId",pg_temp.fid('product',1) AS "productId",pg_temp.fid('lot',((n-1)/10)*600+1) AS "lotId" FROM generate_series(1,5000)n`,
    )
  ).rows) {
    const token = randomUUID() + randomUUID();
    await db.query(
      'INSERT INTO "Session" (id,"userId","tokenHash","expiresAt") VALUES ($1,$2,$3,now()+interval \'12 hours\')',
      [
        randomUUID(),
        row.userId,
        createHash("sha256").update(token).digest("hex"),
      ],
    );
    fixtures.push({
      ...row,
      token,
      cursor: String(count / 500),
      catalogRevision: "200:200",
    });
  }
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(fixtures), { mode: 0o600 });
  const evidence = {
    createdAt: new Date().toISOString(),
    generator: "v1",
    stores: 500,
    accounts: 5000,
    products: 200,
    lots: 300000,
    sales: count,
    databaseBytes: (
      await db.query(
        "SELECT pg_database_size(current_database())::text AS bytes",
      )
    ).rows[0].bytes,
  };
  await writeFile(output + ".summary.json", JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence));
})()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => db.end());
