import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
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
  stockPlace,
  teamMember,
  type World,
} from "./world";
import { Database } from "../src/core/database";
import { expireReturns } from "../src/jobs/returns";

let api: Api;
let w: World;
let db: Database;
let lac: { id: string };
let marsa: { id: string };
let sudPdv: { id: string };

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
  await stockPlace(w, lac.id, w.nord, [10, 10, 10]);
  await stockPlace(w, sudPdv.id, w.sud, [4, 4, 4]);
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

const ask = (over: object = {}) =>
  w.n.post("/v1/returns", { pdvId: lac.id, lines: lines(3, 2), ...over });

describe("a responsable asks for a return", () => {
  it("takes nothing out yet, and the admin sees it waiting", async () => {
    const made = await ask({ note: "Expired box" });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      status: "PENDING",
      action: "REMOVE",
      units: 5,
      para: { name: "Para Lac" },
      to: null,
      note: "Expired box",
      createdBy: { name: "Nora Nord" },
      canEdit: true,
      canDecide: false,
    });
    expect(made.body.number).toMatch(/^RT-\d{4}-\d{6}$/);
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 10 });
    const queue = (await w.a.get("/v1/approvals")).body;
    expect(queue.counts.RETURN).toBe(1);
    expect(queue.items.find((i: any) => i.type === "RETURN")).toMatchObject({
      id: made.body.id,
      name: "Para Lac",
      by: "Nora Nord",
      meta: { units: 5, changed: false },
    });
    expect(
      (await inbox(w.admin)).some((n) => n.key === "return.requested"),
    ).toBe(true);
  });

  it("only for a para of their own region, only to take out, never more than the para holds", async () => {
    expect((await ask({ pdvId: sudPdv.id })).body.code).toBe("PARA_NOT_FOUND");
    expect((await ask({ action: "MOVE", toPdvId: marsa.id })).status).toBe(403);
    expect((await ask({ action: "ADD" })).status).toBe(403);
    const short = await ask({ lines: lines(11) });
    expect(short.status).toBe(409);
    expect(short.body.code).toBe("RETURN_STOCK");
    expect(short.body.details.products[0]).toMatchObject({
      available: 10,
      wanted: 11,
    });
    expect((await ask({ lines: [] })).status).toBe(400);
    const dup = lines(1);
    expect((await ask({ lines: [...dup, ...dup] })).body.code).toBe(
      "DUPLICATE_PRODUCT",
    );
  });

  it("is not for team members, who see nothing of returns", async () => {
    const member = await teamMember(w, lac.id);
    const c = client(api, member.token);
    expect(
      (await c.post("/v1/returns", { pdvId: lac.id, lines: lines(1) })).status,
    ).toBe(403);
    expect((await c.get("/v1/returns")).status).toBe(403);
  });

  it("can be changed or cancelled while it waits, and the change is written down", async () => {
    const made = (await ask()).body;
    const changed = await w.n.post(`/v1/returns/${made.id}/edit`, {
      lines: lines(1, 2, 1),
    });
    expect(changed.body).toMatchObject({ units: 4, revision: 1 });
    expect(
      changed.body.lines.find((l: any) => l.name === "Serum Vitamin C"),
    ).toMatchObject({ quantity: 1, requestedQuantity: 3 });
    expect(changed.body.changes[0]).toMatchObject({
      by: { name: "Nora Nord" },
    });
    expect((await inbox(w.admin)).some((n) => n.key === "return.changed")).toBe(
      true,
    );
    // Nothing changed: no new revision.
    expect(
      (await w.n.post(`/v1/returns/${made.id}/edit`, { lines: lines(1, 2, 1) }))
        .body.revision,
    ).toBe(1);
    expect(
      (await w.n.post(`/v1/returns/${made.id}/edit`, { lines: lines(99) })).body
        .code,
    ).toBe("RETURN_STOCK");
    const gone = await w.n.post(`/v1/returns/${made.id}/cancel`);
    expect(gone.body.status).toBe("CANCELLED");
    expect((await w.n.post(`/v1/returns/${made.id}/cancel`)).body.code).toBe(
      "INVALID_STATE",
    );
    expect((await w.a.get("/v1/approvals")).body.counts.RETURN).toBe(0);
  });
});

describe("the admin decides a return", () => {
  it("approving takes the quantities out of the para, with a history line, and tells the responsable", async () => {
    const made = (await ask()).body;
    const done = await w.a.post(`/v1/returns/${made.id}/approve`, {});
    expect(done.status).toBe(201);
    expect(done.body).toMatchObject({
      status: "APPROVED",
      action: "REMOVE",
      decidedBy: { name: "Admin" },
    });
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 7,
      "Serum Niacinamide": 8,
    });
    const ownerDb = await owner();
    const moves = await ownerDb.query(
      `SELECT reason, delta FROM "StockMovement" WHERE "refType" = 'StockReturn' ORDER BY delta`,
    );
    await ownerDb.end();
    expect(moves.rows.map((r) => [r.reason, r.delta])).toEqual([
      ["RETURN_OUT", -3],
      ["RETURN_OUT", -2],
    ]);
    expect((await inbox(w.nord)).some((n) => n.key === "return.approved")).toBe(
      true,
    );
    expect(
      (await w.a.post(`/v1/returns/${made.id}/approve`, {})).body.code,
    ).toBe("INVALID_STATE");
    const history = (await w.a.get("/v1/approvals/history?type=RETURN")).body
      .items;
    expect(history[0]).toMatchObject({
      type: "RETURN",
      outcome: "APPROVED",
      name: expect.stringContaining("Para Lac"),
    });
  });

  it("can correct the quantities while approving", async () => {
    const made = (await ask()).body;
    const done = await w.a.post(`/v1/returns/${made.id}/approve`, {
      lines: lines(1),
    });
    expect(done.body.units).toBe(1);
    expect(done.body.lines[0]).toMatchObject({
      quantity: 1,
      requestedQuantity: 3,
    });
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 9,
      "Serum Niacinamide": 10,
    });
  });

  it("can move it to another para instead: out of this one, into that one, even in another region", async () => {
    const made = (await ask()).body;
    const done = await w.a.post(`/v1/returns/${made.id}/approve`, {
      toPdvId: sudPdv.id,
    });
    expect(done.body).toMatchObject({
      status: "APPROVED",
      action: "MOVE",
      to: { name: "Para Sud" },
    });
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 7,
      "Serum Niacinamide": 8,
    });
    expect(await levels(w, sudPdv.id)).toMatchObject({
      "Serum Vitamin C": 7,
      "Serum Niacinamide": 6,
    });
    // The responsable of the receiving region is told, and the history says where it went.
    expect(
      (await inbox(w.sud)).find((n) => n.key === "return.moved")!.params,
    ).toMatchObject({ para: "Para Lac", to: "Para Sud", units: 5 });
    const history = (await w.a.get("/v1/approvals/history?type=RETURN")).body
      .items;
    expect(history[0].name).toContain("Para Lac → Para Sud");
    // The responsable of the receiving region does not see it (it belongs to the para it left).
    expect((await w.s.get("/v1/returns")).body).toEqual([]);
    expect((await w.n.get("/v1/returns")).body).toHaveLength(1);
  });

  it("refuses to move to the same para or to an inactive one", async () => {
    const made = (await ask()).body;
    expect(
      (await w.a.post(`/v1/returns/${made.id}/approve`, { toPdvId: lac.id }))
        .body.code,
    ).toBe("SAME_PLACE");
    await w.a.post(`/v1/pdvs/${marsa.id}/suspend`, {});
    expect(
      (await w.a.post(`/v1/returns/${made.id}/approve`, { toPdvId: marsa.id }))
        .body.code,
    ).toBe("PLACE_INACTIVE");
    expect((await w.a.get(`/v1/returns/${made.id}`)).body.status).toBe(
      "PENDING",
    );
  });

  it("checks the stock again when approving", async () => {
    const made = (await ask({ lines: lines(10) })).body;
    const seller = await createAccount({ role: "VENDEUR", pdvId: lac.id });
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Serums",
      amountMillimes: 500,
      startsOn: new Date().toISOString().slice(0, 10),
    });
    await client(api, seller.token).post("/v1/sales", {
      id: crypto.randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 4 }],
    });
    const refused = await w.a.post(`/v1/returns/${made.id}/approve`, {});
    expect(refused.status).toBe(409);
    expect(refused.body.details.products[0]).toMatchObject({
      available: 6,
      wanted: 10,
    });
    expect(
      (await w.a.post(`/v1/returns/${made.id}/approve`, { lines: lines(6) }))
        .status,
    ).toBe(201);
  });

  it("refuses with a reason; only the admin decides", async () => {
    const made = (await ask()).body;
    expect((await w.a.post(`/v1/returns/${made.id}/reject`, {})).status).toBe(
      400,
    );
    for (const c of [w.n, w.s]) {
      expect((await c.post(`/v1/returns/${made.id}/approve`, {})).status).toBe(
        403,
      );
      expect(
        (await c.post(`/v1/returns/${made.id}/reject`, { note: "no" })).status,
      ).toBe(403);
    }
    const refused = await w.a.post(`/v1/returns/${made.id}/reject`, {
      note: "Keep it",
    });
    expect(refused.body).toMatchObject({
      status: "REJECTED",
      decisionNote: "Keep it",
    });
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 10 });
    expect(
      (await inbox(w.nord)).find((n) => n.key === "return.rejected")!.params
        .note,
    ).toBe("Keep it");
  });

  it("expires after three days without a decision", async () => {
    const made = (await ask()).body;
    await expireReturns(db, new Date(Date.now() + 2 * 86_400_000));
    expect((await w.a.get(`/v1/returns/${made.id}`)).body.status).toBe(
      "PENDING",
    );
    await expireReturns(db, new Date(Date.now() + 4 * 86_400_000));
    expect((await w.a.get(`/v1/returns/${made.id}`)).body.status).toBe(
      "EXPIRED",
    );
    expect((await inbox(w.nord)).some((n) => n.key === "return.expired")).toBe(
      true,
    );
  });
});

describe("the admin acts directly, on any para", () => {
  it("removes only: it applies at once", async () => {
    const made = await w.a.post("/v1/returns", {
      pdvId: sudPdv.id,
      lines: lines(1, 1),
    });
    expect(made.body).toMatchObject({
      status: "APPROVED",
      action: "REMOVE",
      units: 2,
    });
    expect(await levels(w, sudPdv.id)).toMatchObject({
      "Serum Vitamin C": 3,
      "Serum Niacinamide": 3,
    });
    expect(
      (await w.a.post("/v1/returns", { pdvId: sudPdv.id, lines: lines(9) }))
        .body.code,
    ).toBe("RETURN_STOCK");
  });

  it("moves to another para at once, which needs the receiving para", async () => {
    expect(
      (
        await w.a.post("/v1/returns", {
          pdvId: lac.id,
          action: "MOVE",
          lines: lines(2),
        })
      ).body.code,
    ).toBe("INVALID_ACTION");
    const made = await w.a.post("/v1/returns", {
      pdvId: lac.id,
      action: "MOVE",
      toPdvId: marsa.id,
      lines: lines(2),
    });
    expect(made.body).toMatchObject({
      status: "APPROVED",
      action: "MOVE",
      to: { name: "Para Marsa" },
    });
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 8 });
    expect(await levels(w, marsa.id)).toMatchObject({ "Serum Vitamin C": 2 });
    const ownerDb = await owner();
    const moves = await ownerDb.query(
      `SELECT reason, delta FROM "StockMovement" WHERE "refType" = 'StockReturn' ORDER BY delta`,
    );
    await ownerDb.end();
    expect(moves.rows.map((r) => [r.reason, r.delta])).toEqual([
      ["RETURN_OUT", -2],
      ["RETURN_IN", 2],
    ]);
  });

  it("only adds: no stock needed, no receiving para", async () => {
    const made = await w.a.post("/v1/returns", {
      pdvId: marsa.id,
      action: "ADD",
      lines: lines(5, 3),
    });
    expect(made.body).toMatchObject({
      status: "APPROVED",
      action: "ADD",
      units: 8,
    });
    expect(await levels(w, marsa.id)).toMatchObject({
      "Serum Vitamin C": 5,
      "Serum Niacinamide": 3,
    });
    expect(
      (
        await w.a.post("/v1/returns", {
          pdvId: marsa.id,
          action: "ADD",
          toPdvId: lac.id,
          lines: lines(1),
        })
      ).body.code,
    ).toBe("INVALID_ACTION");
    expect(
      (
        await w.a.post("/v1/returns", {
          pdvId: marsa.id,
          action: "ADD",
          lines: [{ productId: crypto.randomUUID(), quantity: 1 }],
        })
      ).body.code,
    ).toBe("PRODUCT_NOT_FOUND");
  });

  it("is recorded in the admin's history and tells the responsable of the para", async () => {
    await w.a.post("/v1/returns", {
      pdvId: lac.id,
      action: "ADD",
      lines: lines(1),
    });
    expect((await inbox(w.nord)).some((n) => n.key === "return.added")).toBe(
      true,
    );
    const history = (await w.a.get("/v1/approvals/history?type=RETURN")).body
      .items;
    expect(history[0].outcome).toBe("APPROVED");
  });
});

describe("history stays", () => {
  it("a revision cannot be rewritten", async () => {
    const made = (await ask()).body;
    await w.n.post(`/v1/returns/${made.id}/edit`, { lines: lines(1) });
    const ownerDb = await owner();
    try {
      await expect(
        ownerDb.query(`UPDATE "ReturnRevision" SET "editorId" = "editorId"`),
      ).rejects.toThrow(/append-only/);
      await expect(
        ownerDb.query(`DELETE FROM "ReturnRevision"`),
      ).rejects.toThrow(/append-only/);
    } finally {
      await ownerDb.end();
    }
  });
});
