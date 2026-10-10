// Times the heaviest reads on a large database. Not part of the normal run:
//   TEST_DATABASE_URL=…/biobalance_perf_test TEST_OWNER_DATABASE_URL=…/biobalance_perf_test PERF=1 npx vitest run test/perf.test.ts
// (a database seeded with a year of sales of 300 stores; see docs/runbook.md).
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { client, createAccount, owner, startApi, type Api } from "./helpers";
import { addDays, tunisDay } from "../src/core/dates";

const run = process.env.PERF === "1";
let api: Api;

describe.skipIf(!run)("speed on a large network", () => {
  beforeAll(async () => {
    api = await startApi();
  });
  afterAll(() => api.close());

  it("answers the dashboards and analytics quickly", async () => {
    // Run after run on the same database: the region's previous test responsable steps aside.
    const db = await owner();
    await db.query(
      `UPDATE "User" SET status='SUSPENDED' WHERE role='RESPONSABLE' AND email LIKE 'perf-%'`,
    );
    await db.end();
    const admin = client(api, (await createAccount({ role: "ADMIN" })).token);
    const resp = client(
      api,
      (
        await createAccount({
          role: "RESPONSABLE",
          regionCode: "SUD",
          email: `perf-${Date.now()}@x.test`,
        })
      ).token,
    );
    const today = tunisDay(new Date());
    const month = `from=${addDays(today, -29)}&to=${today}`;
    const year = `from=${addDays(today, -364)}&to=${today}`;
    const timings: Record<string, { ms: number; status: number }> = {};
    async function time(name: string, call: () => Promise<{ status: number }>) {
      await call(); // warm
      const started = performance.now();
      const res = await call();
      timings[name] = {
        ms: Math.round(performance.now() - started),
        status: res.status,
      };
    }
    await time("admin dashboard", () => admin.get("/v1/dashboard"));
    await time("responsable dashboard", () => resp.get("/v1/dashboard"));
    await time("analytics 30 days", () =>
      admin.get(`/v1/analytics/overview?${month}`),
    );
    await time("analytics 1 year", () =>
      admin.get(`/v1/analytics/overview?${year}`),
    );
    await time("analytics region 30 days", () =>
      resp.get(`/v1/analytics/overview?${month}`),
    );
    await time("stores board 30 days", () =>
      admin.get(`/v1/analytics/stores?${month}`),
    );
    await time("sales ledger page", () =>
      admin.get(`/v1/sales?${month}&limit=30`),
    );
    console.table(timings);
    // Every answer comes back; the daily screens in about a second, a whole year compared
    // with the year before in a few.
    for (const [name, t] of Object.entries(timings)) {
      expect(t.status, name).toBe(200);
      expect(t.ms, name).toBeLessThan(name.includes("1 year") ? 5000 : 1500);
    }
  }, 300_000);
});
