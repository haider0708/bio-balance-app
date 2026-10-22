import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
import {
  approvedPdv,
  buildWorld,
  levels,
  photo,
  stockPlace,
  teamMember,
  type World,
} from "./world";

/**
 * The admin can change a decision for 6 hours: put it back to waiting, or correct its quantities.
 * After that it is final. A payout, once paid, is never taken back.
 */
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

const history = async (type?: string) =>
  (await w.a.get(`/v1/approvals/history${type ? `?type=${type}` : ""}`)).body
    .items as any[];
const latest = async (id: string) => (await history()).find((i) => i.id === id);
const line = (i: number, quantity: number) => ({
  productId: w.products[i]!.id,
  quantity,
});

/** Pretends a decision was made `hours` ago (the log itself is never edited). */
async function age(table: string, id: string, column: string, hours: number) {
  const db = await owner();
  try {
    await db.query(
      `UPDATE "${table}" SET "${column}" = "${column}" - ($2 || ' hours')::interval WHERE id = $1`,
      [id, String(hours)],
    );
  } finally {
    await db.end();
  }
}

describe("groups, stores and members", () => {
  it("a group approved or rejected can be put back to waiting for 6 hours", async () => {
    const group = (await w.n.post("/v1/groups", { name: "Groupe Tunis" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    const item = await latest(group.id);
    expect(item.change.options).toEqual(["reopen"]);
    expect(new Date(item.change.until).getTime()).toBeGreaterThan(
      Date.now() + 5.9 * 3_600_000,
    );

    expect((await w.a.post(`/v1/groups/${group.id}/reopen`, {})).status).toBe(
      201,
    );
    expect((await w.n.get("/v1/groups")).body[0].status).toBe("PENDING");
    const told = (await w.n.get("/v1/notifications")).body.items.map(
      (n: any) => n.key,
    );
    expect(told).toContain("decision.reopened");
    // Decided again, differently.
    await w.a.post(`/v1/groups/${group.id}/reject`, { note: "Not now" });
    expect((await latest(group.id)).change.options).toEqual(["reopen"]);
    // Only the admin does it, and a group not decided cannot be.
    expect((await w.n.post(`/v1/groups/${group.id}/reopen`, {})).status).toBe(
      403,
    );
    await w.a.post(`/v1/groups/${group.id}/reopen`, {});
    expect(
      (await w.a.post(`/v1/groups/${group.id}/reopen`, {})).body.code,
    ).toBe("INVALID_STATE");
  });

  it("is final after 6 hours", async () => {
    const group = (await w.n.post("/v1/groups", { name: "Groupe Tunis" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    await age("Group", group.id, "decidedAt", 7);
    expect((await latest(group.id)).change).toBeNull();
    const late = await w.a.post(`/v1/groups/${group.id}/reopen`, {});
    expect(late.status).toBe(409);
    expect(late.body.code).toBe("DECISION_LOCKED");
  });

  it("a store can be taken back until it sells", async () => {
    const created = (
      await w.n.post("/v1/pdvs", {
        name: "Para Lac",
        address: "1 rue",
        city: "Tunis",
      })
    ).body;
    await w.a.post(`/v1/pdvs/${created.id}/approve`, {});
    expect((await latest(created.id)).change.options).toEqual(["reopen"]);
    await w.a.post(`/v1/pdvs/${created.id}/reopen`, {});
    await w.a.post(`/v1/pdvs/${created.id}/approve`, {});
    // Once it sold, it stays: suspend it instead.
    await stockPlace(w, created.id, w.nord, [10, 0, 0]);
    const seller = client(api, (await teamMember(w, created.id)).token);
    expect(
      (
        await seller.post("/v1/sales", {
          id: randomUUID(),
          lines: [line(0, 1)],
        })
      ).status,
    ).toBe(201);
    expect((await latest(created.id)).change).toBeNull();
    expect(
      (await w.a.post(`/v1/pdvs/${created.id}/reopen`, {})).body.code,
    ).toBe("HAS_ACTIVITY");
  });

  it("a member can be taken back until they set their password", async () => {
    const pdv = await approvedPdv(w);
    const added = (
      await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
        phone: "22 000 000",
        name: "Amira",
        email: "amira@example.test",
      })
    ).body;
    await w.a.post(`/v1/users/${added.id}/approve`, {});
    expect((await latest(added.id)).change.options).toEqual(["reopen"]);
    expect((await w.a.post(`/v1/users/${added.id}/reopen`, {})).status).toBe(
      201,
    );
    expect((await w.a.get(`/v1/users/${added.id}`)).body.status).toBe(
      "PENDING",
    );
    // Approved again, then she signed up: it is final.
    await w.a.post(`/v1/users/${added.id}/approve`, {});
    const db = await owner();
    try {
      await db.query(`UPDATE "User" SET "passwordHash" = 'x' WHERE id = $1`, [
        added.id,
      ]);
    } finally {
      await db.end();
    }
    expect((await latest(added.id)).change).toBeNull();
    expect((await w.a.post(`/v1/users/${added.id}/reopen`, {})).body.code).toBe(
      "INVALID_STATE",
    );
  });
});

describe("stock counts", () => {
  async function counted(quantities = [20, 10, 0]) {
    const pdv = await approvedPdv(w);
    const lines = quantities
      .map((q, i) => line(i, q))
      .filter((l) => l.quantity > 0);
    const d = (
      await w.n.post("/v1/stock/declarations", {
        locationId: pdv.id,
        photoId: await photo(w, w.nord),
        lines,
      })
    ).body;
    return { pdv, d };
  }

  it("an approved count is corrected by the difference, keeping the sales since", async () => {
    const { pdv, d } = await counted();
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {});
    expect((await latest(d.id)).change.options).toEqual(["amend", "reopen"]);
    const seller = client(api, (await teamMember(w, pdv.id)).token);
    await seller.post("/v1/sales", { id: randomUUID(), lines: [line(0, 5)] });

    const amended = await w.a.post(`/v1/stock/declarations/${d.id}/amend`, {
      lines: [line(0, 18), line(2, 4)],
      note: "Recounted on the photo",
    });
    expect(amended.status).toBe(201);
    expect(amended.body.status).toBe("APPROVED");
    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 13, // 18 counted, 5 sold
      "Serum Niacinamide": 10,
      "Shampoo Argan": 4, // added
    });
    const told = (await w.n.get("/v1/notifications")).body.items.map(
      (n: any) => n.key,
    );
    expect(told).toContain("stock.amended");
    // Not below what was sold.
    const low = await w.a.post(`/v1/stock/declarations/${d.id}/amend`, {
      lines: [line(0, 3)],
    });
    expect(low.body.code).toBe("BELOW_SOLD");
    // Final after 6 hours.
    await age("StockDeclaration", d.id, "decidedAt", 7);
    expect((await latest(d.id)).change).toBeNull();
    expect(
      (
        await w.a.post(`/v1/stock/declarations/${d.id}/amend`, {
          lines: [line(0, 19)],
        })
      ).body.code,
    ).toBe("DECISION_LOCKED");
  });

  it("an approved count goes back to waiting, and a rejected one gets its stock back", async () => {
    const { pdv, d } = await counted();
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [line(0, 17)],
    });
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/reopen`, {})).body.status,
    ).toBe("PENDING");
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(17);
    // Decided again, as declared: back to 20.
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {});
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(20);

    await w.a.post(`/v1/stock/declarations/${d.id}/reopen`, {});
    await w.a.post(`/v1/stock/declarations/${d.id}/reject`, {
      note: "Blurred photo",
    });
    expect(await levels(w, pdv.id)).toMatchObject({ "Serum Vitamin C": 0 });
    expect((await latest(d.id)).change.options).toEqual(["reopen"]);
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/reopen`, {})).body.status,
    ).toBe("PENDING");
    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 20,
      "Serum Niacinamide": 10,
    });
  });

  it("a rejected count cannot be taken back once the place was counted again", async () => {
    const { pdv, d } = await counted();
    await w.a.post(`/v1/stock/declarations/${d.id}/reject`, { note: "No" });
    await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: [line(0, 9)],
    });
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/reopen`, {})).body.code,
    ).toBe("DECLARATION_EXISTS");
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(9);
  });

  it("a recount permission not used yet can be taken back", async () => {
    const { pdv, d } = await counted();
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {});
    const asked = (
      await w.n.post("/v1/stock/recounts", {
        locationId: pdv.id,
        reason: "Bought elsewhere",
      })
    ).body;
    await w.a.post(`/v1/stock/recounts/${asked.id}/approve`, {});
    expect((await latest(asked.id)).change.options).toEqual(["reopen"]);
    expect(
      (await w.a.post(`/v1/stock/recounts/${asked.id}/reopen`, {})).body.status,
    ).toBe("PENDING");
  });
});

describe("restocks", () => {
  async function order() {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.nord, [50, 0, 0]);
    const o = (
      await w.n.post("/v1/restocks", { destId: pdv.id, lines: [line(0, 10)] })
    ).body;
    return { pdv, o };
  }

  it("a routed order nobody shipped is taken back, and a shipped one is not", async () => {
    const { o } = await order();
    await w.a.post(`/v1/restocks/${o.id}/assign`, { depotId: w.depotId });
    expect((await latest(o.id)).change.options).toEqual(["reopen"]);
    const back = await w.a.post(`/v1/restocks/${o.id}/reopen`, {});
    expect(back.body).toMatchObject({
      status: "REQUESTED",
      source: null,
      supplier: null,
    });
    // Sent from BioBalance, not received: also possible.
    await w.a.post(`/v1/restocks/${o.id}/send-direct`, {});
    expect(
      (await w.a.post(`/v1/restocks/${o.id}/reopen`, {})).body.status,
    ).toBe("REQUESTED");
    // Shipped from a grossiste: goods left it, so no.
    await w.a.post(`/v1/restocks/${o.id}/assign`, { depotId: w.depotId });
    await w.n.post(`/v1/restocks/${o.id}/ship`, { lines: [line(0, 10)] });
    expect((await latest(o.id))?.change ?? null).toBeNull();
    expect((await w.a.post(`/v1/restocks/${o.id}/reopen`, {})).body.code).toBe(
      "INVALID_STATE",
    );
  });

  it("the quantities received of an approved delivery are corrected by the difference", async () => {
    const { pdv, o } = await order();
    await w.a.post(`/v1/restocks/${o.id}/assign`, { depotId: w.depotId });
    await w.n.post(`/v1/restocks/${o.id}/ship`, { lines: [line(0, 10)] });
    await w.n.post(`/v1/restocks/${o.id}/receipt`, {
      photoId: await photo(w, w.nord),
    });
    await w.a.post(`/v1/restocks/${o.id}/approve`, {});
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(10);
    expect((await latest(o.id)).change.options).toEqual(["amend"]);

    const seller = client(api, (await teamMember(w, pdv.id)).token);
    await seller.post("/v1/sales", { id: randomUUID(), lines: [line(0, 4)] });
    // The admin finds 8 arrived, not 10: 10 - 2 - 4 sold.
    const fixed = await w.a.post(`/v1/restocks/${o.id}/amend`, {
      lines: [line(0, 8)],
    });
    expect(fixed.status).toBe(201);
    expect(fixed.body.lines[0].approved).toBe(8);
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(4);
    // Not below what was sold.
    expect(
      (await w.a.post(`/v1/restocks/${o.id}/amend`, { lines: [line(0, 3)] }))
        .body.code,
    ).toBe("BELOW_SOLD");
    await age("RestockOrder", o.id, "decidedAt", 7);
    expect(
      (await w.a.post(`/v1/restocks/${o.id}/amend`, { lines: [line(0, 9)] }))
        .body.code,
    ).toBe("DECISION_LOCKED");
  });
});

describe("payouts", () => {
  it("are never taken back", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, pdv.id, w.nord, [20, 0, 0]);
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Serums",
      amountMillimes: 1000,
      startsOn: "2026-01-01",
    });
    const seller = client(api, (await teamMember(w, pdv.id)).token);
    await seller.post("/v1/sales", { id: randomUUID(), lines: [line(0, 5)] });
    const payout = (await seller.post("/v1/payouts", { amountMillimes: 2000 }))
      .body;
    await w.a.post(`/v1/payouts/${payout.id}/approve`, {});
    const item = await latest(payout.id);
    expect(item.outcome).toBe("APPROVED");
    expect(item.change).toBeNull();
    expect((await w.a.post(`/v1/payouts/${payout.id}/reopen`, {})).status).toBe(
      404,
    );
  });
});
