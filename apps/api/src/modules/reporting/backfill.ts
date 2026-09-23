import { Prisma } from "@prisma/client";
import { Database } from "../../shared/infrastructure/database";

/** Bounded and resumable. The final scan waits for locked live sales instead
 * of confusing SKIP LOCKED's empty result with a completed backfill. */
export async function backfillReporting(db: Pick<Database, "transaction">) {
  let processed = 0;
  let after: string | null = null;
  for (;;) {
    const rows = await db.transaction(async (tx) => {
      const rows = await tx.$queryRaw<
        { id: string; existing: boolean; needed: boolean }[]
      >(Prisma.sql`
        WITH page AS MATERIALIZED (
          SELECT id FROM "Sale" ${after ? Prisma.sql`WHERE id>${after}::uuid` : Prisma.empty}
          ORDER BY id LIMIT 1000
        )
        SELECT s.id,c."saleId" IS NOT NULL AS existing,
          c."saleId" IS NULL OR c.version<>s.version AS needed
        FROM page JOIN "Sale" s ON s.id=page.id
        LEFT JOIN "SalesContribution" c ON c."saleId"=s.id
        ORDER BY s.id FOR UPDATE OF s`);
      if (!rows.length) return rows;
      // Existing contributions need their previous values subtracted. This path
      // is rare because the live transaction trigger already handles revisions.
      const existing = rows.filter((r) => r.needed && r.existing);
      if (existing.length)
        await tx.$executeRaw(Prisma.sql`SELECT project_biobalance_sale(id)
        FROM "Sale" WHERE id IN (${Prisma.join(existing.map((r) => Prisma.sql`${r.id}::uuid`))}) ORDER BY id`);
      const fresh = rows.filter((r) => r.needed && !r.existing);
      if (fresh.length)
        await tx.$executeRaw(Prisma.sql`
        WITH lines AS (
          SELECT s.id,s.version,s."organizationId",s."storeId",s."sellerId",
            ((s."occurredAt" AT TIME ZONE 'UTC') AT TIME ZONE st.timezone)::date AS day,
            (l->>'productId')::uuid AS product,
            (l->>'quantity')::bigint-COALESCE(r.qty,0) AS units,
            ((l->>'quantity')::bigint-COALESCE(r.qty,0))*(l->>'unitPriceMillimes')::bigint AS amount
          FROM "Sale" s JOIN "Store" st ON st.id=s."storeId"
          CROSS JOIN LATERAL jsonb_array_elements(s.lines) l
          LEFT JOIN LATERAL (SELECT SUM(value::bigint) qty FROM jsonb_each_text(s.returned)
            WHERE split_part(key,':',1)=l->>'id') r ON true
          WHERE s.id IN (${Prisma.join(fresh.map((r) => Prisma.sql`${r.id}::uuid`))})
        ), added AS (
          INSERT INTO "SalesContribution" ("saleId","organizationId","storeId","sellerId",day,version,"netUnits","netMillimes",products)
          SELECT id,"organizationId","storeId","sellerId",day,version,SUM(units),SUM(amount),
            jsonb_agg(jsonb_build_object('productId',product,'units',units,'amount',amount))
          FROM lines GROUP BY id,"organizationId","storeId","sellerId",day,version RETURNING *
        ), daily AS (
          INSERT INTO "SalesDay" ("organizationId","storeId","sellerId",day,"saleCount","netUnits","netMillimes")
          SELECT "organizationId","storeId","sellerId",day,COUNT(*),SUM("netUnits"),SUM("netMillimes")
          FROM added GROUP BY 1,2,3,4 ORDER BY 2,3,4
          ON CONFLICT ("storeId","sellerId",day) DO UPDATE SET
            "saleCount"="SalesDay"."saleCount"+EXCLUDED."saleCount",
            "netUnits"="SalesDay"."netUnits"+EXCLUDED."netUnits",
            "netMillimes"="SalesDay"."netMillimes"+EXCLUDED."netMillimes" RETURNING 1
        )
        INSERT INTO "SalesProductDay" ("organizationId","storeId","sellerId","productId",day,"netUnits","netMillimes")
        SELECT a."organizationId",a."storeId",a."sellerId",(p->>'productId')::uuid,a.day,
          SUM((p->>'units')::bigint),SUM((p->>'amount')::bigint)
        FROM added a CROSS JOIN LATERAL jsonb_array_elements(a.products) p
        CROSS JOIN (SELECT COUNT(*) FROM daily) daily_completed
        GROUP BY 1,2,3,4,5 ORDER BY 2,3,4,5
        ON CONFLICT ("storeId","sellerId","productId",day) DO UPDATE SET
          "netUnits"="SalesProductDay"."netUnits"+EXCLUDED."netUnits",
          "netMillimes"="SalesProductDay"."netMillimes"+EXCLUDED."netMillimes"`);
      return rows;
    });
    processed += rows.filter((r) => r.needed).length;
    if (!rows.length) return processed;
    after = rows.at(-1)!.id;
  }
}

/** Independently aggregate authoritative lines and returns in one snapshot.
 * This verification never rewrites business or reporting histories. */
export async function reconcileReporting(db: Pick<Database, "$transaction">) {
  return db.$transaction(
    async (tx) => {
      await tx.$executeRaw`CREATE TEMP TABLE expected_sale ON COMMIT DROP AS
      SELECT s.id,s.version,s."organizationId",s."storeId",s."sellerId",
        ((s."occurredAt" AT TIME ZONE 'UTC') AT TIME ZONE st.timezone)::date AS day,
        COALESCE(SUM((l->>'quantity')::bigint-COALESCE(r.qty,0)),0)::bigint AS units,
        COALESCE(SUM(((l->>'quantity')::bigint-COALESCE(r.qty,0))*(l->>'unitPriceMillimes')::bigint),0)::bigint AS amount
      FROM "Sale" s JOIN "Store" st ON st.id=s."storeId"
      LEFT JOIN LATERAL jsonb_array_elements(s.lines) l ON true
      LEFT JOIN LATERAL (SELECT SUM(value::bigint) qty FROM jsonb_each_text(s.returned) WHERE split_part(key,':',1)=l->>'id') r ON true
      GROUP BY s.id,st.timezone`;
      const [sales] = await tx.$queryRaw<
        { count: bigint }[]
      >`SELECT COUNT(*) AS count FROM expected_sale e FULL JOIN "SalesContribution" c ON c."saleId"=e.id
      WHERE e.id IS NULL OR c."saleId" IS NULL OR (e.version,e."organizationId",e."storeId",e."sellerId",e.day,e.units,e.amount)
        IS DISTINCT FROM (c.version,c."organizationId",c."storeId",c."sellerId",c.day,c."netUnits",c."netMillimes")`;
      const [days] = await tx.$queryRaw<{ count: bigint }[]>`WITH expected AS (
      SELECT "organizationId","storeId","sellerId",day,COUNT(*) n,SUM(units) units,SUM(amount) amount FROM expected_sale GROUP BY 1,2,3,4)
      SELECT COUNT(*) AS count FROM expected e FULL JOIN "SalesDay" d USING ("organizationId","storeId","sellerId",day)
      WHERE (COALESCE(e.n,0),COALESCE(e.units,0),COALESCE(e.amount,0)) IS DISTINCT FROM (COALESCE(d."saleCount",0),COALESCE(d."netUnits",0),COALESCE(d."netMillimes",0))`;
      const [products] = await tx.$queryRaw<
        { count: bigint }[]
      >`WITH expected AS (
      SELECT s."organizationId",s."storeId",s."sellerId",(l->>'productId')::uuid AS "productId",e.day,
        SUM((l->>'quantity')::bigint-COALESCE(r.qty,0)) units,
        SUM(((l->>'quantity')::bigint-COALESCE(r.qty,0))*(l->>'unitPriceMillimes')::bigint) amount
      FROM "Sale" s JOIN expected_sale e ON e.id=s.id CROSS JOIN LATERAL jsonb_array_elements(s.lines) l
      LEFT JOIN LATERAL (SELECT SUM(value::bigint) qty FROM jsonb_each_text(s.returned) WHERE split_part(key,':',1)=l->>'id') r ON true GROUP BY 1,2,3,4,5)
      SELECT COUNT(*) AS count FROM expected e FULL JOIN "SalesProductDay" d USING ("organizationId","storeId","sellerId","productId",day)
      WHERE (COALESCE(e.units,0),COALESCE(e.amount,0)) IS DISTINCT FROM (COALESCE(d."netUnits",0),COALESCE(d."netMillimes",0))`;
      const result = {
        saleMismatches: Number(sales!.count),
        dayMismatches: Number(days!.count),
        productMismatches: Number(products!.count),
      };
      if (Object.values(result).some((n) => n !== 0))
        throw new Error(
          `REPORTING_RECONCILIATION_FAILED ${JSON.stringify(result)}`,
        );
      return result;
    },
    {
      isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
      timeout: 180000,
    },
  );
}
if (require.main === module) {
  const db = new Database();
  void backfillReporting(db)
    .then(async (processed) => {
      // Owner-run maintenance refreshes estimates after a large historical import.
      await db.$executeRawUnsafe(
        'ANALYZE "SalesDay", "SalesProductDay", "SalesContribution"',
      );
      console.log(
        JSON.stringify({ processed, ...(await reconcileReporting(db)) }),
      );
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    })
    .finally(() => db.$disconnect());
}
