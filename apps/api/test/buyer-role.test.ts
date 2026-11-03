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
import type { Actor } from "../src/core/actor";

let api: Api;
let w: World;
let db: Database;
let lac: { id: string };
let marsa: { id: string };
let sud: { id: string };
let buyer: Account;
let b: ReturnType<typeof client>;

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
  sud = await approvedPdv(w, "s", "Para Sud");
  await stockPlace(w, lac.id, w.nord, [3, 10, 20]);
  await stockPlace(w, marsa.id, w.nord, [20, 20, 20]);
  buyer = await createAccount({
    role: "ACHETEUR",
    pdvId: lac.id,
    name: "Aya Acheteuse",
  });
  b = client(api, buyer.token);
});

const lines = (...q: number[]) =>
  q
    .map((quantity, i) => ({ productId: w.products[i]!.id, quantity }))
    .filter((l) => l.quantity > 0);

async function inbox(account: Account) {
  const ownerDb = await owner();
  try {
    return (
      await ownerDb.query<{ key: string }>(
        `SELECT key FROM "Notification" WHERE "userId" = $1 ORDER BY "createdAt"`,
        [account.id],
      )
    ).rows;
  } finally {
    await ownerDb.end();
  }
}

/** Put some reward in a seller's wallet, as the database would after a sale. */
async function credit(userId: string, millimes: number) {
  const ownerDb = await owner();
  try {
    await ownerDb.query(
      `INSERT INTO "WalletEntry"(id,"userId",kind,"amountMillimes") VALUES (gen_random_uuid(),$1,'CORRECTION',$2)`,
      [userId, millimes],
    );
  } finally {
    await ownerDb.end();
  }
}

describe("creating a buyer", () => {
  it("a responsable adds a buyer to a para of the region; the admin approves", async () => {
    const added = await w.n.post(`/v1/pdvs/${lac.id}/members`, {
      name: "Ines Achats",
      email: "ines@example.test",
      phone: "22 123 456",
      duties: { sells: false, buys: true },
    });
    expect(added.status).toBe(201);
    expect(added.body).toMatchObject({
      role: "ACHETEUR",
      status: "PENDING",
      pdvId: lac.id,
      canOrder: false,
    });
    // The admin sees it among the members waiting.
    const waiting = await w.a.get("/v1/approvals?type=MEMBER");
    expect(JSON.stringify(waiting.body)).toContain("Ines Achats");
    const approved = await w.a.post(`/v1/users/${added.body.id}/approve`, {});
    expect(approved.status).toBe(201);
    expect(approved.body.status).toBe("ACTIVE");
  });

  it("adds someone who sells and buys, or a plain seller by default", async () => {
    const both = await w.n.post(`/v1/pdvs/${lac.id}/members`, {
      name: "Both Person",
      email: "both@example.test",
      phone: "22 123 457",
      duties: { sells: true, buys: true },
    });
    expect(both.body).toMatchObject({ role: "VENDEUR", canOrder: true });
    const plain = await w.n.post(`/v1/pdvs/${lac.id}/members`, {
      name: "Plain Person",
      email: "plain@example.test",
      phone: "22 123 458",
    });
    expect(plain.body).toMatchObject({ role: "VENDEUR", canOrder: false });
    // Someone who does neither is refused.
    expect(
      (
        await w.n.post(`/v1/pdvs/${lac.id}/members`, {
          name: "Nobody Here",
          email: "nobody@example.test",
          phone: "22 123 459",
          duties: { sells: false, buys: false },
        })
      ).status,
    ).toBe(400);
  });

  it("only for a para of the responsable's own region; the admin can create one anywhere", async () => {
    expect(
      (
        await w.n.post(`/v1/pdvs/${sud.id}/members`, {
          name: "Far Away",
          email: "far@example.test",
          phone: "22 123 460",
          duties: { sells: false, buys: true },
        })
      ).status,
    ).toBe(404);
    const made = await w.a.post("/v1/users", {
      role: "ACHETEUR",
      pdvId: sud.id,
      name: "Sud Acheteur",
      email: "sudbuyer@example.test",
      phone: "22 123 461",
    });
    expect(made.body).toMatchObject({
      role: "ACHETEUR",
      status: "ACTIVE",
      pdvId: sud.id,
    });
  });

  it("the app knows who orders: a buyer always, a seller when allowed", async () => {
    expect((await b.get("/v1/me")).body).toMatchObject({
      role: "ACHETEUR",
      canOrder: true,
      pdv: { id: lac.id },
    });
    const seller = await teamMember(w, lac.id, "Sam Seller");
    expect((await client(api, seller.token).get("/v1/me")).body.canOrder).toBe(
      false,
    );
    const both = await createAccount({
      role: "VENDEUR",
      pdvId: lac.id,
      canOrder: true,
    });
    expect((await client(api, both.token).get("/v1/me")).body.canOrder).toBe(
      true,
    );
  });
});

describe("what a buyer sees", () => {
  it("the stock of its own para, and no other", async () => {
    const own = await b.get(`/v1/stock/locations/${lac.id}`);
    expect(own.status).toBe(200);
    expect(own.body.items.length).toBeGreaterThan(0);
    expect((await b.get(`/v1/stock/locations/${marsa.id}`)).status).toBe(404);
  });

  it("only the orders of its own para", async () => {
    const mine = (
      await w.n.post("/v1/restocks", { destId: lac.id, lines: lines(5) })
    ).body;
    const other = (
      await w.n.post("/v1/restocks", { destId: marsa.id, lines: lines(5) })
    ).body;
    const seen = (await b.get("/v1/restocks")).body.map((o: any) => o.id);
    expect(seen).toContain(mine.id);
    expect(seen).not.toContain(other.id);
    expect((await b.get(`/v1/restocks/${other.id}`)).status).toBe(404);
  });

  it("nothing of money, sales, people, approvals, transfers or the network", async () => {
    for (const route of [
      "/v1/wallet",
      "/v1/orders/overview",
      "/v1/approvals",
      "/v1/users",
      "/v1/transfers",
      "/v1/returns",
      "/v1/rewards",
    ])
      expect([401, 403, 404]).toContain((await b.get(route)).status);
    expect(
      (
        await b.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: w.products[0]!.id, quantity: 1 }],
        })
      ).status,
    ).toBe(403);
  });

  it("the database itself shows it no wallet, payout or sale, whatever the code asks", async () => {
    const seller = await teamMember(w, lac.id, "Sam Seller");
    await credit(seller.id, 5000);
    const actor = {
      id: buyer.id,
      name: "Aya",
      email: buyer.email,
      role: "ACHETEUR",
      regionId: null,
      pdvId: lac.id,
      locale: "fr",
    } as Actor;
    const admin = { ...actor, id: w.admin.id, role: "ADMIN" } as Actor;
    expect(await db.run(admin, (tx) => tx.walletEntry.count())).toBe(1);
    expect(await db.run(actor, (tx) => tx.walletEntry.count())).toBe(0);
    expect(await db.run(actor, (tx) => tx.payoutRequest.count())).toBe(0);
    expect(await db.run(actor, (tx) => tx.sale.count())).toBe(0);
    // Its para only: another para's stock and orders are not even rows to it.
    const places = await db.run(actor, (tx) => tx.stock.findMany());
    expect(new Set(places.map((s) => s.locationId))).toEqual(new Set([lac.id]));
  });
});

describe("placing an order", () => {
  it("for its own para: the responsable, the order manager and the admin are told", async () => {
    const manager = await createAccount({ role: "ORDERS", name: "Omar" });
    const made = await b.post("/v1/restocks", {
      destId: lac.id,
      lines: lines(6, 4),
      note: "Running low",
    });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      status: "REQUESTED",
      requestedBy: { name: "Aya Acheteuse" },
    });
    expect(
      (await inbox(w.nord)).some((n) => n.key === "restock.requested"),
    ).toBe(true);
    expect(
      (await inbox(manager)).some((n) => n.key === "restock.requested"),
    ).toBe(true);
    expect(
      (await inbox(w.admin)).some((n) => n.key === "restock.requested"),
    ).toBe(true);
  });

  it("never for another para or a grossiste (they are not even visible to it)", async () => {
    for (const destId of [marsa.id, sud.id, w.depotId])
      expect(
        (await b.post("/v1/restocks", { destId, lines: lines(2) })).status,
      ).toBe(404);
  });

  it("a plain seller cannot; a seller allowed to order can", async () => {
    const plain = client(api, (await teamMember(w, lac.id, "Plain")).token);
    expect(
      (await plain.post("/v1/restocks", { destId: lac.id, lines: lines(2) }))
        .status,
    ).toBe(403);
    const allowed = client(
      api,
      (await createAccount({ role: "VENDEUR", pdvId: lac.id, canOrder: true }))
        .token,
    );
    expect(
      (await allowed.post("/v1/restocks", { destId: lac.id, lines: lines(2) }))
        .status,
    ).toBe(201);
    // And the plain seller sees no order of the para.
    expect((await plain.get("/v1/restocks")).body).toEqual([]);
  });

  it("cannot choose the grossiste", async () => {
    const res = await b.post("/v1/restocks", {
      destId: lac.id,
      lines: lines(2),
      supplierId: w.depotId,
    });
    expect(res.status).toBe(403);
  });

  it("cancels its own order while it waits; the responsable can cancel it too", async () => {
    const first = (
      await b.post("/v1/restocks", { destId: lac.id, lines: lines(2) })
    ).body;
    expect(
      (await b.post(`/v1/restocks/${first.id}/cancel`, { note: "Mistake" }))
        .body.status,
    ).toBe("CANCELLED");
    const second = (
      await b.post("/v1/restocks", { destId: lac.id, lines: lines(3) })
    ).body;
    const cancelled = await w.n.post(`/v1/restocks/${second.id}/cancel`, {
      note: "Not now",
    });
    expect(cancelled.status).toBe(201);
    expect(cancelled.body.status).toBe("CANCELLED");
    // Another region's responsable cannot.
    const third = (
      await b.post("/v1/restocks", { destId: lac.id, lines: lines(1) })
    ).body;
    expect(
      (await w.s.post(`/v1/restocks/${third.id}/cancel`, { note: "No way" }))
        .status,
    ).toBe(404);
  });
});

describe("receiving", () => {
  async function onTheRoad() {
    const order = (
      await b.post("/v1/restocks", { destId: lac.id, lines: lines(6, 4) })
    ).body;
    const sent = await w.a.post(`/v1/restocks/${order.id}/send-direct`, {});
    expect(sent.status).toBe(201);
    return order as { id: string };
  }

  it("the buyer confirms the delivery with its paper; only the admin's approval moves the stock", async () => {
    const order = await onTheRoad();
    const before = await levels(w, lac.id);
    const received = await b.post(`/v1/restocks/${order.id}/receipt`, {
      photoIds: [await photo(w, buyer)],
      note: "Box damaged",
    });
    expect(received.status).toBe(201);
    expect(received.body.status).toBe("RECEIVED");
    expect(await levels(w, lac.id)).toEqual(before);
    const done = await w.a.post(`/v1/restocks/${order.id}/approve`, {
      lines: lines(6, 4),
    });
    expect(done.body.status).toBe("COMPLETED");
    const after = await levels(w, lac.id);
    expect(after["Serum Vitamin C"]).toBe(before["Serum Vitamin C"]! + 6);
  });

  it("another para's buyer cannot", async () => {
    const order = await onTheRoad();
    const foreign = await createAccount({
      role: "ACHETEUR",
      pdvId: marsa.id,
    });
    const f = client(api, foreign.token);
    const res = await f.post(`/v1/restocks/${order.id}/receipt`, {
      photoIds: [await photo(w, foreign)],
    });
    expect([403, 404]).toContain(res.status);
  });

  it("when the responsable named someone else, the buyer steps aside", async () => {
    const order = await onTheRoad();
    const seller = await teamMember(w, lac.id, "Sam Seller");
    expect(
      (
        await w.n.put(`/v1/restocks/${order.id}/receiver`, {
          userId: seller.id,
        })
      ).status,
    ).toBe(200);
    const res = await b.post(`/v1/restocks/${order.id}/receipt`, {
      photoIds: [await photo(w, buyer)],
    });
    // The order is no longer visible through the buyer's own-para rule only when named: it still is, but not its to receive.
    expect(res.status).toBe(403);
  });

  it("the responsable can name a buyer as the receiver", async () => {
    const order = await onTheRoad();
    const named = await w.n.put(`/v1/restocks/${order.id}/receiver`, {
      userId: buyer.id,
    });
    expect(named.status).toBe(200);
    expect(named.body.receiver).toMatchObject({ name: "Aya Acheteuse" });
  });

  it("the buyer reads the papers the order manager attached", async () => {
    const manager = await createAccount({ role: "ORDERS", name: "Omar" });
    const order = await onTheRoad();
    const paper = await photo(w, manager);
    expect(
      (
        await client(api, manager.token).post(
          `/v1/restocks/${order.id}/documents`,
          { photoIds: [paper] },
        )
      ).status,
    ).toBe(201);
    expect((await b.get(`/v1/media/${paper}/info`)).status).toBe(200);
    // A paper of another para's order stays closed to it.
    const foreign = await photo(w, w.sud);
    expect((await b.get(`/v1/media/${foreign}/info`)).status).toBe(404);
  });
});

describe("changing what someone does", () => {
  it("a seller becomes a buyer too, and back", async () => {
    const seller = await teamMember(w, lac.id, "Sam Seller");
    const both = await w.n.post(`/v1/users/${seller.id}/duties`, {
      sells: true,
      buys: true,
    });
    expect(both.status).toBe(201);
    expect(both.body).toMatchObject({ role: "VENDEUR", canOrder: true });
    expect(
      (
        await client(api, seller.token).post("/v1/restocks", {
          destId: lac.id,
          lines: lines(1),
        })
      ).status,
    ).toBe(201);
    const back = await w.n.post(`/v1/users/${seller.id}/duties`, {
      sells: true,
      buys: false,
    });
    expect(back.body).toMatchObject({ role: "VENDEUR", canOrder: false });
    expect(
      (
        await client(api, seller.token).post("/v1/restocks", {
          destId: lac.id,
          lines: lines(1),
        })
      ).status,
    ).toBe(403);
  });

  it("a buyer starts to sell: it becomes a seller who also orders", async () => {
    const res = await w.n.post(`/v1/users/${buyer.id}/duties`, {
      sells: true,
      buys: true,
    });
    expect(res.body).toMatchObject({ role: "VENDEUR", canOrder: true });
    // The same session now reaches the wallet, and still orders.
    expect((await b.get("/v1/wallet")).status).toBe(200);
    expect(
      (await b.post("/v1/restocks", { destId: lac.id, lines: lines(1) }))
        .status,
    ).toBe(201);
  });

  it("a seller who stops selling must have nothing left in the wallet", async () => {
    const seller = await teamMember(w, lac.id, "Sam Seller");
    await credit(seller.id, 3000);
    const refused = await w.n.post(`/v1/users/${seller.id}/duties`, {
      sells: false,
      buys: true,
    });
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("WALLET_NOT_EMPTY");
    await credit(seller.id, -3000);
    const ok = await w.n.post(`/v1/users/${seller.id}/duties`, {
      sells: false,
      buys: true,
    });
    expect(ok.body).toMatchObject({ role: "ACHETEUR", canOrder: false });
    // No longer a seller: no wallet, no sale.
    const c = client(api, seller.token);
    expect((await c.get("/v1/wallet")).status).toBe(403);
    expect(
      (
        await c.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: w.products[0]!.id, quantity: 1 }],
        })
      ).status,
    ).toBe(403);
    expect(
      (await c.post("/v1/restocks", { destId: lac.id, lines: lines(1) }))
        .status,
    ).toBe(201);
  });

  it("the person is told, and it is written down; a person must do something", async () => {
    const seller = await teamMember(w, lac.id, "Sam Seller");
    await w.n.post(`/v1/users/${seller.id}/duties`, {
      sells: true,
      buys: true,
    });
    expect((await inbox(seller)).some((n) => n.key === "duties.changed")).toBe(
      true,
    );
    expect(
      (
        await w.n.post(`/v1/users/${seller.id}/duties`, {
          sells: false,
          buys: false,
        })
      ).status,
    ).toBe(400);
  });

  it("only the responsable of the region or the admin; never a responsable, an admin or another region", async () => {
    const seller = await teamMember(w, lac.id, "Sam Seller");
    expect(
      (
        await w.s.post(`/v1/users/${seller.id}/duties`, {
          sells: true,
          buys: true,
        })
      ).status,
    ).toBe(404);
    expect(
      (
        await client(api, seller.token).post(`/v1/users/${seller.id}/duties`, {
          sells: true,
          buys: true,
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await w.a.post(`/v1/users/${w.nord.id}/duties`, {
          sells: true,
          buys: true,
        })
      ).status,
    ).toBe(404);
    expect(
      (
        await w.a.post(`/v1/users/${seller.id}/duties`, {
          sells: true,
          buys: true,
        })
      ).status,
    ).toBe(201);
  });

  it("the responsable lists the buyers of the region with the sellers", async () => {
    const people = (await w.n.get("/v1/users")).body as {
      id: string;
      role: string;
    }[];
    expect(people.find((p) => p.id === buyer.id)?.role).toBe("ACHETEUR");
  });
});
