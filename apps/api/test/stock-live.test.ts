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
  });
});

describe("correcting an approved count", () => {
  async function approvedCount(quantities = [20, 10, 0]) {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, quantities);
    await w.a.post(`/v1/stock/declarations/${d.id}/approve`, {});
    return { pdv, d };
  }
  const ask = (id: string, reason = "Typed 20 instead of 22") =>
    w.n.post(`/v1/stock/declarations/${id}/correction-request`, { reason });

  it("needs the admin's approval first, then is made once, with the stock following", async () => {
    const { pdv, d } = await approvedCount();
    await sell(await seller(pdv.id), 0, 5);
    const edit = (lines = [line(0, 22), line(1, 10)]) =>
      w.n.put(`/v1/stock/declarations/${d.id}`, { lines });
    // Without a request the responsable cannot correct.
    expect((await edit()).body.code).toBe("CORRECTION_NOT_APPROVED");

    const asked = await ask(d.id);
    expect(asked.status).toBe(201);
    expect((await ask(d.id)).body.code).toBe("CORRECTION_PENDING");
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correction,
    ).toMatchObject({ status: "PENDING" });
    // Still waiting: nothing changes.
    expect((await edit()).body.code).toBe("CORRECTION_NOT_APPROVED");

    // The request reaches the admin's inbox, then the admin approves it.
    const inbox = (await w.a.get("/v1/approvals")).body.items as any[];
    expect(inbox.find((i) => i.id === asked.body.id)).toMatchObject({
      type: "RECOUNT",
      meta: { kind: "CORRECTION" },
    });
    expect(
      (await w.a.post(`/v1/stock/recounts/${asked.body.id}/approve`, {}))
        .status,
    ).toBe(201);
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correction,
    ).toMatchObject({ status: "APPROVED" });

    const fixed = await edit();
    expect(fixed.status).toBe(200);
    expect(fixed.body.status).toBe("APPROVED"); // no new approval of the count itself
    expect(fixed.body.lines.find((l: any) => l.name === VITC)).toMatchObject({
      quantity: 22,
      approvedQuantity: 22,
    });
    expect((await levels(w, pdv.id))[VITC]).toBe(17); // 22 - 5 sold, not "22"
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correction,
    ).toMatchObject({ status: "USED" });
    // The permission was for one correction.
    expect((await edit([line(0, 23)])).body.code).toBe(
      "CORRECTION_NOT_APPROVED",
    );
    const told = (await w.a.get("/v1/notifications")).body.items.find(
      (n: any) => n.key === "stock.corrected",
    );
    expect(told).toBeTruthy();
    const audit = (await w.a.get("/v1/audit?limit=40")).body.items as any[];
    expect(audit.map((e) => e.action)).toEqual(
      expect.arrayContaining(["stock.correction_requested", "stock.corrected"]),
    );
  });

  it("a refused request can be asked again, and the request is open for 3 days on the latest count", async () => {
    const { d } = await approvedCount();
    const first = await ask(d.id);
    expect(
      (await w.a.post(`/v1/stock/recounts/${first.body.id}/reject`, {})).status,
    ).toBe(400); // a refusal needs its reason
    await w.a.post(`/v1/stock/recounts/${first.body.id}/reject`, {
      note: "Count again tomorrow",
    });
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correction,
    ).toMatchObject({ status: "REJECTED", note: "Count again tomorrow" });
    expect((await ask(d.id, "I checked again")).status).toBe(201);

    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "StockDeclaration" SET "decidedAt" = now() - interval '4 days' WHERE id = $1`,
        [d.id],
      );
    } finally {
      await ownerDb.end();
    }
    const late = await ask(d.id);
    expect(late.status).toBe(403);
    expect(late.body.code).toBe("STOCK_CORRECTION_CLOSED");
    expect(
      (await w.n.get(`/v1/stock/declarations/${d.id}`)).body.correctableUntil,
    ).toBeNull();
  });

  it("is never asked for a count the admin made; the admin edits it directly, never below what was sold", async () => {
    const pdv = await approvedPdv(w);
    const own = await w.a.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.admin),
      lines: [line(0, 10)],
    });
    expect(own.body.status).toBe("APPROVED");
    expect((await ask(own.body.id)).status).toBe(403);
    expect(
      (
        await w.n.put(`/v1/stock/declarations/${own.body.id}`, {
          lines: [line(0, 99)],
          reason: "Not mine",
        })
      ).status,
    ).toBe(403);

    const { pdv: store, d } = await approvedCount([20, 0, 0]);
    await sell(await seller(store.id), 0, 18);
    // The admin needs no request and no time limit, only a reason, and cannot go below what was sold.
    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "StockDeclaration" SET "decidedAt" = now() - interval '30 days' WHERE id = $1`,
        [d.id],
      );
    } finally {
      await ownerDb.end();
    }
    const noReason = await w.a.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 25), line(1, 3)],
    });
    expect(noReason.body.code).toBe("REASON_REQUIRED");
    const low = await w.a.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 5)],
      reason: "Recounted",
    });
    expect(low.body.code).toBe("BELOW_SOLD");
    expect(low.body.details.products[0]).toMatchObject({
      name: VITC,
      minimum: 18,
    });
    expect((await levels(w, store.id))[VITC]).toBe(2);
    const ok = await w.a.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 25), line(1, 3)],
      reason: "Two products were missing",
    });
    expect(ok.status).toBe(200);
    expect((await levels(w, store.id))[VITC]).toBe(7); // 25 - 18 sold
    expect((await levels(w, store.id))[NIAC]).toBe(3);
  });
});

describe("the admin and the responsable on a waiting count", () => {
  it("the admin edits it directly (add, remove, change), the responsable's old form is refused, and she is told", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 10, 0]);
    expect(d.revision).toBe(0);
    await w.n.post(`/v1/stock/declarations/${d.id}/edit`, {});
    // The admin takes over the count she was correcting.
    const byAdmin = await w.a.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 15), line(2, 4)], // NIAC removed, ARGAN added
      revision: 0,
    });
    expect(byAdmin.status).toBe(200);
    expect(byAdmin.body.status).toBe("PENDING"); // still waiting for a decision
    expect(byAdmin.body.revision).toBe(1);
    expect(byAdmin.body.editing).toBeNull();
    const stock = await levels(w, pdv.id);
    expect(stock[VITC]).toBe(15);
    expect(stock[ARGAN]).toBe(4);
    expect(stock[NIAC] ?? 0).toBe(0);
    // Her form was opened on revision 0: saving it now would overwrite the admin's change.
    const stale = await w.n.put(`/v1/stock/declarations/${d.id}`, {
      lines: [line(0, 20), line(1, 10)],
      revision: 0,
    });
    expect(stale.status).toBe(409);
    expect(stale.body.code).toBe("STALE_COUNT");
    expect(
      (await w.n.get("/v1/notifications")).body.items.some(
        (n: any) => n.key === "stock.admin_edited",
      ),
    ).toBe(true);
    // With the current revision her save works.
    expect(
      (
        await w.n.put(`/v1/stock/declarations/${d.id}`, {
          lines: [line(0, 16), line(2, 4)],
          revision: 1,
        })
      ).status,
    ).toBe(200);
  });

  it("a rejected count cannot be edited, by anyone", async () => {
    const pdv = await approvedPdv(w);
    const d = await declare(pdv.id, [20, 0, 0]);
    await w.a.post(`/v1/stock/declarations/${d.id}/reject`, {
      note: "Wrong photo",
    });
    expect(
      (await w.a.put(`/v1/stock/declarations/${d.id}`, { lines: [line(0, 1)] }))
        .status,
    ).toBe(409);
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

  it("shows the lines of a count in the order they were entered", async () => {
    const pdv = await approvedPdv(w);
    // Not alphabetical: Shampoo, Serum Vitamin C, Serum Niacinamide.
    const order = [2, 0, 1];
    const made = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: order.map((i) => line(i, 3 + i)),
    });
    expect(made.status).toBe(201);
    const read = await w.n.get(`/v1/stock/declarations/${made.body.id}`);
    expect(read.body.lines.map((l: { name: string }) => l.name)).toEqual([
      "Shampoo Argan",
      "Serum Vitamin C",
      "Serum Niacinamide",
    ]);
  });
});
