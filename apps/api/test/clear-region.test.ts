import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
import { clearRegion } from "../src/demo/clear-region";
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

type Db = Awaited<ReturnType<typeof owner>>;

/** What belongs to a region, counted table by table. */
async function inRegion(db: Db, code: string) {
  const one = async (sql: string) =>
    Number((await db.query(sql, [code])).rows[0].count);
  const region = `(SELECT id FROM "Region" WHERE code = $1)`;
  return {
    users: await one(
      `SELECT count(*) FROM "User" WHERE "regionId" = ${region}`,
    ),
    pdvs: await one(`SELECT count(*) FROM "Pdv" WHERE "regionId" = ${region}`),
    groups: await one(
      `SELECT count(*) FROM "Group" WHERE "regionId" = ${region}`,
    ),
    depots: await one(
      `SELECT count(*) FROM "Depot" WHERE "regionId" = ${region}`,
    ),
    sales: await one(
      `SELECT count(*) FROM "Sale" WHERE "regionId" = ${region}`,
    ),
    saleLines: await one(
      `SELECT count(*) FROM "SaleLine" l JOIN "Sale" s ON s.id = l."saleId" WHERE s."regionId" = ${region}`,
    ),
    stock: await one(
      `SELECT count(*) FROM "Stock" WHERE "regionId" = ${region}`,
    ),
    movements: await one(
      `SELECT count(*) FROM "StockMovement" WHERE "regionId" = ${region}`,
    ),
    declarations: await one(
      `SELECT count(*) FROM "StockDeclaration" WHERE "regionId" = ${region}`,
    ),
    orders: await one(
      `SELECT count(*) FROM "RestockOrder" WHERE "regionId" = ${region}`,
    ),
    audit: await one(
      `SELECT count(*) FROM "AuditEntry" WHERE "regionId" = ${region}`,
    ),
    photos: await one(
      `SELECT count(*) FROM "MediaAsset" WHERE "regionId" = ${region}`,
    ),
    wallets: await one(
      `SELECT count(*) FROM "WalletEntry" e JOIN "User" u ON u.id = e."userId" WHERE u."regionId" = ${region}`,
    ),
  };
}

async function sell(token: string, productId: string, quantity: number) {
  const sale = await client(api, token).post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId, quantity }],
  });
  expect(sale.status).toBe(201);
}

describe("clearing one region", () => {
  it("empties it completely and leaves every other region, the admin and the catalogue as they were", async () => {
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Serums",
      amountMillimes: 500,
      startsOn: "2026-01-01",
    });
    // NORD: a store with stock, a seller with a sale (reward and wallet), a restock request.
    const north = await approvedPdv(w, "n", "Para Nord");
    await stockPlace(w, north.id, w.nord, [20, 20, 20]);
    const anis = await teamMember(w, north.id, "Anis");
    await sell(anis.token, w.products[0]!.id, 2);
    const request = await w.n.post("/v1/restocks", {
      destId: north.id,
      lines: [{ productId: w.products[1]!.id, quantity: 5 }],
    });
    expect(request.status).toBe(201);
    // SUD: the same kind of content, which must survive untouched.
    const south = await approvedPdv(w, "s", "Para Sud");
    await stockPlace(w, south.id, w.sud, [20, 20, 20]);
    const chiraz = await teamMember(w, south.id, "Chiraz");
    await sell(chiraz.token, w.products[0]!.id, 3);

    const db = await owner();
    try {
      const sudBefore = await inRegion(db, "SUD");
      const nordBefore = await inRegion(db, "NORD");
      expect(nordBefore.pdvs).toBe(1);
      expect(nordBefore.sales).toBe(1);
      expect(nordBefore.orders).toBe(1);
      expect(nordBefore.depots).toBe(1);
      expect(nordBefore.wallets).toBeGreaterThan(0);
      const global = async () => ({
        products: Number(
          (await db.query(`SELECT count(*) FROM "Product"`)).rows[0].count,
        ),
        rules: Number(
          (await db.query(`SELECT count(*) FROM "RewardRule"`)).rows[0].count,
        ),
        regions: Number(
          (await db.query(`SELECT count(*) FROM "Region"`)).rows[0].count,
        ),
        admins: Number(
          (await db.query(`SELECT count(*) FROM "User" WHERE role = 'ADMIN'`))
            .rows[0].count,
        ),
      });
      const globalBefore = await global();

      const result = await clearRegion(db, "NORD");
      expect(result.region.code).toBe("NORD");
      expect(result.files.length).toBeGreaterThan(0);

      // NORD is empty, but the region itself remains.
      expect(await inRegion(db, "NORD")).toEqual({
        users: 0,
        pdvs: 0,
        groups: 0,
        depots: 0,
        sales: 0,
        saleLines: 0,
        stock: 0,
        movements: 0,
        declarations: 0,
        orders: 0,
        audit: 0,
        photos: 0,
        wallets: 0,
      });
      expect(
        (await db.query(`SELECT 1 FROM "Region" WHERE code = 'NORD'`)).rowCount,
      ).toBe(1);
      // Nothing else moved.
      expect(await inRegion(db, "SUD")).toEqual(sudBefore);
      expect(await global()).toEqual(globalBefore);
      // No alert is left pointing at something that was removed.
      const dangling = await db.query(
        `SELECT n.id FROM "Notification" n WHERE
           (n."entityType" = 'Pdv' AND n."entityId" NOT IN (SELECT id FROM "Pdv"))
        OR (n."entityType" = 'Sale' AND n."entityId" NOT IN (SELECT id FROM "Sale"))
        OR (n."entityType" = 'RestockOrder' AND n."entityId" NOT IN (SELECT id FROM "RestockOrder"))
        OR (n."entityType" = 'StockDeclaration' AND n."entityId" NOT IN (SELECT id FROM "StockDeclaration"))`,
      );
      expect(dangling.rowCount).toBe(0);
      // The photos of the other region are still on record, and the history guards are back on.
      const sudPhotos = (
        await db.query(
          `SELECT path FROM "MediaAsset" WHERE "regionId" = (SELECT id FROM "Region" WHERE code = 'SUD')`,
        )
      ).rows.map((r) => r.path);
      expect(sudPhotos.length).toBeGreaterThan(0);
      expect(result.files.some((f) => sudPhotos.includes(f))).toBe(false);
      await expect(
        db.query(`UPDATE "StockMovement" SET "createdAt" = now()`),
      ).rejects.toThrow(/append-only/i);
      // Clearing it again is harmless, and the app still works for the region that remains.
      expect((await clearRegion(db, "NORD")).files).toEqual([]);
      expect((await client(api, chiraz.token).get("/v1/me")).status).toBe(200);
    } finally {
      await db.end();
    }
  }, 60_000);

  it("refuses a test region and an unknown one, and changes nothing", async () => {
    const db = await owner();
    try {
      await db.query(
        `UPDATE "Region" SET sandbox = true WHERE code = 'CENTRE'`,
      );
      const before = Number(
        (await db.query(`SELECT count(*) FROM "User"`)).rows[0].count,
      );
      await expect(clearRegion(db, "CENTRE")).rejects.toThrow(/test region/);
      await expect(clearRegion(db, "NOWHERE")).rejects.toThrow(/no region/);
      expect(
        Number((await db.query(`SELECT count(*) FROM "User"`)).rows[0].count),
      ).toBe(before);
    } finally {
      await db.end();
    }
  });
});
