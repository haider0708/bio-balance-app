import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
import { approvedPdv, buildWorld, stockPlace, type World } from "./world";
import { Database } from "../src/core/database";
import { addDays, tunisDay } from "../src/core/dates";
import { reviewPasswordHashes, wipeNetwork } from "../src/demo/fresh-start";
import {
  SANDBOX_BUILD_LOCK,
  approveSandbox,
  keepSandboxSelling,
  restoreDemoAccount,
  sandboxServices,
  type RestorePayload,
} from "../src/demo/sandbox";
import { demoServices, seedDemo } from "../src/demo/seed";

/** The test region looks after itself, and the network can be emptied for its real start. */
const PASSWORDS = {
  responsable: "Resp-Demo-2026x",
  vendeur: "Vend-Demo-2026x",
};
let api: Api;
let w: World;
let db: Database;

async function signIn(email: string, password: string) {
  const res = await client(api).post("/v1/auth/login", { email, password });
  return { status: res.status, c: client(api, res.body?.token) };
}
const vendeur = () => signIn("demo-vendeur@galylio.com", PASSWORDS.vendeur);
const responsable = () =>
  signIn("demo-responsable@galylio.com", PASSWORDS.responsable);
const adminUnread = async () =>
  (await w.a.get("/v1/notifications/unread-count")).body.unread as number;

beforeAll(async () => {
  await resetDatabase();
  api = await startApi();
  db = api.app.get(Database);
  w = await buildWorld(api);
  for (const [i, family] of ["Serums", "Hair", "Care", "Care"].entries())
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
      startsOn: addDays(tunisDay(new Date()), -3),
    });
  // A real store with stock and a sale, to be emptied at the end.
  const pdv = await approvedPdv(w, "n", "Para Réelle");
  await stockPlace(w, pdv.id, w.nord, [30, 30, 30]);
  const ownerDb = await owner();
  try {
    await seedDemo(demoServices(api.app), ownerDb, {
      days: 5,
      passwords: PASSWORDS,
    });
    await ownerDb.query(`DELETE FROM "Notification"`);
  } finally {
    await ownerDb.end();
  }
}, 120_000);

afterAll(() => api?.close());

describe("what the test region submits is approved a minute later", () => {
  it("approves its stores and payouts without telling the admin", async () => {
    const r = (await responsable()).c;
    const v = (await vendeur()).c;
    const store = await r.post("/v1/pdvs", {
      name: "Para Démo 2",
      address: "1 rue",
      city: "Tunis",
    });
    expect(store.body.status).toBe("PENDING");
    const payout = await v.post("/v1/payouts", { amountMillimes: 1000 });
    expect(payout.status).toBe(201);

    const services = sandboxServices(db);
    expect(await approveSandbox(services)).toBe(0); // not yet: a minute first
    expect(
      await approveSandbox(services, new Date(Date.now() + 2 * 60_000)),
    ).toBeGreaterThanOrEqual(2);
    expect((await r.get(`/v1/pdvs/${store.body.id}`)).body.status).toBe(
      "ACTIVE",
    );
    const mine = (await v.get("/v1/payouts")).body;
    const paid = (mine.items ?? mine).find((p: any) => p.id === payout.body.id);
    expect(paid.status).toBe("APPROVED");
    expect(await adminUnread()).toBe(0);
  });
});

describe("the test shop keeps selling", () => {
  it("adds the sales of the hours since the last one, with stock, quietly", async () => {
    const ownerDb = await owner();
    const sellerId = (
      await ownerDb.query(`SELECT id FROM "User" WHERE email = $1`, [
        "demo-vendeur@galylio.com",
      ])
    ).rows[0].id;
    // Their last sale was a day ago: a whole business day is missing.
    await ownerDb.query(
      `UPDATE "Sale" SET "occurredAt" = "occurredAt" - interval '1 day' WHERE "sellerId" = $1`,
      [sellerId],
    );
    const before = Number(
      (await ownerDb.query(`SELECT count(*) FROM "Sale"`)).rows[0].count,
    );
    const made = await keepSandboxSelling(sandboxServices(db));
    // A whole business day of planned sales (about nine a day).
    expect(made).toBeGreaterThan(2);
    const { rows } = await ownerDb.query(
      `SELECT count(*)::int AS sales,
              count(*) FILTER (WHERE "occurredAt" > now() AT TIME ZONE 'UTC')::int AS future,
              (SELECT count(*)::int FROM "Stock" WHERE quantity < 0) AS negative,
              (SELECT count(*)::int FROM "Notification" n JOIN "Sale" s ON n."entityId" = s.id
                 WHERE n."pushedAt" IS NULL) AS unpushed
       FROM "Sale"`,
    );
    await ownerDb.end();
    expect(rows[0]).toMatchObject({
      sales: before + made,
      future: 0,
      negative: 0,
      unpushed: 0,
    });
    // Run again at once, or as often as the worker likes: the same hours never sell twice.
    expect(await keepSandboxSelling(sandboxServices(db))).toBe(0);
    expect(await keepSandboxSelling(sandboxServices(db))).toBe(0);
    expect(await adminUnread()).toBe(0);
  });
});

describe("while the test region is being built", () => {
  it("the worker leaves it alone, and comes back once it is done", async () => {
    const v = (await vendeur()).c;
    expect((await v.post("/v1/payouts", { amountMillimes: 1000 })).status).toBe(
      201,
    );
    const later = new Date(Date.now() + 3_600_000);
    const services = sandboxServices(db);
    const ownerDb = await owner();
    try {
      await ownerDb.query(`SELECT pg_advisory_lock($1)`, [SANDBOX_BUILD_LOCK]);
      expect(await approveSandbox(services, later)).toBe(0);
      expect(await keepSandboxSelling(services)).toBe(0);
      await ownerDb.query(`SELECT pg_advisory_unlock($1)`, [
        SANDBOX_BUILD_LOCK,
      ]);
    } finally {
      await ownerDb.end();
    }
    expect(await approveSandbox(services, later)).toBe(1);
  });
});

describe("a demonstration account a reviewer deletes comes back", () => {
  it("is deleted, then restored with its password and history", async () => {
    const v = (await vendeur()).c;
    const sales = (await v.get("/v1/sales")).body;
    const count = (sales.items ?? sales).length;
    expect(
      (await v.post("/v1/me/delete", { password: PASSWORDS.vendeur })).status,
    ).toBe(201);
    expect((await vendeur()).status).toBe(401);

    const ownerDb = await owner();
    const job = (
      await ownerDb.query(
        `SELECT payload FROM "Job" WHERE kind = 'demo-restore'`,
      )
    ).rows[0];
    await ownerDb.end();
    await restoreDemoAccount(db, job.payload as RestorePayload);

    const back = await vendeur();
    expect(back.status).toBe(201);
    const again = (await back.c.get("/v1/sales")).body;
    expect((again.items ?? again).length).toBe(count);
  });
});

describe("the real start", () => {
  it("empties the network but the admins, the catalogue and the rates, and rebuilds the test region", async () => {
    const ownerDb = await owner();
    try {
      const products = Number(
        (await ownerDb.query(`SELECT count(*) FROM "Product"`)).rows[0].count,
      );
      const hashes = await reviewPasswordHashes(ownerDb);
      expect(hashes).not.toBeNull();
      const wiped = await wipeNetwork(ownerDb);
      expect(wiped.counts.User).toBeGreaterThan(2);
      expect(wiped.files.length).toBeGreaterThan(0);
      await seedDemo(demoServices(api.app), ownerDb, {
        days: 3,
        passwordHashes: hashes!,
      });

      const { rows } = await ownerDb.query(
        `SELECT (SELECT count(*)::int FROM "Product") AS products,
                (SELECT count(*)::int FROM "User" WHERE role = 'ADMIN') AS admins,
                (SELECT count(*)::int FROM "User" WHERE role <> 'ADMIN') AS others,
                (SELECT count(*)::int FROM "Region") AS regions,
                (SELECT count(*)::int FROM "Region" WHERE sandbox) AS sandboxes,
                (SELECT count(*)::int FROM "RewardRule" WHERE note IS DISTINCT FROM 'Historique de démonstration') AS rates`,
      );
      expect(rows[0]).toMatchObject({
        products,
        admins: 1,
        others: 2,
        regions: 1,
        sandboxes: 1,
        rates: 3,
      });
    } finally {
      await ownerDb.end();
    }
    // The admin is still signed in, and sees a network at zero.
    expect((await w.a.get("/v1/me")).status).toBe(200);
    const dashboard = (await w.a.get("/v1/dashboard")).body;
    expect(dashboard.sales.month.units).toBe(0);
    expect((await w.a.get("/v1/regions")).body).toEqual([]);
    // The reviewers sign in with the passwords they were given, and find their data.
    const v = await vendeur();
    expect(v.status).toBe(201);
    const mine = (await v.c.get("/v1/sales")).body;
    expect((mine.items ?? mine).length).toBeGreaterThan(0);
    expect((await responsable()).status).toBe(201);
    // A sale in the test region, for good measure, still reaches nobody real.
    await v.c.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    });
    expect(await adminUnread()).toBe(0);
  });
});
