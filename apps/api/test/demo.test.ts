import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
import { addDays, tunisDay } from "../src/core/dates";
import { purgeDemo } from "../src/demo/purge";
import { DEMO_REGION_CODE, demoServices, seedDemo } from "../src/demo/seed";
import {
  approvedPdv,
  buildWorld,
  stockPlace,
  teamMember,
  type World,
} from "./world";

let api: Api;
let w: World;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

const PASSWORDS = {
  responsable: "Resp-Demo-2026x",
  vendeur: "Vend-Demo-2026x",
};
const today = () => tunisDay(new Date());

/** The real network: a store with stock and a sale, and the reward rates the admin set. */
async function realNetwork() {
  for (const [i, family] of [
    "Serums",
    "Hair",
    "Care",
    "Care",
    "Hair",
    "Serums",
    "Care",
  ].entries())
    await w.a.post("/v1/products", {
      reference: `Q${i}`,
      name: `Produit ${i}`,
      family,
      barcode: `70000000000${i}`,
    });
  for (const family of ["Serums", "Hair", "Care"])
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family,
      amountMillimes: 600,
      startsOn: addDays(today(), -3),
    });
  const pdv = await approvedPdv(w, "n", "Para Réel");
  await stockPlace(w, pdv.id, w.nord, [30, 30, 30]);
  const seller = await teamMember(w, pdv.id, "Vendeur Réel");
  await client(api, seller.token).post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[0]!.id, quantity: 2 }],
  });
}

async function counts(db: Awaited<ReturnType<typeof owner>>) {
  const { rows } = await db.query<{ tablename: string }>(
    `SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '_prisma_migrations' ORDER BY 1`,
  );
  const result: Record<string, number> = {};
  for (const { tablename } of rows)
    result[tablename] = Number(
      (await db.query(`SELECT count(*) FROM "${tablename}"`)).rows[0].count,
    );
  return result;
}

describe("the demonstration region", () => {
  it("is built with the real rules, adds up, lets reviewers sign in, and leaves with no trace", async () => {
    await realNetwork();
    const db = await owner();
    try {
      const before = await counts(db);
      const auditBefore = new Set(
        (await db.query(`SELECT id FROM "AuditEntry"`)).rows.map((r) => r.id),
      );
      const { rows: realNotes } = await db.query(
        `SELECT count(*) FROM "Notification" WHERE "userId" = $1`,
        [w.admin.id],
      );

      const result = await seedDemo(demoServices(api.app), db, {
        days: 12,
        passwords: PASSWORDS,
      });
      expect(result.sales).toBeGreaterThan(60);
      expect(
        result.accounts.filter((a) => a.role === "RESPONSABLE"),
      ).toHaveLength(1);
      expect(result.accounts.filter((a) => a.role === "VENDEUR")).toHaveLength(
        1,
      );
      // It is the test region: the admin does not see it.
      const regions = (await w.a.get("/v1/regions")).body;
      expect((regions.items ?? regions).map((r: any) => r.id)).not.toContain(
        result.regionId,
      );

      // The reviewers sign in with the given passwords.
      for (const [email, password] of [
        ["demo-vendeur@galylio.com", PASSWORDS.vendeur],
        ["demo-responsable@galylio.com", PASSWORDS.responsable],
      ] as const) {
        const login = await client(api).post("/v1/auth/login", {
          email,
          password,
        });
        expect(login.status, email).toBe(201);
        expect(login.body.token).toBeTruthy();
      }
      expect(
        (
          await client(api).post("/v1/auth/login", {
            email: "demo-ines@galylio.com",
            password: "not-the-password",
          })
        ).status,
      ).toBe(401);

      // Every sale sits at its own moment, over the whole period, and earned its reward.
      const { rows: salesByDay } = await db.query(
        `SELECT min(day)::text AS first, max(day)::text AS last, count(DISTINCT day)::int AS days,
                count(*)::int AS sales, sum(units)::int AS units,
                count(*) FILTER (WHERE "rewardMillimes" = 0)::int AS unpaid,
                count(*) FILTER (WHERE "createdAt" <> "occurredAt" + interval '25 seconds')::int AS misdated
         FROM "Sale" WHERE "regionId" = $1`,
        [result.regionId],
      );
      expect(salesByDay[0]).toMatchObject({
        first: result.from,
        last: today(),
        days: 12,
        sales: result.sales,
        units: result.units,
        unpaid: 0,
        misdated: 0,
      });

      // Stock is never negative and equals what the history says; wallets equal their entries.
      const { rows: stockDrift } = await db.query(
        `SELECT count(*)::int AS bad FROM "Stock" s
         WHERE s."regionId" = $1 AND (s.quantity < 0 OR s.quantity <> COALESCE((
           SELECT sum(m.delta) FROM "StockMovement" m
           WHERE m."locationId" = s."locationId" AND m."productId" = s."productId"), 0))`,
        [result.regionId],
      );
      expect(stockDrift[0].bad).toBe(0);
      const { rows: walletDrift } = await db.query(
        `SELECT count(*)::int AS bad FROM "User" u WHERE u."regionId" = $1 AND u.role = 'VENDEUR' AND
           COALESCE((SELECT sum("amountMillimes") FROM "WalletEntry" w WHERE w."userId" = u.id), 0) < 0`,
        [result.regionId],
      );
      expect(walletDrift[0].bad).toBe(0);

      // The history is believable for the reviewer: a balance, paid and waiting payouts, a restock, an announcement.
      const seller = await client(api).post("/v1/auth/login", {
        email: "demo-vendeur@galylio.com",
        password: PASSWORDS.vendeur,
      });
      const v = client(api, seller.body.token);
      const wallet = (await v.get("/v1/wallet")).body;
      expect(wallet.balanceMillimes).toBeGreaterThan(0);
      const payouts = (await v.get("/v1/payouts")).body;
      const statuses = (payouts.items ?? payouts)
        .map((p: any) => p.status)
        .sort();
      expect(statuses).toContain("PENDING");
      expect(statuses).toContain("APPROVED");
      const days = (
        await v.get(`/v1/sales/days?from=${result.from}&to=${today()}`)
      ).body;
      expect(days.length).toBeGreaterThanOrEqual(10);
      const boss = await client(api).post("/v1/auth/login", {
        email: "demo-responsable@galylio.com",
        password: PASSWORDS.responsable,
      });
      const r = client(api, boss.body.token);
      const restocks = (await r.get("/v1/restocks")).body;
      const states = (restocks.items ?? restocks).map((o: any) => o.status);
      expect(states).toContain("COMPLETED");
      expect(states).toContain("REQUESTED");
      const analytics = await r.get(
        `/v1/analytics/overview?from=${result.from}&to=${today()}`,
      );
      expect(analytics.status).toBe(200);
      expect(analytics.body.totals.sales).toBe(result.sales);
      expect((await r.get("/v1/messages/inbox")).status).toBeLessThan(500);

      // Nothing was told to the real administrator, and no invitation email was left to send.
      const { rows: after } = await db.query(
        `SELECT count(*) FROM "Notification" WHERE "userId" = $1`,
        [w.admin.id],
      );
      expect(after[0].count).toBe(realNotes[0].count);
      expect(
        (
          await db.query(
            `SELECT 1 FROM "Job" WHERE kind = 'email' AND payload->>'template' = 'invite'`,
          )
        ).rowCount,
      ).toBe(0);

      // The real network is untouched by it: a second one is refused.
      await expect(
        seedDemo(demoServices(api.app), db, { days: 3, passwords: PASSWORDS }),
      ).rejects.toThrow(/already exists/);

      // Removing it leaves exactly what was there before, in every table.
      const purged = await purgeDemo(db);
      expect(purged.found).toBe(true);
      expect(purged.files.length).toBeGreaterThan(0);
      const left = (
        await db.query(
          `SELECT id, action, entity, "regionId" FROM "AuditEntry"`,
        )
      ).rows.filter((r) => !auditBefore.has(r.id));
      expect(left, "audit lines the removal missed").toEqual([]);
      // The sign-in attempts are the test's own, not the demonstration's.
      const { LoginAttempt: _after, ...afterCounts } = await counts(db);
      const { LoginAttempt: _was, ...beforeCounts } = before;
      expect(afterCounts).toEqual(beforeCounts);
      expect(
        (
          await db.query(`SELECT 1 FROM "Region" WHERE code = $1`, [
            DEMO_REGION_CODE,
          ])
        ).rowCount,
      ).toBe(0);
      expect((await purgeDemo(db)).found).toBe(false);
    } finally {
      await db.end();
    }
  }, 180_000);
});
