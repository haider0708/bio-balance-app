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
  photo,
  stockPlace,
  teamMember,
  type World,
} from "./world";
import { Database } from "../src/core/database";
import { expireTransfers } from "../src/jobs/transfers";

let api: Api;
let w: World;
let db: Database;
let lac: { id: string };
let marsa: { id: string };
let carthage: { id: string };
let lacMember: Account;
let marsaMember: Account;
let loner: { id: string };
let sudPdv: { id: string };

beforeAll(async () => {
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api?.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  // Three paras of one group, one para without a group, one in another region.
  lac = await approvedPdv(w, "n", "Para Lac");
  marsa = await approvedPdv(w, "n", "Para Marsa");
  carthage = await approvedPdv(w, "n", "Para Carthage");
  loner = await approvedPdv(w, "n", "Para Seul");
  sudPdv = await approvedPdv(w, "s", "Para Sud");
  const group = (await w.n.post("/v1/groups", { name: "Groupe Tunis" })).body;
  await w.a.post(`/v1/groups/${group.id}/approve`, {});
  for (const p of [lac, marsa, carthage])
    await w.n.patch(`/v1/pdvs/${p.id}`, { groupId: group.id });
  await stockPlace(w, lac.id, w.nord, [10, 10, 10]);
  await stockPlace(w, marsa.id, w.nord, [5, 0, 5]);
  await stockPlace(w, loner.id, w.nord, [10, 10, 10]);
  lacMember = await teamMember(w, lac.id, "Lina Lac");
  marsaMember = await teamMember(w, marsa.id, "Mehdi Marsa");
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

async function send(who: Account, over: object = {}) {
  const c = client(api, who.token);
  return c.post("/v1/transfers", {
    fromPdvId: lac.id,
    toPdvId: marsa.id,
    direction: "SEND",
    lines: lines(3, 2),
    photoId: await photo(w, who),
    ...over,
  });
}

describe("recording a transfer", () => {
  it("a team member sends products to another para of their group, with one photo, and nothing moves yet", async () => {
    const made = await send(lacMember, { note: "Called Mehdi" });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      status: "PENDING",
      direction: "SEND",
      units: 5,
      group: { name: "Groupe Tunis" },
      from: { name: "Para Lac" },
      to: { name: "Para Marsa" },
      createdBy: { name: "Lina Lac" },
      note: "Called Mehdi",
      canEdit: true,
      canCancel: true,
      canDecide: false,
    });
    expect(made.body.number).toMatch(/^TR-\d{4}-\d{6}$/);
    expect(made.body.photoId).toBeTruthy();
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 10 });
    expect(await levels(w, marsa.id)).toMatchObject({ "Serum Vitamin C": 5 });
  });

  it("a team member asking for products is the receiver, whatever the request says", async () => {
    const made = await send(marsaMember, {
      fromPdvId: lac.id,
      toPdvId: marsa.id,
      direction: "SEND",
    });
    expect(made.body.direction).toBe("REQUEST");
    // The partner's stock is not shown to them, but a request for more than it holds is refused.
    const tooMuch = await send(marsaMember, { lines: lines(30) });
    expect(tooMuch.status).toBe(409);
    expect(tooMuch.body.code).toBe("TRANSFER_STOCK");
    expect(tooMuch.body.details.products[0]).toMatchObject({
      available: 10,
      wanted: 30,
    });
  });

  it("only between paras of the same group, active, and different", async () => {
    expect((await send(lacMember, { toPdvId: loner.id })).body.code).toBe(
      "NOT_SAME_GROUP",
    );
    expect((await send(lacMember, { toPdvId: sudPdv.id })).body.code).toBe(
      "NOT_SAME_GROUP",
    );
    expect((await send(lacMember, { toPdvId: lac.id })).body.code).toBe(
      "SAME_PLACE",
    );
    await w.a.post(`/v1/pdvs/${carthage.id}/suspend`, {});
    expect((await send(lacMember, { toPdvId: carthage.id })).body.code).toBe(
      "PLACE_INACTIVE",
    );
  });

  it("needs one photo (not for the admin), real quantities and enough stock", async () => {
    const c = client(api, lacMember.token);
    const body = {
      fromPdvId: lac.id,
      toPdvId: marsa.id,
      direction: "SEND",
      lines: lines(1),
    };
    expect((await c.post("/v1/transfers", body)).body.code).toBe(
      "PHOTO_REQUIRED",
    );
    expect((await send(lacMember, { lines: lines(0, 0) })).status).toBe(400);
    expect(
      (
        await send(lacMember, {
          lines: [{ productId: w.products[0]!.id, quantity: 0 }],
        })
      ).status,
    ).toBe(400);
    const dup = lines(1);
    expect((await send(lacMember, { lines: [...dup, ...dup] })).body.code).toBe(
      "DUPLICATE_PRODUCT",
    );
    const short = await send(lacMember, { lines: lines(11) });
    expect(short.status).toBe(409);
    expect(short.body.code).toBe("TRANSFER_STOCK");
    // Somebody else's photo cannot be used.
    const stolen = await photo(w, w.nord);
    expect((await send(lacMember, { photoId: stolen })).body.code).toBe(
      "PHOTO_REQUIRED",
    );
  });

  it("who may record: the paras' team members and their region's responsable, not a third para, not another region", async () => {
    const third = await teamMember(w, carthage.id, "Chaima");
    // Carthage is in the group but is neither side of this transfer.
    expect((await send(third)).status).toBe(403);
    const other = await createAccount({ role: "VENDEUR", pdvId: sudPdv.id });
    expect((await send(other)).status).toBe(403);
    expect((await send(w.sud)).status).toBe(403);
    expect((await send(w.nord)).status).toBe(201);
  });
});

describe("the admin decides", () => {
  it("approving moves the stock in one go, with a history line on each side", async () => {
    const made = (await send(lacMember)).body;
    // The admin sees it in the queue, with the photo.
    const queue = (await w.a.get("/v1/approvals")).body;
    expect(queue.counts.TRANSFER).toBe(1);
    expect(queue.items.find((i: any) => i.type === "TRANSFER")).toMatchObject({
      id: made.id,
      name: "Para Lac → Para Marsa",
      by: "Lina Lac",
      meta: { number: made.number, units: 5, changed: false },
    });
    const approved = await w.a.post(`/v1/transfers/${made.id}/approve`, {});
    expect(approved.status).toBe(201);
    expect(approved.body).toMatchObject({
      status: "APPROVED",
      decidedBy: { name: "Admin" },
    });
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 7,
      "Serum Niacinamide": 8,
    });
    expect(await levels(w, marsa.id)).toMatchObject({
      "Serum Vitamin C": 8,
      "Serum Niacinamide": 2,
    });
    const ownerDb = await owner();
    const moves = await ownerDb.query(
      `SELECT reason, delta FROM "StockMovement" WHERE "refType" = 'StockTransfer' ORDER BY reason, delta`,
    );
    await ownerDb.end();
    expect(moves.rows.map((r) => [r.reason, r.delta])).toEqual([
      ["TRANSFER_IN", 2],
      ["TRANSFER_IN", 3],
      ["TRANSFER_OUT", -3],
      ["TRANSFER_OUT", -2],
    ]);
    // Everybody concerned is told; a decided transfer cannot be decided again.
    for (const who of [lacMember, marsaMember, w.nord])
      expect(
        (await inbox(who)).some((n) => n.key === "transfer.approved"),
      ).toBe(true);
    expect(
      (await w.a.post(`/v1/transfers/${made.id}/approve`, {})).body.code,
    ).toBe("INVALID_STATE");
    expect((await w.a.get("/v1/approvals")).body.counts.TRANSFER).toBe(0);
  });

  it("can correct the quantities while approving: what the admin writes is what moves", async () => {
    const made = (await send(lacMember)).body;
    const approved = await w.a.post(`/v1/transfers/${made.id}/approve`, {
      lines: lines(1, 2),
      note: "Only one",
    });
    expect(approved.body.units).toBe(3);
    expect(
      approved.body.lines.find((l: any) => l.name === "Serum Vitamin C"),
    ).toMatchObject({
      quantity: 1,
      requestedQuantity: 3,
    });
    expect(approved.body.changes).toHaveLength(1);
    expect(await levels(w, lac.id)).toMatchObject({
      "Serum Vitamin C": 9,
      "Serum Niacinamide": 8,
    });
  });

  it("checks the stock again when approving: a sale in between can make it impossible", async () => {
    const made = (await send(lacMember, { lines: lines(10) })).body;
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
    const refused = await w.a.post(`/v1/transfers/${made.id}/approve`, {});
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("TRANSFER_STOCK");
    expect(refused.body.details.products[0]).toMatchObject({
      available: 6,
      wanted: 10,
    });
    // Nothing moved, and it still waits.
    expect(await levels(w, marsa.id)).toMatchObject({ "Serum Vitamin C": 5 });
    expect((await w.a.get(`/v1/transfers/${made.id}`)).body.status).toBe(
      "PENDING",
    );
    // Approved with what is left.
    expect(
      (await w.a.post(`/v1/transfers/${made.id}/approve`, { lines: lines(6) }))
        .status,
    ).toBe(201);
  });

  it("refuses with a reason, tells the people concerned, and moves nothing", async () => {
    const made = (await send(lacMember)).body;
    expect((await w.a.post(`/v1/transfers/${made.id}/reject`, {})).status).toBe(
      400,
    );
    const refused = await w.a.post(`/v1/transfers/${made.id}/reject`, {
      note: "Not needed",
    });
    expect(refused.body).toMatchObject({
      status: "REJECTED",
      decisionNote: "Not needed",
    });
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 10 });
    expect(
      (await inbox(lacMember)).find((n) => n.key === "transfer.rejected")!
        .params.note,
    ).toBe("Not needed");
    // The decision is in the admin's history.
    const history = (await w.a.get("/v1/approvals/history?type=TRANSFER")).body
      .items;
    expect(history[0]).toMatchObject({
      type: "TRANSFER",
      outcome: "REJECTED",
      name: expect.stringContaining("Para Lac → Para Marsa"),
    });
  });

  it("belongs to the admin alone", async () => {
    const made = (await send(lacMember)).body;
    for (const c of [client(api, lacMember.token), w.n, w.s]) {
      expect(
        (await c.post(`/v1/transfers/${made.id}/approve`, {})).status,
      ).toBe(403);
      expect(
        (await c.post(`/v1/transfers/${made.id}/reject`, { note: "no" }))
          .status,
      ).toBe(403);
    }
  });

  it("an admin's own transfer moves at once, with no photo and no waiting", async () => {
    const made = await w.a.post("/v1/transfers", {
      fromPdvId: lac.id,
      toPdvId: carthage.id,
      direction: "SEND",
      lines: lines(4),
    });
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      status: "APPROVED",
      photoId: null,
      units: 4,
    });
    expect(await levels(w, lac.id)).toMatchObject({ "Serum Vitamin C": 6 });
    expect(await levels(w, carthage.id)).toMatchObject({
      "Serum Vitamin C": 4,
    });
    const history = (await w.a.get("/v1/approvals/history?type=TRANSFER")).body
      .items;
    expect(history[0].outcome).toBe("APPROVED");
  });
});

describe("changing, cancelling, expiring", () => {
  it("either para or the responsable can change the quantities before the admin decides, and it is written down", async () => {
    const made = (await send(lacMember)).body;
    const changed = await client(api, marsaMember.token).post(
      `/v1/transfers/${made.id}/edit`,
      {
        lines: lines(2, 2, 1),
      },
    );
    expect(changed.status).toBe(201);
    expect(changed.body).toMatchObject({ units: 5, revision: 1 });
    expect(changed.body.changes[0]).toMatchObject({
      by: { name: "Mehdi Marsa" },
    });
    const queue = (await w.a.get("/v1/approvals")).body.items.find(
      (i: any) => i.type === "TRANSFER",
    );
    expect(queue.meta.changed).toBe(true);
    expect(
      (await inbox(w.admin)).some((n) => n.key === "transfer.changed"),
    ).toBe(true);
    // The first quantities stay visible; the same numbers again change nothing.
    expect(
      changed.body.lines.find((l: any) => l.name === "Serum Vitamin C"),
    ).toMatchObject({ quantity: 2, requestedQuantity: 3 });
    expect(
      (
        await w.n.post(`/v1/transfers/${made.id}/edit`, {
          lines: lines(2, 2, 1),
        })
      ).body.revision,
    ).toBe(1);
    // A third para of the group is not part of it; too much is refused.
    const third = await teamMember(w, carthage.id);
    expect(
      (
        await client(api, third.token).post(`/v1/transfers/${made.id}/edit`, {
          lines: lines(1),
        })
      ).status,
    ).toBe(404);
    expect(
      (await w.n.post(`/v1/transfers/${made.id}/edit`, { lines: lines(99) }))
        .body.code,
    ).toBe("TRANSFER_STOCK");
  });

  it("is cancelled by one of the paras, and no longer waits for the admin", async () => {
    const made = (await send(lacMember)).body;
    const gone = await client(api, lacMember.token).post(
      `/v1/transfers/${made.id}/cancel`,
    );
    expect(gone.body).toMatchObject({ status: "CANCELLED", canEdit: false });
    expect((await w.a.get("/v1/approvals")).body.counts.TRANSFER).toBe(0);
    expect(
      (await w.a.post(`/v1/transfers/${made.id}/approve`, {})).body.code,
    ).toBe("INVALID_STATE");
    expect((await w.n.post(`/v1/transfers/${made.id}/cancel`)).body.code).toBe(
      "INVALID_STATE",
    );
  });

  it("expires after three days without a decision, and the people who made it are told", async () => {
    const made = (await send(lacMember)).body;
    await expireTransfers(db, new Date(Date.now() + 2 * 86_400_000));
    expect((await w.a.get(`/v1/transfers/${made.id}`)).body.status).toBe(
      "PENDING",
    );
    await expireTransfers(db, new Date(Date.now() + 4 * 86_400_000));
    expect((await w.a.get(`/v1/transfers/${made.id}`)).body.status).toBe(
      "EXPIRED",
    );
    expect(
      (await inbox(lacMember)).some((n) => n.key === "transfer.expired"),
    ).toBe(true);
    expect(
      (await w.a.post(`/v1/transfers/${made.id}/approve`, {})).body.code,
    ).toBe("INVALID_STATE");
  });
});

describe("who sees transfers", () => {
  it("a team member sees the transfers of their own para only, the responsable their region's, the admin all", async () => {
    const made = (await send(lacMember)).body;
    const third = await teamMember(w, carthage.id, "Chaima");
    const ids = async (c: ReturnType<typeof client>) =>
      (await c.get("/v1/transfers")).body.map((t: any) => t.id);
    expect(await ids(client(api, lacMember.token))).toEqual([made.id]);
    expect(await ids(client(api, marsaMember.token))).toEqual([made.id]);
    expect(await ids(client(api, third.token))).toEqual([]);
    expect(
      (await client(api, third.token).get(`/v1/transfers/${made.id}`)).status,
    ).toBe(404);
    expect(await ids(w.n)).toEqual([made.id]);
    expect(await ids(w.s)).toEqual([]);
    expect((await w.s.get(`/v1/transfers/${made.id}`)).status).toBe(404);
    expect(await ids(w.a)).toEqual([made.id]);
    expect((await w.a.get("/v1/transfers?status=APPROVED")).body).toEqual([]);
  });

  it("lists the paras of the same group to choose from, and nothing for a para without a group", async () => {
    const mine = (
      await client(api, lacMember.token).get("/v1/transfers/partners")
    ).body;
    expect(mine.group.name).toBe("Groupe Tunis");
    expect(mine.partners.map((p: any) => p.name)).toEqual([
      "Para Carthage",
      "Para Marsa",
    ]);
    const lonerMember = await teamMember(w, loner.id);
    expect(
      (await client(api, lonerMember.token).get("/v1/transfers/partners")).body,
    ).toEqual({ group: null, partners: [] });
    expect(
      (await w.n.get(`/v1/transfers/partners?pdvId=${lac.id}`)).body.partners,
    ).toHaveLength(2);
    expect(
      (await w.s.get(`/v1/transfers/partners?pdvId=${lac.id}`)).status,
    ).toBe(403);
    // A team member cannot ask about another para.
    expect(
      (
        await client(api, lacMember.token).get(
          `/v1/transfers/partners?pdvId=${marsa.id}`,
        )
      ).body.group.name,
    ).toBe("Groupe Tunis");
  });

  it("history stays: a movement of a transfer cannot be edited, and a revision cannot be rewritten", async () => {
    const made = (await send(lacMember)).body;
    await w.n.post(`/v1/transfers/${made.id}/edit`, { lines: lines(2) });
    const ownerDb = await owner();
    try {
      await expect(
        ownerDb.query(`UPDATE "TransferRevision" SET "editorId" = "editorId"`),
      ).rejects.toThrow(/append-only/);
      await expect(
        ownerDb.query(`DELETE FROM "TransferRevision"`),
      ).rejects.toThrow(/append-only/);
    } finally {
      await ownerDb.end();
    }
  });
});
