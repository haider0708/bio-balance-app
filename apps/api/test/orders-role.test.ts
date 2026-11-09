import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Account,
  type Api,
} from "./helpers";
import {
  approvedPdv,
  buildWorld,
  levels,
  photo,
  stockPlace,
  teamMember,
  type World,
} from "./world";
import { Database } from "../src/core/database";
import { tunisDay } from "../src/core/dates";
import type { Actor } from "../src/core/actor";

let api: Api;
let w: World;
let db: Database;
let lac: { id: string };
let marsa: { id: string };
let sudPdv: { id: string };
let manager: Account;
let m: ReturnType<typeof client>;
let seller: Account;

beforeAll(async () => {
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api?.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  lac = await approvedPdv(w, "n", "Para Lac");
  marsa = await approvedPdv(w, "n", "Para Marsa");
  sudPdv = await approvedPdv(w, "s", "Para Sud");
  // Lac: one product low, one that sold out, one fine. Marsa and Sud are well stocked.
  await stockPlace(w, lac.id, w.nord, [3, 10, 20]);
  await stockPlace(w, marsa.id, w.nord, [20, 20, 20]);
  await stockPlace(w, sudPdv.id, w.sud, [20, 20, 20]);
  // The grossiste holds plenty.
  await stockPlace(w, w.depotId, w.admin, [100, 100, 100]);
  seller = await teamMember(w, lac.id, "Lina Lac");
  // The whole stock of Niacinamide is sold: the para is out of it.
  const sold = await client(api, seller.token).post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[1]!.id, quantity: 10 }],
  });
  if (sold.status !== 201) throw new Error(JSON.stringify(sold.body));
  manager = await createAccount({ role: "ORDERS", name: "Omar Orders" });
  m = client(api, manager.token);
});

const lines = (...q: number[]) =>
  q
    .map((quantity, i) => ({ productId: w.products[i]!.id, quantity }))
    .filter((l) => l.quantity > 0);

async function inbox(account: Account) {
  const ownerDb = await owner();
  try {
    return (
      await ownerDb.query<{ key: string; params: any }>(
        `SELECT key, params FROM "Notification" WHERE "userId" = $1 ORDER BY "createdAt"`,
        [account.id],
      )
    ).rows;
  } finally {
    await ownerDb.end();
  }
}

const request = async (pdvId = lac.id, q = [6, 4]) =>
  (await w.n.post("/v1/restocks", { destId: pdvId, lines: lines(...q) })).body;

describe("the account", () => {
  it("the admin creates it: no region, no para, active at once", async () => {
    const made = await w.a.post("/v1/users", {
      role: "ORDERS",
      name: "Olfa Commandes",
      email: "olfa@example.test",
      phone: "22 123 456",
    });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      role: "ORDERS",
      status: "ACTIVE",
      regionId: null,
      pdvId: null,
    });
    // Only the admin creates accounts; a responsable cannot make one.
    expect(
      (
        await w.n.post("/v1/users", {
          role: "ORDERS",
          name: "x",
          email: "x@example.test",
        })
      ).status,
    ).toBe(403);
  });

  it("is known by the app as itself", async () => {
    const me = (await m.get("/v1/me")).body;
    expect(me).toMatchObject({ role: "ORDERS", name: "Omar Orders" });
    expect(me.region ?? null).toBeNull();
  });
});

describe("seeing the network", () => {
  it("shows every para with what is low and out, the worst first", async () => {
    const paras = (await m.get("/v1/orders/paras")).body;
    expect(paras.map((p: any) => p.name)).toEqual([
      "Para Lac",
      "Para Marsa",
      "Para Sud",
    ]);
    expect(paras[0]).toMatchObject({
      name: "Para Lac",
      region: { name: "Nord" },
      stock: { products: 3, low: 1, out: 1, units: 23 },
      openOrders: 0,
    });
    expect(
      (await m.get("/v1/orders/paras?low=true")).body.map((p: any) => p.name),
    ).toEqual(["Para Lac"]);
    expect((await m.get("/v1/orders/paras?q=marsa")).body).toHaveLength(1);
    // Nothing about money is in what it sees.
    expect(JSON.stringify(paras)).not.toMatch(/reward|wallet|payout/i);
  });

  it("opens one para: stock with how fast each product sells, what is on order, and who to call", async () => {
    const order = await request(lac.id);
    const para = (await m.get(`/v1/orders/paras/${lac.id}`)).body;
    expect(para.name).toBe("Para Lac");
    expect(
      para.stock.lines.find((l: any) => l.name === "Serum Vitamin C"),
    ).toMatchObject({ quantity: 3, level: "LOW" });
    expect(
      para.stock.lines.find((l: any) => l.name === "Serum Niacinamide"),
    ).toMatchObject({ quantity: 0, level: "OUT" });
    expect(para.orders).toEqual([
      expect.objectContaining({
        id: order.id,
        status: "REQUESTED",
        units: 10,
        proposed: false,
      }),
    ]);
    const names = para.contacts.map((c: any) => c.name);
    expect(names).toContain("Nora Nord");
    expect(names).toContain("Lina Lac");
    expect((await m.get(`/v1/orders/paras/${randomUUID()}`)).status).toBe(404);
  });

  it("measures how fast a product sells and how many days it would last", async () => {
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Hair",
      amountMillimes: 500,
      startsOn: tunisDay(new Date()),
    });
    const sold = await client(api, seller.token).post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[2]!.id, quantity: 7 }],
    });
    expect(sold.status).toBe(201);
    const line = (
      await m.get(`/v1/orders/paras/${lac.id}`)
    ).body.stock.lines.find((l: any) => l.name === "Shampoo Argan");
    // 20 - 7 = 13 left, 7 sold this week: one a day, so 13 days.
    expect(line).toMatchObject({ quantity: 13, sold7Days: 7, coverDays: 13 });
    expect(
      (await m.get("/v1/orders/paras")).body.find(
        (p: any) => p.name === "Para Lac",
      ).sold7Days,
    ).toBe(17);
  });

  it("gives the home: what waits and which paras need attention", async () => {
    await request(lac.id);
    await request(marsa.id, [1]);
    const o = (await m.get("/v1/orders/overview")).body;
    expect(o.orders).toMatchObject({
      requested: 2,
      proposed: 0,
      toShip: 0,
      onTheRoad: 0,
      delivered: 0,
      toApprove: 0,
    });
    expect(o.paras).toMatchObject({ total: 3, low: 1, out: 1 });
    expect(o.attention.map((p: any) => p.name)).toEqual(["Para Lac"]);
  });

  it("is only for the order manager and the admin", async () => {
    for (const c of [w.n, client(api, seller.token)])
      for (const route of [
        "/v1/orders/overview",
        "/v1/orders/paras",
        `/v1/orders/paras/${lac.id}`,
      ])
        expect((await c.get(route)).status).toBe(403);
    expect((await w.a.get("/v1/orders/overview")).status).toBe(200);
  });

  it("reads the paras, groups and grossistes, to pick a destination", async () => {
    const pdvs = await m.get("/v1/pdvs");
    expect(pdvs.status).toBe(200);
    expect(pdvs.body.map((p: { id: string }) => p.id)).toContain(lac.id);
    expect((await m.get(`/v1/pdvs/${lac.id}`)).status).toBe(200);
    expect((await m.get("/v1/groups")).status).toBe(200);
    const depots = await m.get("/v1/depots");
    expect(depots.status).toBe(200);
    expect(depots.body.map((d: { id: string }) => d.id)).toContain(w.depotId);
  });

  it("sees transfers and returns, and can change none", async () => {
    const group = (await w.n.post("/v1/groups", { name: "Groupe" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    for (const p of [lac, marsa])
      await w.n.patch(`/v1/pdvs/${p.id}`, { groupId: group.id });
    const ret = (
      await w.n.post("/v1/returns", { pdvId: marsa.id, lines: lines(2) })
    ).body;
    expect((await m.get("/v1/returns")).body.map((r: any) => r.id)).toEqual([
      ret.id,
    ]);
    const seen = await m.get(`/v1/returns/${ret.id}`);
    expect(seen.status).toBe(200);
    expect(seen.body).toMatchObject({
      canEdit: false,
      canCancel: false,
      canDecide: false,
    });
    expect(
      (await m.post("/v1/returns", { pdvId: marsa.id, lines: lines(1) }))
        .status,
    ).toBe(403);
    expect((await m.post(`/v1/returns/${ret.id}/approve`, {})).status).toBe(
      403,
    );
    expect((await m.get("/v1/transfers")).status).toBe(200);
    expect(
      (
        await m.post("/v1/transfers", {
          fromPdvId: lac.id,
          toPdvId: marsa.id,
          lines: lines(1),
        })
      ).status,
    ).toBe(403);
  });
});

describe("asking a para", () => {
  it("tells its team and its responsable, once in a while", async () => {
    const sent = await m.post(`/v1/orders/paras/${lac.id}/ask`, {
      message: "Need serums?",
    });
    expect(sent.status).toBe(201);
    for (const who of [seller, w.nord]) {
      const n = (await inbox(who)).find((x) => x.key === "orders.asks");
      expect(n!.params).toMatchObject({ by: "Omar Orders", place: "Para Lac" });
      expect(n!.params.message).toContain("Need serums?");
    }
    // Another para's team hears nothing; asking again at once is refused.
    expect((await inbox(await teamMember(w, marsa.id))).length).toBe(0);
    const again = await m.post(`/v1/orders/paras/${lac.id}/ask`, {});
    expect(again.status).toBe(429);
    expect(again.body.code).toBe("TOO_SOON");
    expect(
      (await m.get(`/v1/orders/paras/${lac.id}`)).body.lastAskedAt,
    ).toBeTruthy();
    // Only the order manager asks.
    expect(
      (await w.n.post(`/v1/orders/paras/${marsa.id}/ask`, {})).status,
    ).toBe(403);
  });
});

describe("what it must never reach", () => {
  it("money, accounts, approvals and stock corrections stay closed", async () => {
    for (const route of [
      "/v1/wallets",
      "/v1/payouts",
      "/v1/reward-rules",
      "/v1/analytics/overview?from=2026-01-01&to=2026-01-02",
      "/v1/sales",
      "/v1/users",
      "/v1/approvals",
      "/v1/audit",
      "/v1/planning/overview?from=2026-01-01&to=2026-01-02",
    ])
      expect((await m.get(route)).status, route).toBe(403);
    expect(
      (
        await m.post("/v1/stock/adjust", {
          locationId: lac.id,
          reason: "because",
          lines: lines(1),
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await m.post("/v1/users", {
          role: "ORDERS",
          name: "x",
          email: "y@example.test",
        })
      ).status,
    ).toBe(403);
  });

  it("the database itself shows it no wallet, payout or sale, whatever the code asks", async () => {
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Hair",
      amountMillimes: 500,
      startsOn: tunisDay(new Date()),
    });
    await client(api, seller.token).post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[2]!.id, quantity: 1 }],
    });
    const actor = {
      id: manager.id,
      name: "Omar",
      email: manager.email,
      role: "ORDERS",
      regionId: null,
      pdvId: null,
      locale: "fr",
    } as Actor;
    const admin = { ...actor, id: w.admin.id, role: "ADMIN" } as Actor;
    expect(await db.run(admin, (tx) => tx.walletEntry.count())).toBeGreaterThan(
      0,
    );
    expect(await db.run(actor, (tx) => tx.walletEntry.count())).toBe(0);
    expect(await db.run(actor, (tx) => tx.payoutRequest.count())).toBe(0);
    expect(await db.run(actor, (tx) => tx.sale.count())).toBe(0);
    // What it may read, it reads: the paras and their stock.
    expect(await db.run(actor, (tx) => tx.pdv.count())).toBe(3);
    expect(await db.run(actor, (tx) => tx.stock.count())).toBeGreaterThan(0);
  });
});

describe("preparing an order for the admin to approve", () => {
  it("a responsable's request reaches the order manager, who proposes a grossiste with papers; the admin approves in one tap", async () => {
    const order = await request(lac.id, [6, 4]);
    expect(
      (await inbox(manager)).some((n) => n.key === "restock.requested"),
    ).toBe(true);
    // The order manager sees orders of every region and the grossistes' stock for it.
    expect((await m.get("/v1/restocks")).body.map((o: any) => o.id)).toContain(
      order.id,
    );
    const suppliers = (await m.get(`/v1/restocks/${order.id}/suppliers`)).body;
    expect(suppliers[0]).toMatchObject({ name: "Depot Hedi", missing: 0 });

    const paper = await photo(w, manager);
    const proposed = await m.post(`/v1/restocks/${order.id}/propose`, {
      source: "GROSSISTE",
      depotId: w.depotId,
      lines: lines(5, 4),
      note: "Depot is closest",
      photoIds: [paper],
    });
    expect(proposed.status).toBe(201);
    expect(proposed.body.status).toBe("REQUESTED");
    expect(proposed.body.proposal).toMatchObject({
      source: "GROSSISTE",
      supplier: { name: "Depot Hedi" },
      by: { name: "Omar Orders" },
      note: "Depot is closest",
    });
    expect(proposed.body.documentIds).toEqual([paper]);
    expect(
      proposed.body.lines.find((l: any) => l.name === "Serum Vitamin C"),
    ).toMatchObject({ requested: 6, proposed: 5 });

    // The admin finds it in Approvals, marked as a proposal; nothing left yet.
    const item = (await w.a.get("/v1/approvals")).body.items.find(
      (i: any) => i.id === order.id,
    );
    expect(item.meta).toMatchObject({
      proposal: true,
      proposedBy: "Omar Orders",
    });
    expect(
      (await inbox(w.admin)).some((n) => n.key === "restock.proposed"),
    ).toBe(true);
    expect(await levels(w, w.depotId)).toMatchObject({
      "Serum Vitamin C": 100,
    });

    const approved = await w.a.post(
      `/v1/restocks/${order.id}/approve-proposal`,
      {},
    );
    expect(approved.status).toBe(201);
    expect(approved.body).toMatchObject({
      status: "ASSIGNED",
      source: "GROSSISTE",
      supplier: { name: "Depot Hedi" },
    });
    // The quantities are exactly the proposed ones.
    expect(
      approved.body.lines.find((l: any) => l.name === "Serum Vitamin C")
        .requested,
    ).toBe(5);
    expect(
      (await inbox(manager)).some((n) => n.key === "restock.proposal_approved"),
    ).toBe(true);
  });

  it("then ships, adds papers and marks it delivered; the place confirms and the admin approves: only then does the stock arrive", async () => {
    const order = await request(lac.id, [6, 4]);
    await m.post(`/v1/restocks/${order.id}/propose`, {
      source: "GROSSISTE",
      depotId: w.depotId,
    });
    await w.a.post(`/v1/restocks/${order.id}/approve-proposal`, {});

    const shipped = await m.post(`/v1/restocks/${order.id}/ship`, {
      lines: lines(6, 4),
    });
    expect(shipped.status).toBe(201);
    expect(shipped.body.status).toBe("SHIPPED");
    expect(await levels(w, w.depotId)).toMatchObject({
      "Serum Vitamin C": 94,
      "Serum Niacinamide": 96,
    });
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 3 });

    const docs = await m.post(`/v1/restocks/${order.id}/documents`, {
      photoIds: [await photo(w, manager)],
    });
    expect(docs.body.documentIds).toHaveLength(1);
    const delivered = await m.post(`/v1/restocks/${order.id}/delivered`, {
      photoIds: [await photo(w, manager)],
    });
    expect(delivered.body).toMatchObject({
      status: "SHIPPED",
      deliveredBy: { name: "Omar Orders" },
    });
    expect(delivered.body.deliveredAt).toBeTruthy();
    expect(delivered.body.documentIds).toHaveLength(2);
    expect(
      (await inbox(w.nord)).some((n) => n.key === "restock.delivered"),
    ).toBe(true);
    expect(
      (await m.post(`/v1/restocks/${order.id}/delivered`, {})).body.code,
    ).toBe("INVALID_STATE");

    // The place still confirms, and the admin approves.
    const receipt = await w.n.post(`/v1/restocks/${order.id}/receipt`, {
      photoIds: [await photo(w, w.nord)],
    });
    expect(receipt.status).toBe(201);
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 3 });
    const done = await w.a.post(`/v1/restocks/${order.id}/approve`, {
      lines: lines(6, 4),
    });
    expect(done.body.status).toBe("COMPLETED");
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 9,
      "Serum Niacinamide": 4,
    });
  });

  it("files its papers under the order's region: the responsable of the place can open them", async () => {
    const order = await request(lac.id, [6, 4]);
    const paper = await photo(w, manager);
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/documents`, {
          photoIds: [paper],
        })
      ).status,
    ).toBe(201);
    expect((await w.n.get(`/v1/media/${paper}/info`)).status).toBe(200);
    expect((await w.s.get(`/v1/media/${paper}/info`)).status).toBe(404);
  });

  it("can propose a direct shipment from BioBalance, and the admin can refuse a proposal with a reason", async () => {
    const order = await request(lac.id);
    const direct = await m.post(`/v1/restocks/${order.id}/propose`, {
      source: "BIOBALANCE",
    });
    expect(direct.body.proposal).toMatchObject({
      source: "BIOBALANCE",
      supplier: null,
    });
    expect(
      (await w.a.post(`/v1/restocks/${order.id}/reject-proposal`, {})).status,
    ).toBe(400);
    const refused = await w.a.post(`/v1/restocks/${order.id}/reject-proposal`, {
      note: "Use the depot",
    });
    expect(refused.body.proposal).toBeNull();
    expect(refused.body.status).toBe("REQUESTED");
    expect(
      (await inbox(manager)).find((n) => n.key === "restock.proposal_refused")!
        .params.note,
    ).toBe("Use the depot");
    // A new proposal is approved: it goes straight to the place.
    await m.post(`/v1/restocks/${order.id}/propose`, { source: "BIOBALANCE" });
    const sent = await w.a.post(
      `/v1/restocks/${order.id}/approve-proposal`,
      {},
    );
    expect(sent.body).toMatchObject({
      status: "SHIPPED",
      source: "BIOBALANCE",
    });
  });

  it("checks what it proposes: the grossiste, the quantities, the product, the state", async () => {
    const order = await request(lac.id, [6, 4]);
    const base = { source: "GROSSISTE" as const, depotId: w.depotId };
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          source: "GROSSISTE",
        })
      ).body.code,
    ).toBe("DEPOT_REQUIRED");
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          source: "GROSSISTE",
          depotId: randomUUID(),
        })
      ).body.code,
    ).toBe("DEPOT_NOT_FOUND");
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          source: "BIOBALANCE",
          depotId: w.depotId,
        })
      ).body.code,
    ).toBe("INVALID_ACTION");
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          ...base,
          lines: lines(7),
        })
      ).body.code,
    ).toBe("TOO_MANY");
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          ...base,
          lines: [{ productId: w.products[2]!.id, quantity: 1 }],
        })
      ).body.code,
    ).toBe("PRODUCT_NOT_FOUND");
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/propose`, {
          ...base,
          lines: [
            { productId: w.products[0]!.id, quantity: 0 },
            { productId: w.products[1]!.id, quantity: 0 },
          ],
        })
      ).body.code,
    ).toBe("NOTHING_SHIPPED");
    // Only the order manager proposes; the admin has nothing to approve before someone did.
    expect(
      (await w.n.post(`/v1/restocks/${order.id}/propose`, base)).status,
    ).toBe(403);
    expect(
      (await w.a.post(`/v1/restocks/${order.id}/propose`, base)).status,
    ).toBe(403);
    expect(
      (await w.a.post(`/v1/restocks/${order.id}/approve-proposal`, {})).body
        .code,
    ).toBe("NO_PROPOSAL");
    expect(
      (await m.post(`/v1/restocks/${order.id}/ship`, { lines: lines(1) })).body
        .code,
    ).toBe("INVALID_STATE");
    await m.post(`/v1/restocks/${order.id}/propose`, base);
    await w.a.post(`/v1/restocks/${order.id}/approve-proposal`, {});
    // Once assigned, it can no longer be proposed.
    expect(
      (await m.post(`/v1/restocks/${order.id}/propose`, base)).body.code,
    ).toBe("INVALID_STATE");
  });

  it("asks for stock for any para itself, and cancels what it asked while it waits", async () => {
    const made = await m.post("/v1/restocks", {
      destId: sudPdv.id,
      lines: lines(3),
      note: "Low in the south",
    });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      status: "REQUESTED",
      requestedBy: { name: "Omar Orders" },
      destination: { name: "Para Sud" },
    });
    expect(
      (await inbox(w.admin)).some((n) => n.key === "restock.requested"),
    ).toBe(true);
    const cancelled = await m.post(`/v1/restocks/${made.body.id}/cancel`, {
      note: "Not needed",
    });
    expect(cancelled.body.status).toBe("CANCELLED");
    // A responsable's order is not the manager's to cancel.
    const theirs = await request(lac.id);
    expect(
      (await m.post(`/v1/restocks/${theirs.id}/cancel`, { note: "no" })).status,
    ).toBe(403);
    // And it cannot do what only the admin does with a store's order.
    for (const route of [
      "assign",
      "send-direct",
      "approve",
      "amend",
      "reopen",
      "reject-receipt",
    ])
      expect(
        (
          await m.post(`/v1/restocks/${theirs.id}/${route}`, {
            depotId: w.depotId,
          })
        ).status,
        route,
      ).toBe(403);
  });

  it("papers: only the order manager or the admin add them, until the order is closed", async () => {
    const order = await request(lac.id);
    expect(
      (
        await w.n.post(`/v1/restocks/${order.id}/documents`, {
          photoIds: [await photo(w, w.nord)],
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/documents`, {
          photoIds: [await photo(w, w.admin)],
        })
      ).body.code,
    ).toBe("PHOTO_REQUIRED");
    expect(
      (
        await w.a.post(`/v1/restocks/${order.id}/documents`, {
          photoIds: [await photo(w, w.admin)],
        })
      ).status,
    ).toBe(201);
    await w.a.post(`/v1/restocks/${order.id}/cancel`, { note: "closed" });
    expect(
      (
        await m.post(`/v1/restocks/${order.id}/documents`, {
          photoIds: [await photo(w, manager)],
        })
      ).body.code,
    ).toBe("INVALID_STATE");
  });
});
