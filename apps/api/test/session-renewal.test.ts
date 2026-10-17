import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { owner, resetDatabase, startApi, type Api } from "./helpers";
import { buildWorld, type World } from "./world";

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

describe("sessions", () => {
  it("slide forward when used: 90 days for the team, 7 for the admin", async () => {
    const db = await owner();
    try {
      await db.query(
        `UPDATE "Session" SET "expiresAt" = now() + interval '2 days'`,
      );
      expect((await w.n.get("/v1/me")).status).toBe(200);
      expect((await w.a.get("/v1/me")).status).toBe(200);
      const rows = await db.query(
        `SELECT u.role, EXTRACT(EPOCH FROM (s."expiresAt" - now()))/86400 AS days
         FROM "Session" s JOIN "User" u ON u.id = s."userId"`,
      );
      // Only the two sessions that were used moved; the others kept their two days.
      const days = rows.rows.map((r) => [r.role, Number(r.days)] as const);
      expect(
        days.some(([role, d]) => role === "ADMIN" && d > 6.9 && d < 7.1),
      ).toBe(true);
      expect(
        days.some(([role, d]) => role !== "ADMIN" && d > 89.9 && d < 90.1),
      ).toBe(true);
    } finally {
      await db.end();
    }
  });
});
