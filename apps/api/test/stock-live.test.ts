import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import {
  approvedPdv,
  buildWorld,
  levels,
  photo,
  teamMember,
  type World,
} from "./world";

/**
 * A count reaches the stock when it is declared, so sellers can sell while the admin has not
 * decided yet. Every change after that applies only the difference: what was sold meanwhile is
 * never overwritten, and the stock never goes negative.
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

const [VITC, NIAC, ARGAN] = [
  "Serum Vitamin C",
  "Serum Niacinamide",
  "Shampoo Argan",
];
const line = (i: number, quantity: number) => ({
  productId: w.products[i]!.id,
  quantity,
});

async function declare(where: string, quantities: number[], by = w.n) {
  const lines = quantities
    .map((q, i) => line(i, q))
    .filter((l) => l.quantity > 0);
  const res = await by.post("/v1/stock/declarations", {
    locationId: where,
    photoId: await photo(w, w.nord),
    lines,
  });
  if (res.status !== 201) throw new Error(JSON.stringify(res.body));
  return res.body;
}

async function seller(pdvId: string) {
  const m = await teamMember(w, pdvId);
  return client(api, m.token);
}
const sell = (c: ReturnType<typeof client>, i: number, quantity: number) =>
  c.post("/v1/sales", { id: randomUUID(), lines: [line(i, quantity)] });

describe("a count waiting for the admin", () => {
  it("can be sold from at once, and the admin's amendment applies only the difference", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    const m = await seller(pdv.id);
    expect((await sell(m, 0, 5)).status).toBe(201);
    expect((await levels(w, pdv.id))[VITC]).toBe(15);

    // The admin counts 18 on the photo (2 fewer than declared): 15 - 2, not "18".
    const approved = await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [{ productId: w.products[0]!.id, quantity: 18 }],
    });
    expect(approved.body.status).toBe("APPROVED");
    expect((await levels(w, pdv.id))[VITC]).toBe(13);
    expect((await levels(w, pdv.id))[NIAC]).toBe(10);
    // Approving again changes nothing.
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {})).status,
    ).toBe(409);
    expect((await levels(w, pdv.id))[VITC]).toBe(13);
  });

  it("cannot be approved below what was already sold", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 0, 0]);
    await sell(await seller(pdv.id), 0, 15);
    const refused = await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [{ productId: w.products[0]!.id, quantity: 3 }],
    });
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("BELOW_SOLD");
    expect(refused.body.details.products[0]).toMatchObject({ minimum: 15 });
    // Nothing moved, and it is still waiting.
    expect((await levels(w, pdv.id))[VITC]).toBe(5);
    const ok = await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [{ productId: w.products[0]!.id, quantity: 15 }],
    });
    expect(ok.body.status).toBe("APPROVED");
    expect((await levels(w, pdv.id))[VITC]).toBe(0);
  });

  it("lets the admin add products the responsable left out", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 0, 0]);
    const approved = await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [
        { productId: w.products[1]!.id, quantity: 7 },
        { productId: w.products[2]!.id, quantity: 4 },
      ],
    });
    expect(approved.body.status).toBe("APPROVED");
    expect(await levels(w, pdv.id)).toMatchObject({
      [VITC]: 20,
      [NIAC]: 7,
      [ARGAN]: 4,
    });
    const added = approved.body.lines.filter((l: any) => l.addedByAdmin);
    expect(
      added.map((l: any) => [l.name, l.quantity, l.approvedQuantity]),
    ).toEqual(
      expect.arrayContaining([
        [NIAC, 0, 7],
        [ARGAN, 0, 4],
      ]),
    );
    // An unknown product is refused.
    const second = await declare(
      (await approvedPdv(w, "n", "Para Marsa")).id,
      [1, 0, 0],
    );
    const bad = await w.a.post(`/v1/stock/declarations/${second.id}/approve`, {
      lines: [{ productId: randomUUID(), quantity: 1 }],
    });
    expect(bad.body.code).toBe("PRODUCT_NOT_FOUND");
  });

  it("is taken back when rejected, but not what was sold meanwhile", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    await sell(await seller(pdv.id), 0, 5);
    const rejected = await w.a.post(`/v1/stock/declarations/${d.id}/reject`, {
      note: "Photo does not match",
    });
    expect(rejected.body.status).toBe("REJECTED");
    // The 15 left of the 20 are removed; the 5 sold stay sold; nothing goes negative.
    expect(await levels(w, pdv.id)).toMatchObject({ [VITC]: 0, [NIAC]: 0 });
    // The place can be counted again.
    const again = await declare(pdv.id, [9, 0, 0]);
    expect((await levels(w, pdv.id))[VITC]).toBe(9);
    expect(again.kind).toBe("INITIAL");
  });
});

describe("correcting a waiting count", () => {
  it("puts it on hold for the admin, applies the difference, and gives it back", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    await sell(await seller(pdv.id), 0, 5);

    const held = await w.n.post(`/v1/stock/declarations/${d.id}/edit`, {});
    expect(held.body.editing.by.name).toBeTruthy();
    // The admin sees it is on hold and cannot decide it.
    expect(
      (await w.a.get(`/v1/stock/declarations/${d.id}`)).body.editing,
    ).not.toBeNull();
    const blocked = await w.a.post(
      `/v1/stock/declarations/${d.id}/approve`,
      {},
    );
    expect(blocked.status).toBe(409);
    expect(blocked.body.code).toBe("EDITING");
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/reject`, { note: "no" }))
        .body.code,
    ).toBe("EDITING");

    // The mistake: 25 not 20 of the first, the second was 10 but is 12, the third was missing.
    const saved = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 25), line(1, 12), line(2, 3)],
    });
    expect(saved.status).toBe(200);
    expect(saved.body).toMatchObject({ status: "PENDING", editing: null });
    expect(await levels(w, pdv.id)).toMatchObject({
      [VITC]: 20,
      [NIAC]: 12,
      [ARGAN]: 3,
    });
    // Back with the admin, who approves it.
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {})).body
        .status,
    ).toBe("APPROVED");
    expect((await levels(w, pdv.id))[VITC]).toBe(20);
    const told = (await w.a.get("/v1/notifications")).body.items.map(
      (n: any) => n.key,
    );
    expect(told).toContain("stock.edited");
  });

  it("cannot go below what was sold, and a product left out comes out of the stock", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    await sell(await seller(pdv.id), 0, 15);
    const tooLow = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 10), line(1, 10)],
    });
    expect(tooLow.status).toBe(409);
    expect(tooLow.body.code).toBe("BELOW_SOLD");
    expect(await levels(w, pdv.id)).toMatchObject({ [VITC]: 5, [NIAC]: 10 });
    const fine = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 16)],
    });
    expect(fine.status).toBe(200);
    expect(await levels(w, pdv.id)).toMatchObject({ [VITC]: 1, [NIAC]: 0 });
    expect(fine.body.lines.map((l: any) => l.name)).toEqual([VITC]);
  });

  it("is not on hold for ever: the hold ends by itself", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 0, 0]);
    await w.n.post(`/v1/stock/declarations/${d.id}/edit`, {});
    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "StockDeclaration" SET "editingUntil" = now() - interval '1 minute'`,
      );
    } finally {
      await ownerDb.end();
    }
    expect(
      (await w.a.get(`/v1/stock/declarations/${d.id}`)).body.editing,
    ).toBeNull();
    expect(
      (await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {})).status,
    ).toBe(201);
    // Letting go early works too.
    const next = await approvedPdv(w, "n", "Para Marsa");
    const e = await declare(next.id, [5, 0, 0]);
    await w.n.post(`/v1/stock/declarations/${e.id}/edit`, {});
    await w.n.delete(`/v1/stock/declarations/${e.id}/edit`);
    expect(
      (await w.a.post(`/v1/stock/declarations/${e.id}/approve`, {})).status,
    ).toBe(201);
  });

  it("is the responsable's own work: another region cannot touch it", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 0, 0]);
    expect(
      (await w.s.post(`/v1/stock/declarations/${d.id}/edit`, {})).status,
    ).toBe(404);
    expect(
      (await w.s.put(`/v1/stock/declarations/${d.id}`, { lines: [line(0, 1)] }))
        .status,
    ).toBe(404);
    expect(
      (await w.a.put(`/v1/stock/declarations/${d.id}`, { lines: [] })).status,
    ).toBe(403);
  });
});

describe("correcting an approved count", () => {
  async function approvedCount(quantities = [20, 10, 0]) {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, quantities);
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {});
    return { pdv, d };
  }

  it("needs a reason, applies at once without a new approval, and tells the admin", async () => {
    const { pdv, d } = await approvedCount();
    await sell(await seller(pdv.id), 0, 5);
    const noReason = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 22), line(1, 10)],
    });
    expect(noReason.body.code).toBe("REASON_REQUIRED");

    const fixed = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 22), line(1, 10)],
      reason: "Typed 20 instead of 22",
    });
    expect(fixed.status).toBe(200);
    expect(fixed.body.status).toBe("APPROVED"); // no new approval
    expect(fixed.body.lines.find((l: any) => l.name === VITC)).toMatchObject({
      quantity: 22,
      approvedQuantity: 22,
    });
    expect((await levels(w, pdv.id))[VITC]).toBe(17); // 22 - 5 sold, not "22"
    const told = (await w.a.get("/v1/notifications")).body.items.find(
      (n: any) => n.key === "stock.corrected",
    );
    expect(told.params).toMatchObject({ reason: "Typed 20 instead of 22" });
    const audit = (await w.a.get("/v1/audit?limit=30")).body.items as any[];
    expect(audit.map((e) => e.action)).toContain("stock.corrected");
  });

  it("is open for 3 days after the approval, and only on the latest count", async () => {
    const { pdv, d } = await approvedCount();
    const body = await w.n.get(`/v1/stock/declarations/${d.id}`);
    expect(new Date(body.body.correctableUntil).getTime()).toBeGreaterThan(
      Date.now() + 2.9 * 86_400_000,
    );
    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "StockDeclaration" SET "decidedAt" = now() - interval '4 days' WHERE id = $1`,
        [d.id],
      );
    } finally {
      await ownerDb.end();
    }
    const late = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 21)],
      reason: "Too late",
    });
    expect(late.status).toBe(403);
    expect(late.body.code).toBe("STOCK_CORRECTION_CLOSED");
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correctableUntil,
    ).toBeNull();
    expect((await levels(w, pdv.id))[VITC]).toBe(20);
  });

  it("is refused for a count the admin made, and below what was sold", async () => {
    const pdv = await approvedPdv(w);
    const own = await w.a.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.admin),
      lines: [line(0, 10)],
    });
    expect(own.body.status).toBe("APPROVED");
    const refused = await w.n.put(`/v1/stock/declarations/${own.body.id}`, {
      lines: [line(0, 99)],
      reason: "Not mine",
    });
    expect(refused.status).toBe(403);

    const { pdv: store, d } = await approvedCount([20, 0, 0]);
    await sell(await seller(store.id), 0, 18);
    const low = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 5)],
      reason: "Recounted",
    });
    expect(low.body.code).toBe("BELOW_SOLD");
    expect((await levels(w, store.id))[VITC]).toBe(2);
  });
});

describe("a grossiste's count works the same way", () => {
  it("can ship before the admin decides, and the amendment keeps what left", async () => {
    const d = await declare(w.depotId, [50, 0, 0]);
    expect((await levels(w, w.depotId))[VITC]).toBe(50);
    const pdv = await approvedPdv(w);
    const order = (
      await w.n.post("/v1/restocks", { destId: pdv.id, lines: [line(0, 10)] })
    ).body;
    await w.a.post(`/v1/restocks/${order.id}/assign`, { depotId: w.depotId });
    expect(
      (
        await w.n.post(`/v1/restocks/${order.id}/ship`, {
          lines: [line(0, 10)],
        })
      ).status,
    ).toBe(201);
    expect((await levels(w, w.depotId))[VITC]).toBe(40);
    // The admin counts 45 on the photo: 40 - 5.
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [{ productId: w.products[0]!.id, quantity: 45 }],
    });
    expect((await levels(w, w.depotId))[VITC]).toBe(35);
  });
});

describe("a count made before counts applied at once", () => {
  it("still applies in full when the admin approves it", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    // As it was stored before: nothing applied, nothing in stock.
    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "StockDeclarationLine" SET "appliedQuantity" = NULL`,
      );
      await ownerDb.query(`DELETE FROM "Stock"`);
    } finally {
      await ownerDb.end();
    }
    expect(await levels(w, pdv.id)).toEqual({});
    const approved = await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {
      lines: [{ productId: w.products[0]!.id, quantity: 18 }],
    });
    expect(approved.body.status).toBe("APPROVED");
    expect(await levels(w, pdv.id)).toMatchObject({ [VITC]: 18, [NIAC]: 10 });
  });
});
