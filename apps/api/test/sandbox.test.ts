import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  regionId,
  resetDatabase,
  startApi,
  type Account,
  type Api,
} from "./helpers";
import { approvedPdv, buildWorld, stockPlace, type World } from "./world";
import { tunisDay } from "../src/core/dates";

/**
 * The test region (Sud here): the store reviewers' accounts work there normally, the admin does not
 * see it unless they ask to, and nothing done there reaches the admin.
 */
let api: Api;
let w: World;
let sudPdv: { id: string; name: string };
let sudSeller: Account;
let nordSeller: Account;
const show = { "x-biobalance-sandbox": "show" };

async function adminGet(route: string, headers: Record<string, string> = {}) {
  const res = await fetch(`${api.url}${route}`, {
    headers: { Authorization: `Bearer ${w.admin.token}`, ...headers },
  });
  return { status: res.status, body: await res.json() };
}

async function adminUnread() {
  return (await w.a.get("/v1/notifications/unread-count")).body
    .unread as number;
}

beforeAll(async () => {
  await resetDatabase();
  api = await startApi();
  w = await buildWorld(api);
  await w.a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Serums",
    amountMillimes: 500,
    startsOn: tunisDay(new Date()),
  });
  // One real store in Nord and one in Sud, each with stock, a seller and a sale.
  const nordPdv = await approvedPdv(w, "n", "Para Nord");
  sudPdv = await approvedPdv(w, "s", "Para Test");
  await stockPlace(w, nordPdv.id, w.nord, [50, 50, 50]);
  await stockPlace(w, sudPdv.id, w.sud, [50, 50, 50]);
  nordSeller = await createAccount({ role: "VENDEUR", pdvId: nordPdv.id });
  sudSeller = await createAccount({ role: "VENDEUR", pdvId: sudPdv.id });
  for (const [seller, quantity] of [
    [nordSeller, 2],
    [sudSeller, 7],
  ] as const)
    await client(api, seller.token).post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity }],
    });
  // Sud becomes the test region.
  const db = await owner();
  await db.query(`UPDATE "Region" SET sandbox = true WHERE code = 'SUD'`);
  await db.query(`DELETE FROM "Notification"`);
  await db.end();
});

afterAll(async () => {
  const db = await owner();
  await db.query(`UPDATE "Region" SET sandbox = false`);
  await db.end();
  await api?.close();
});

describe("the admin does not see the test region", () => {
  it("is absent from regions, stores, people and their pages", async () => {
    const regions = (await w.a.get("/v1/regions")).body;
    const names = (regions.items ?? regions).map((r: any) => r.name);
    expect(names).toContain("Nord");
    expect(names).not.toContain("Sud");

    const pdvs = (await w.a.get("/v1/pdvs")).body;
    expect((pdvs.items ?? pdvs).map((p: any) => p.name)).toEqual(["Para Nord"]);
    expect((await w.a.get(`/v1/pdvs/${sudPdv.id}`)).status).toBe(404);

    const users = (await w.a.get("/v1/users")).body;
    const emails = (users.items ?? users).map((u: any) => u.email);
    expect(emails).toContain(nordSeller.email);
    expect(emails).not.toContain(sudSeller.email);
    expect(emails).not.toContain(w.sud.email);
  });

  it("is left out of the totals, analytics and approvals", async () => {
    const dashboard = (await w.a.get("/v1/dashboard")).body;
    expect(dashboard.sales.today.units).toBe(2);
    const today = tunisDay(new Date());
    const overview = (
      await w.a.get(`/v1/analytics/overview?from=${today}&to=${today}`)
    ).body;
    expect(JSON.stringify(overview)).not.toContain("Para Test");
    const sales = (await w.a.get("/v1/sales")).body;
    expect((sales.items ?? sales).length).toBe(1);
  });

  it("shows again when the admin asks for it", async () => {
    const regions = (await adminGet("/v1/regions", show)).body;
    expect((regions.items ?? regions).map((r: any) => r.name)).toContain("Sud");
    expect((await adminGet(`/v1/pdvs/${sudPdv.id}`, show)).status).toBe(200);
    const dashboard = (await adminGet("/v1/dashboard", show)).body;
    expect(dashboard.sales.today.units).toBe(9);
  });

  it("is never shown to anyone but an admin who asks", async () => {
    const res = await fetch(`${api.url}/v1/pdvs`, {
      headers: { Authorization: `Bearer ${w.nord.token}`, ...show },
    });
    const pdvs = await res.json();
    expect((pdvs.items ?? pdvs).map((p: any) => p.name)).toEqual(["Para Nord"]);
  });
});

describe("the test region works for its own people", () => {
  it("shows the responsable and the seller their own data", async () => {
    const dashboard = (await w.s.get("/v1/dashboard")).body;
    expect(dashboard.sales.today.units).toBe(7);
    const mine = (await client(api, sudSeller.token).get("/v1/sales")).body;
    expect((mine.items ?? mine).length).toBe(1);
  });
});

describe("nothing done in the test region reaches the admin", () => {
  it("sends the admin no notification", async () => {
    expect(await adminUnread()).toBe(0);
    const s = client(api, sudSeller.token);
    expect((await s.post("/v1/payouts", { amountMillimes: 1000 })).status).toBe(
      201,
    );
    await w.s.post("/v1/pdvs", {
      name: "Para Test 2",
      address: "1 rue",
      city: "Sfax",
    });
    await w.s.post(`/v1/pdvs/${sudPdv.id}/members`, {
      name: "Nouveau",
      email: "nouveau@example.test",
    });
    expect(await adminUnread()).toBe(0);
    // The same actions in a real region do reach the admin.
    await w.n.post("/v1/pdvs", {
      name: "Para Nord 2",
      address: "1 rue",
      city: "Bizerte",
    });
    expect(await adminUnread()).toBe(1);
  });

  it("keeps the admin's announcements to everyone away from it", async () => {
    const sent = await w.a.post("/v1/messages", {
      title: "Prices",
      body: "New prices next week.",
      audience: { all: true },
    });
    expect(sent.status).toBe(201);
    const got = async (account: Account) =>
      (
        await client(api, account.token).get("/v1/notifications")
      ).body.items.some((n: any) => n.title === "Prices");
    expect(await got(nordSeller)).toBe(true);
    expect(await got(sudSeller)).toBe(false);
  });

  it("does not let a demonstration account change its password or get a reset code", async () => {
    const changed = await client(api, sudSeller.token).post("/v1/me/password", {
      current: "x",
      next: "a-new-password-123",
    });
    expect(changed.status).toBe(403);
    expect(changed.body.code).toBe("DEMO_ACCOUNT");
    await client(api).post("/v1/auth/forgot-password", {
      email: sudSeller.email,
    });
    const db = await owner();
    const { rows } = await db.query(
      `SELECT count(*)::int AS n FROM "Job" j WHERE j.payload->>'userId' = $1`,
      [sudSeller.id],
    );
    await db.end();
    expect(rows[0].n).toBe(0);
  });
});

describe("the test region is unique", () => {
  it("refuses a second one", async () => {
    const db = await owner();
    await expect(
      db.query(`UPDATE "Region" SET sandbox = true WHERE code = 'NORD'`),
    ).rejects.toThrow();
    await db.end();
    expect(await regionId("NORD")).toBeTruthy();
  });
});
