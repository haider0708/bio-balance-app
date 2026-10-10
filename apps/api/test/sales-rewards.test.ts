import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  resetDatabase,
  startApi,
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
import { addDays, tunisDay } from "../src/core/dates";

let api: Api;
let w: World;
const today = () => tunisDay(new Date());
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

/** A point of sale with 20 of each product and one team member who can sell. */
async function shop(region: "n" | "s" = "n") {
  const pdv = await approvedPdv(
    w,
    region,
    region === "n" ? "Para" : "Para Sud",
  );
  await stockPlace(w, pdv.id, region === "n" ? w.nord : w.sud, [20, 20, 20]);
  const member = await teamMember(w, pdv.id);
  return { pdv, member, m: client(api, member.token) };
}

const family = (amountMillimes: number, extra: object = {}) => ({
  scope: "FAMILY",
  family: "Serums",
  amountMillimes,
  startsOn: today(),
  ...extra,
});

describe("reward rules", () => {
  it("pay per family, with a product able to override its family", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    await w.a.post("/v1/reward-rules", {
      scope: "PRODUCT",
      productId: w.products[0]!.id,
      amountMillimes: 800,
      startsOn: today(),
    });
    const effective = (
      await w.a.get(`/v1/reward-rules/effective?day=${today()}`)
    ).body;
    const pay = Object.fromEntries(
      effective.map((e: any) => [e.name, e.amountMillimes]),
    );
    expect(pay).toEqual({
      "Serum Vitamin C": 800,
      "Serum Niacinamide": 500,
      "Shampoo Argan": 0,
    });
    // The product's own rule overrides its family; the family only fills in the others.
    expect(
      Object.fromEntries(effective.map((e: any) => [e.name, e.source])),
    ).toEqual({
      "Serum Vitamin C": "PRODUCT",
      "Serum Niacinamide": "FAMILY",
      "Shampoo Argan": "NONE",
    });
  });

  it("values can change from one week to the next", async () => {
    const next = addDays(today(), 7);
    await w.a.post(
      "/v1/reward-rules",
      family(500, { endsOn: addDays(today(), 6) }),
    );
    await w.a.post("/v1/reward-rules", family(700, { startsOn: next }));
    const now = (await w.a.get(`/v1/reward-rules/effective?day=${today()}`))
      .body;
    const later = (await w.a.get(`/v1/reward-rules/effective?day=${next}`))
      .body;
    expect(
      now.find((e: any) => e.name === "Serum Niacinamide").amountMillimes,
    ).toBe(500);
    expect(
      later.find((e: any) => e.name === "Serum Niacinamide").amountMillimes,
    ).toBe(700);
    expect((await w.a.get("/v1/reward-rules?when=upcoming")).body).toHaveLength(
      1,
    );
  });

  it("refuses overlapping values unless asked to replace them", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const clash = await w.a.post(
      "/v1/reward-rules",
      family(900, { startsOn: addDays(today(), 3) }),
    );
    expect(clash.body.code).toBe("RULE_OVERLAP");
    const replaced = await w.a.post(
      "/v1/reward-rules",
      family(900, { startsOn: addDays(today(), 3), replaceOverlap: true }),
    );
    expect(replaced.status).toBe(201);
    const before = (
      await w.a.get(`/v1/reward-rules/effective?day=${addDays(today(), 2)}`)
    ).body;
    const after = (
      await w.a.get(`/v1/reward-rules/effective?day=${addDays(today(), 3)}`)
    ).body;
    expect(
      before.find((e: any) => e.name === "Serum Vitamin C").amountMillimes,
    ).toBe(500);
    expect(before.find((e: any) => e.name === "Serum Vitamin C").source).toBe(
      "FAMILY",
    );
    expect(
      after.find((e: any) => e.name === "Serum Vitamin C").amountMillimes,
    ).toBe(900);
  });

  it("belong to the admin alone", async () => {
    expect((await w.n.post("/v1/reward-rules", family(500))).status).toBe(403);
    expect((await w.n.get("/v1/reward-rules")).status).toBe(403);
    const { m } = await shop();
    expect((await m.get("/v1/reward-rules")).status).toBe(403);
  });
});

describe("recording a sale", () => {
  beforeEach(async () => {
    await w.a.post("/v1/reward-rules", family(500));
    await w.a.post("/v1/reward-rules", {
      scope: "PRODUCT",
      productId: w.products[0]!.id,
      amountMillimes: 800,
      startsOn: today(),
    });
  });

  it("pays the reward, lowers stock and shows the new totals", async () => {
    const { pdv, m } = await shop();
    const sale = await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [
        { productId: w.products[0]!.id, quantity: 2 },
        { productId: w.products[1]!.id, quantity: 1 },
      ],
    });
    expect(sale.status).toBe(201);
    expect(sale.body).toMatchObject({
      units: 3,
      rewardMillimes: 2100,
      replay: false,
      status: "ACTIVE",
    });
    expect(
      sale.body.lines
        .map((l: any) => [l.name, l.quantity, l.rewardMillimes])
        .sort((a: any[], b: any[]) => a[0].localeCompare(b[0])),
    ).toEqual([
      ["Serum Niacinamide", 1, 500],
      ["Serum Vitamin C", 2, 1600],
    ]);
    expect(sale.body.wallet).toMatchObject({
      balanceMillimes: 2100,
      availableMillimes: 2100,
      today: { sales: 1, units: 3, rewardMillimes: 2100 },
    });
    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 18,
      "Serum Niacinamide": 19,
    });
  });

  it("counts a retried sale only once", async () => {
    const { m } = await shop();
    const body = {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    };
    const first = await m.post("/v1/sales", body);
    const second = await m.post("/v1/sales", body);
    expect(second.body).toMatchObject({ replay: true, rewardMillimes: 800 });
    expect(second.body.wallet.balanceMillimes).toBe(
      first.body.wallet.balanceMillimes,
    );
    expect((await m.get("/v1/sales")).body.items).toHaveLength(1);
  });

  it("uses the value that applied on the day of the sale", async () => {
    const { m } = await shop();
    // The family pays 500 today; from tomorrow 5000. A sale made yesterday offline is paid at yesterday's value.
    await w.a.post(
      "/v1/reward-rules",
      family(5000, { startsOn: addDays(today(), 1), replaceOverlap: true }),
    );
    const yesterday = new Date(Date.now() - 86400_000);
    const old = await m.post("/v1/sales", {
      id: randomUUID(),
      occurredAt: yesterday,
      lines: [{ productId: w.products[1]!.id, quantity: 1 }],
    });
    expect(old.body.rewardMillimes).toBe(0); // no rule covered yesterday
    const now = await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[1]!.id, quantity: 1 }],
    });
    expect(now.body.rewardMillimes).toBe(500);
  });

  it("refuses dates in the future and unknown products", async () => {
    const { m } = await shop();
    const line = [{ productId: w.products[0]!.id, quantity: 1 }];
    expect(
      (
        await m.post("/v1/sales", {
          id: randomUUID(),
          occurredAt: new Date(Date.now() + 3600_000),
          lines: line,
        })
      ).body.code,
    ).toBe("INVALID_DATE");
    expect(
      (
        await m.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: randomUUID(), quantity: 1 }],
        })
      ).body.code,
    ).toBe("PRODUCT_NOT_FOUND");
    expect(
      (await m.post("/v1/sales", { id: randomUUID(), lines: [] })).status,
    ).toBe(400);
  });

  it("is only for team members of an active point of sale", async () => {
    const { pdv } = await shop();
    expect(
      (
        await w.n.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: w.products[0]!.id, quantity: 1 }],
        })
      ).status,
    ).toBe(403);
    await w.a.post(`/v1/pdvs/${pdv.id}/suspend`, {});
    const other = client(api, (await teamMember(w, pdv.id, "Other")).token);
    expect(
      (
        await other.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: w.products[0]!.id, quantity: 1 }],
        })
      ).body.code,
    ).toBe("PDV_INACTIVE");
  });
});

describe("correcting a sale", () => {
  beforeEach(async () => {
    await w.a.post("/v1/reward-rules", family(500));
    await w.a.post("/v1/reward-rules", {
      scope: "PRODUCT",
      productId: w.products[0]!.id,
      amountMillimes: 800,
      startsOn: today(),
    });
  });
  const sell = async (m: ReturnType<typeof client>) =>
    (
      await m.post("/v1/sales", {
        id: randomUUID(),
        lines: [
          { productId: w.products[0]!.id, quantity: 2 },
          { productId: w.products[1]!.id, quantity: 1 },
        ],
      })
    ).body;

  it("adjusts stock and the wallet, and keeps the history", async () => {
    const { pdv, m } = await shop();
    const sale = await sell(m);
    const fixed = await m.post(`/v1/sales/${sale.id}/correct`, {
      reason: "Only one serum was sold",
      lines: [
        { productId: w.products[0]!.id, quantity: 1 },
        { productId: w.products[1]!.id, quantity: 1 },
      ],
    });
    expect(fixed.body).toMatchObject({
      units: 2,
      rewardMillimes: 1300,
      version: 2,
    });
    expect(fixed.body.wallet.balanceMillimes).toBe(1300);
    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 19,
      "Serum Niacinamide": 19,
    });
    const detail = (await m.get(`/v1/sales/${sale.id}`)).body;
    expect(detail.revisions).toHaveLength(1);
    expect(detail.revisions[0]).toMatchObject({
      reason: "Only one serum was sold",
      version: 2,
    });
    const history = (await m.get("/v1/wallet/entries")).body.items.map(
      (e: any) => [e.kind, e.amountMillimes],
    );
    expect(history).toEqual([
      ["CORRECTION", -800],
      ["SALE", 2100],
    ]);
  });

  it("cancels a sale completely", async () => {
    const { pdv, m } = await shop();
    const sale = await sell(m);
    const voided = await m.post(`/v1/sales/${sale.id}/correct`, {
      reason: "Customer returned everything",
      lines: [],
    });
    expect(voided.body).toMatchObject({
      status: "VOIDED",
      units: 0,
      rewardMillimes: 0,
    });
    expect(voided.body.wallet.balanceMillimes).toBe(0);
    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 20,
      "Serum Niacinamide": 20,
    });
    expect(
      (
        await m.post(`/v1/sales/${sale.id}/correct`, {
          reason: "again",
          lines: [],
        })
      ).status,
    ).toBe(409);
  });

  it("is allowed to the responsable of the region, never to another region or another seller", async () => {
    const { pdv, m } = await shop();
    const sale = await sell(m);
    const correction = {
      reason: "Recount at the till",
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    };
    expect(
      (await w.s.post(`/v1/sales/${sale.id}/correct`, correction)).status,
    ).toBe(404);
    const colleague = client(
      api,
      (await teamMember(w, pdv.id, "Colleague")).token,
    );
    expect(
      (await colleague.post(`/v1/sales/${sale.id}/correct`, correction)).status,
    ).toBe(404);
    const byResponsable = await w.n.post(
      `/v1/sales/${sale.id}/correct`,
      correction,
    );
    expect(byResponsable.status).toBe(201);
    // The seller's wallet follows, and they are told.
    expect((await m.get("/v1/wallet")).body.balanceMillimes).toBe(800);
    const inbox = (await m.get("/v1/notifications")).body.items ?? [];
    expect(inbox.some((n: any) => n.key === "sale.corrected")).toBe(true);
  });

  it("closes to the seller after 48 hours but stays open to the responsable", async () => {
    const { m } = await shop();
    const sale = await sell(m);
    const { owner } = await import("./helpers");
    const db = await owner();
    await db.query(
      `UPDATE "Sale" SET "createdAt" = now() - interval '3 days' WHERE id=$1`,
      [sale.id],
    );
    await db.end();
    const fix = {
      reason: "Late fix",
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    };
    expect((await m.post(`/v1/sales/${sale.id}/correct`, fix)).body.code).toBe(
      "CORRECTION_WINDOW_CLOSED",
    );
    expect((await w.n.post(`/v1/sales/${sale.id}/correct`, fix)).status).toBe(
      201,
    );
  });
});

describe("what each role sees of sales", () => {
  it("a seller sees only their own, a responsable their region, the admin everything", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const north = await approvedPdv(w, "n", "Para Nord");
    const south = await approvedPdv(w, "s", "Para Sud");
    await stockPlace(w, north.id, w.nord, [10, 10, 10]);
    await stockPlace(w, south.id, w.sud, [10, 10, 10]);
    const a = client(api, (await teamMember(w, north.id, "Anis")).token);
    const b = client(api, (await teamMember(w, north.id, "Bilel")).token);
    const c = client(api, (await teamMember(w, south.id, "Chiraz")).token);
    for (const who of [a, b, c])
      await who.post("/v1/sales", {
        id: randomUUID(),
        lines: [{ productId: w.products[1]!.id, quantity: 1 }],
      });
    expect((await a.get("/v1/sales")).body.items).toHaveLength(1);
    expect((await w.n.get("/v1/sales")).body.items).toHaveLength(2);
    expect((await w.s.get("/v1/sales")).body.items).toHaveLength(1);
    expect((await w.a.get("/v1/sales")).body.items).toHaveLength(3);
    expect(
      (await w.a.get(`/v1/sales?regionId=${south.regionId}`)).body.items,
    ).toHaveLength(1);
  });
});

describe("wallet and payouts", () => {
  beforeEach(async () => {
    await w.a.post("/v1/reward-rules", family(1000));
  });
  const earn = async (m: ReturnType<typeof client>, units: number) =>
    m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[1]!.id, quantity: units }],
    });

  it("deducts a payout only when the admin approves it", async () => {
    const { m } = await shop();
    await earn(m, 5); // 5 000 millimes
    expect((await m.get("/v1/wallet")).body).toMatchObject({
      balanceMillimes: 5000,
      availableMillimes: 5000,
    });
    const tooMuch = await m.post("/v1/payouts", { amountMillimes: 6000 });
    expect(tooMuch.body.code).toBe("INSUFFICIENT_BALANCE");
    const request = (await m.post("/v1/payouts", { amountMillimes: 3000 }))
      .body;
    expect(request.status).toBe("PENDING");
    // The requested amount is held, but the balance has not moved yet.
    expect((await m.get("/v1/wallet")).body).toMatchObject({
      balanceMillimes: 5000,
      pendingPayoutMillimes: 3000,
      availableMillimes: 2000,
    });
    expect(
      (await m.post("/v1/payouts", { amountMillimes: 2500 })).body.code,
    ).toBe("INSUFFICIENT_BALANCE");

    const approved = await w.a.post(`/v1/payouts/${request.id}/approve`, {
      reference: "CASH-001",
    });
    expect(approved.body).toMatchObject({
      status: "APPROVED",
      reference: "CASH-001",
      user: { name: "Karim" },
    });
    expect((await m.get("/v1/wallet")).body).toMatchObject({
      balanceMillimes: 2000,
      pendingPayoutMillimes: 0,
      availableMillimes: 2000,
    });
    expect((await m.get("/v1/wallet/entries")).body.items[0]).toMatchObject({
      kind: "PAYOUT",
      amountMillimes: -3000,
    });
    expect(
      (await w.a.post(`/v1/payouts/${request.id}/approve`, {})).status,
    ).toBe(409);
  });

  it("releases the held amount when a payout is rejected or cancelled", async () => {
    const { m } = await shop();
    await earn(m, 4);
    const first = (await m.post("/v1/payouts", { amountMillimes: 4000 })).body;
    await w.a.post(`/v1/payouts/${first.id}/reject`, {
      note: "Come back on Friday",
    });
    expect((await m.get("/v1/wallet")).body.availableMillimes).toBe(4000);
    const second = (await m.post("/v1/payouts", { amountMillimes: 1000 })).body;
    expect((await m.post(`/v1/payouts/${second.id}/cancel`)).body.status).toBe(
      "CANCELLED",
    );
    expect((await m.get("/v1/wallet")).body.availableMillimes).toBe(4000);
    expect((await m.get("/v1/payouts")).body).toHaveLength(2);
  });

  it("won't pay out money a correction has since taken back", async () => {
    const { m } = await shop();
    const sale = (await earn(m, 4)).body; // 4 000
    const request = (await m.post("/v1/payouts", { amountMillimes: 4000 }))
      .body;
    await m.post(`/v1/sales/${sale.id}/correct`, {
      reason: "Wrong count",
      lines: [{ productId: w.products[1]!.id, quantity: 1 }],
    });
    const approve = await w.a.post(`/v1/payouts/${request.id}/approve`, {});
    expect(approve.body.code).toBe("INSUFFICIENT_BALANCE");
  });

  it("gives the admin an overview of every wallet, and nobody else", async () => {
    const { m } = await shop();
    await earn(m, 3);
    const overview = (await w.a.get("/v1/wallets")).body;
    expect(overview).toEqual([
      expect.objectContaining({
        name: "Karim",
        balance: 3000,
        earned: 3000,
        paid: 0,
        availableMillimes: 3000,
      }),
    ]);
    expect((await w.n.get("/v1/wallets")).status).toBe(403);
    expect((await w.n.get("/v1/payouts")).status).toBe(403);
  });

  it("keeps each person's wallet private", async () => {
    const { pdv, m } = await shop();
    await earn(m, 2);
    const other = client(
      api,
      (await createAccount({ role: "VENDEUR", pdvId: pdv.id })).token,
    );
    expect((await other.get("/v1/wallet")).body.balanceMillimes).toBe(0);
    expect((await other.get("/v1/wallet/entries")).body.items).toHaveLength(0);
  });
});

describe("sale notifications", () => {
  it("tell the responsable of the region about every sale, and nobody else", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const { m } = await shop();
    const sale = await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 2 }],
    });
    expect(sale.status).toBe(201);
    const inbox = (await w.n.get("/v1/notifications")).body.items;
    const notice = inbox.find((n: any) => n.key === "sale.recorded");
    expect(notice.params).toMatchObject({ units: 2, amountMillimes: 1000 });
    const other = (await w.s.get("/v1/notifications")).body.items;
    expect(other.some((n: any) => n.key === "sale.recorded")).toBe(false);
  });
});

describe("reading the history", () => {
  it("gives one line per day, filters by product and date, and never mixes in other people's days", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const { m } = await shop();
    for (const [product, quantity] of [
      [0, 2],
      [1, 1],
    ] as const)
      await m.post("/v1/sales", {
        id: randomUUID(),
        lines: [{ productId: w.products[product]!.id, quantity }],
      });
    const days = (
      await m.get(`/v1/sales/days?from=${addDays(today(), -30)}&to=${today()}`)
    ).body;
    expect(days).toEqual([
      { day: today(), sales: 2, units: 3, rewardMillimes: 1500 },
    ]);
    const onlyVitaminC = (
      await m.get(
        `/v1/sales?productId=${w.products[0]!.id}&from=${today()}&to=${today()}`,
      )
    ).body.items;
    expect(onlyVitaminC).toHaveLength(1);
    const { m: other } = await shop("s");
    expect(
      (await other.get(`/v1/sales/days?from=${today()}&to=${today()}`)).body,
    ).toEqual([]);
  });

  it("compares a report with the period before and returns a daily trend", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const { m } = await shop();
    await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 2 }],
    });
    const report = (
      await w.a.get(
        `/v1/reports/sales?groupBy=product&from=${addDays(today(), -6)}&to=${today()}`,
      )
    ).body;
    expect(report.totals.units).toBe(2);
    expect(report.previous).toEqual({
      sales: 0,
      units: 0,
      rewardMillimes: 0,
    });
    expect(report.trend).toHaveLength(7);
    expect(report.trend.at(-1)).toEqual({
      day: today(),
      units: 2,
      sales: 1,
    });
    expect(report.rows[0]).toHaveProperty("imageId");
  });
});

describe("notification filters", () => {
  it("narrow the inbox by kind of notification and by unread", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const { m } = await shop();
    await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    });
    const all = (await w.n.get("/v1/notifications")).body.items;
    expect(all.length).toBeGreaterThan(1);
    const sales = (await w.n.get("/v1/notifications?category=SALES")).body
      .items;
    expect(sales.every((n: any) => n.key === "sale.recorded")).toBe(true);
    expect(sales).toHaveLength(1);
    const stock = (await w.n.get("/v1/notifications?category=STOCK")).body
      .items;
    expect(stock.some((n: any) => n.key === "sale.recorded")).toBe(false);
    await w.n.post(`/v1/notifications/${sales[0].id}/read`);
    expect(
      (await w.n.get("/v1/notifications?category=SALES&unreadOnly=true")).body
        .items,
    ).toEqual([]);
  });
});

describe("the same sale sent many times at once", () => {
  it("is recorded once, and every sender gets the receipt", async () => {
    await w.a.post("/v1/reward-rules", family(500));
    const { m, pdv } = await shop();
    const id = randomUUID();
    const sends = await Promise.all(
      Array.from({ length: 25 }, () =>
        m.post("/v1/sales", {
          id,
          lines: [{ productId: w.products[0]!.id, quantity: 2 }],
        }),
      ),
    );
    expect(sends.every((s) => [200, 201].includes(s.status))).toBe(true);
    expect(sends.filter((s) => s.body.replay === false)).toHaveLength(1);
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(18);
    expect((await m.get("/v1/wallet")).body.balanceMillimes).toBe(1000);
  });
});
