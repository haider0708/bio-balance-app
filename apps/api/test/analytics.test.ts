import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { client, resetDatabase, startApi, type Api } from "./helpers";
import {
  approvedPdv,
  buildWorld,
  stockPlace,
  teamMember,
  type World,
} from "./world";
import { addDays, tunisDay } from "../src/core/dates";

let api: Api;
let w: World;
const today = () => tunisDay(new Date());
const day = `from=${tunisDay(new Date())}&to=${tunisDay(new Date())}`;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

/** Two stores in two regions: Nord sells 8 units in two sales (Anis), Sud 4 in one (Chiraz). */
async function network() {
  await w.a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Serums",
    amountMillimes: 500,
    startsOn: today(),
  });
  const north = await approvedPdv(w, "n", "Para Nord");
  const south = await approvedPdv(w, "s", "Para Sud");
  await stockPlace(w, north.id, w.nord, [10, 30, 30]);
  await stockPlace(w, south.id, w.sud, [30, 30, 30]);
  const anis = await teamMember(w, north.id, "Anis");
  const chiraz = await teamMember(w, south.id, "Chiraz");
  const a = client(api, anis.token);
  const c = client(api, chiraz.token);
  const first = randomUUID();
  await a.post("/v1/sales", {
    id: first,
    lines: [
      { productId: w.products[0]!.id, quantity: 5 },
      { productId: w.products[2]!.id, quantity: 1 },
    ],
  });
  await a.post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[1]!.id, quantity: 2 }],
  });
  await c.post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[1]!.id, quantity: 4 }],
  });
  return { north, south, a, c, anis, chiraz, first };
}

const names = (rows: any[]) => rows.map((r) => [r.name, r.units]);

describe("analytics overview", () => {
  it("explains a day of the whole network: totals, hours, and every ranking", async () => {
    await network();
    const r = (await w.a.get(`/v1/analytics/overview?${day}`)).body;
    expect(r.granularity).toBe("hour");
    expect(r.totals).toMatchObject({
      sales: 3,
      units: 12,
      rewardMillimes: 5500,
      stores: 2,
      sellers: 2,
      products: 3,
      silentStores: 0,
      voided: 0,
      corrected: 0,
    });
    expect(r.change.units).toBeNull();
    expect(r.series).toHaveLength(24);
    expect(r.series.reduce((t: number, h: any) => t + h.units, 0)).toBe(12);
    expect(r.hours.reduce((t: number, h: any) => t + h.units, 0)).toBe(12);
    expect(names(r.breakdowns.regions)).toEqual([
      ["Nord", 8],
      ["Sud", 4],
    ]);
    expect(names(r.breakdowns.stores)).toEqual([
      ["Para Nord", 8],
      ["Para Sud", 4],
    ]);
    expect(r.breakdowns.stores[0].sub).toBe("Tunis");
    expect(names(r.breakdowns.sellers)).toEqual([
      ["Anis", 8],
      ["Chiraz", 4],
    ]);
    expect(r.breakdowns.sellers[0].sub).toBe("Para Nord");
    expect(names(r.breakdowns.products)).toEqual([
      ["Serum Niacinamide", 6],
      ["Serum Vitamin C", 5],
      ["Shampoo Argan", 1],
    ]);
    expect(names(r.breakdowns.families)).toEqual([
      ["Serums", 11],
      ["Hair", 1],
    ]);
    expect(r.stock.kind).toBe("network");
    expect(r.money.owedMillimes).toBe(5500);
    expect(r.insights.map((i: any) => i.key)).toEqual(
      expect.arrayContaining(["TOP_FAMILY", "BEST_HOUR", "TOP_SELLER"]),
    );
  });

  it("matches the dashboard's numbers for the same day", async () => {
    await network();
    const dash = (await w.a.get("/v1/dashboard")).body;
    const r = (await w.a.get(`/v1/analytics/overview?${day}`)).body;
    expect(dash.today).toBe(today());
    expect(r.totals.units).toBe(dash.sales.today.units);
    expect(r.totals.sales).toBe(dash.sales.today.sales);
  });

  it("follows a product: where it sold, who sold it, and where its stock sits", async () => {
    const { north, south } = await network();
    const r = (
      await w.a.get(
        `/v1/analytics/overview?${day}&productId=${w.products[1]!.id}`,
      )
    ).body;
    expect(r.subject.product).toMatchObject({
      name: "Serum Niacinamide",
      family: "Serums",
    });
    expect(r.totals).toMatchObject({ units: 6, sales: 2 });
    expect(r.breakdowns.products).toBeUndefined();
    expect(r.breakdowns.families).toBeUndefined();
    expect(names(r.breakdowns.stores)).toEqual([
      ["Para Sud", 4],
      ["Para Nord", 2],
    ]);
    expect(r.stock.kind).toBe("product");
    expect(
      r.stock.rows
        .filter((s: any) => s.kind === "PDV")
        .map((s: any) => [s.locationId, s.quantity]),
    ).toEqual([
      [south.id, 26],
      [north.id, 28],
    ]);
    expect(r.stock.total).toBe(54);
    expect(
      r.stock.rows.find((s: any) => s.locationId === south.id).perDay,
    ).toBe(0.1);
  });

  it("follows a store: what it sells, who sells, and how long its stock lasts", async () => {
    const { north } = await network();
    const r = (await w.a.get(`/v1/analytics/overview?${day}&pdvId=${north.id}`))
      .body;
    expect(r.subject.pdv).toMatchObject({
      name: "Para Nord",
      region: "Nord",
      members: 1,
    });
    expect(r.totals).toMatchObject({ units: 8, sales: 2 });
    expect(r.breakdowns.stores).toBeUndefined();
    expect(r.breakdowns.regions).toBeUndefined();
    expect(names(r.breakdowns.sellers)).toEqual([["Anis", 8]]);
    expect(r.stock.kind).toBe("store");
    // Vitamin C: 5 left, 5 sold in four weeks: about a month.
    expect(
      r.stock.rows.find((s: any) => s.name === "Serum Vitamin C"),
    ).toMatchObject({ quantity: 5, daysLeft: 28 });
  });

  it("follows a seller, a group and a family", async () => {
    const { north, anis } = await network();
    const seller = (
      await w.a.get(`/v1/analytics/overview?${day}&sellerId=${anis.id}`)
    ).body;
    expect(seller.subject.seller).toMatchObject({
      name: "Anis",
      pdv: "Para Nord",
    });
    expect(seller.totals.units).toBe(8);
    expect(seller.breakdowns.sellers).toBeUndefined();
    expect(seller.stock).toBeNull();
    expect(seller.money.owedMillimes).toBe(3500);

    const group = (await w.n.post("/v1/groups", { name: "Groupe N" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    await w.n.patch(`/v1/pdvs/${north.id}`, { groupId: group.id });
    const byGroup = (
      await w.a.get(`/v1/analytics/overview?${day}&groupId=${group.id}`)
    ).body;
    expect(byGroup.subject.group).toMatchObject({
      name: "Groupe N",
      stores: 1,
    });
    expect(byGroup.totals.units).toBe(8);
    expect(names(byGroup.breakdowns.stores)).toEqual([["Para Nord", 8]]);
    expect(
      names(
        (await w.a.get(`/v1/analytics/overview?${day}`)).body.breakdowns.groups,
      ),
    ).toEqual([["Groupe N", 8]]);

    const hair = (await w.a.get(`/v1/analytics/overview?${day}&family=Hair`))
      .body;
    expect(hair.totals).toMatchObject({ units: 1, sales: 1 });
    expect(names(hair.breakdowns.products)).toEqual([["Shampoo Argan", 1]]);
    expect(hair.breakdowns.families).toBeUndefined();
  });

  it("ranks by the measure asked for", async () => {
    await network();
    const r = (await w.a.get(`/v1/analytics/overview?${day}&sort=reward`)).body;
    expect(
      r.breakdowns.products.map((p: any) => [p.name, p.rewardMillimes]),
    ).toEqual([
      ["Serum Niacinamide", 3000],
      ["Serum Vitamin C", 2500],
      ["Shampoo Argan", 0],
    ]);
  });

  it("compares with the period before and draws days over a longer period", async () => {
    await network();
    const from = addDays(today(), -13);
    const r = (
      await w.a.get(`/v1/analytics/overview?from=${from}&to=${today()}`)
    ).body;
    expect(r.granularity).toBe("day");
    expect(r.series).toHaveLength(14);
    expect(r.series.at(-1)).toMatchObject({ key: today(), units: 12 });
    expect(r.previous.to).toBe(addDays(from, -1));
    const long = (
      await w.a.get(
        `/v1/analytics/overview?from=${addDays(today(), -120)}&to=${today()}`,
      )
    ).body;
    expect(long.granularity).toBe("week");
    expect(long.series.reduce((t: number, p: any) => t + p.units, 0)).toBe(12);
  });

  it("counts voided and corrected sales so nothing is hidden", async () => {
    const { a, first } = await network();
    await a.post(`/v1/sales/${first}/correct`, {
      reason: "Wrong quantity",
      lines: [{ productId: w.products[0]!.id, quantity: 4 }],
    });
    const r = (await w.a.get(`/v1/analytics/overview?${day}`)).body;
    expect(r.totals).toMatchObject({ units: 10, corrected: 1, voided: 0 });
    await a.post(`/v1/sales/${first}/correct`, {
      reason: "Not sold after all",
      lines: [],
    });
    const after = (await w.a.get(`/v1/analytics/overview?${day}`)).body;
    expect(after.totals).toMatchObject({ units: 6, sales: 2, voided: 1 });
  });

  it("keeps a responsable to their region and hides the money", async () => {
    const { south } = await network();
    const sudId = south.regionId;
    const mine = (
      await w.n.get(`/v1/analytics/overview?${day}&regionId=${sudId}`)
    ).body;
    expect(mine.totals.units).toBe(8);
    expect(mine.breakdowns.regions).toBeUndefined();
    expect(names(mine.breakdowns.stores)).toEqual([["Para Nord", 8]]);
    expect(mine.money).toBeNull();
    expect(
      (await w.n.get(`/v1/analytics/overview?${day}&pdvId=${south.id}`)).status,
    ).toBe(404);
  });
});

describe("store board", () => {
  it("lists every store of the scope, the silent ones too", async () => {
    await network();
    await w.n.post("/v1/pdvs", {
      name: "Para Waiting",
      address: "1 rue",
      city: "Bizerte",
    });
    await approvedPdv(w, "n", "Para Quiet");
    const r = (await w.a.get(`/v1/analytics/stores?${day}`)).body;
    expect(r.summary).toMatchObject({
      total: 4,
      active: 3,
      pending: 1,
      selling: 2,
      silent: 1,
    });
    expect(r.rows[0]).toMatchObject({
      name: "Para Nord",
      units: 8,
      sales: 2,
      sellers: 1,
      members: 1,
      region: "Nord",
    });
    expect(r.rows[0].lastSaleAt).not.toBeNull();
    const nord = (await w.n.get(`/v1/analytics/stores?${day}`)).body;
    expect(nord.rows.map((s: any) => s.name).sort()).toEqual([
      "Para Nord",
      "Para Quiet",
      "Para Waiting",
    ]);
    const overview = (await w.n.get(`/v1/analytics/overview?${day}`)).body;
    expect(overview.totals.silentStores).toBe(1);
  });
});

describe("sales ledger and export", () => {
  it("filters the sales behind any number: family, group, status", async () => {
    const { north, a, first } = await network();
    const hair = (await w.a.get(`/v1/sales?${day}&family=Hair`)).body;
    expect(hair.items.map((s: any) => s.id)).toEqual([first]);
    const group = (await w.n.post("/v1/groups", { name: "Groupe N" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    await w.n.patch(`/v1/pdvs/${north.id}`, { groupId: group.id });
    expect(
      (await w.a.get(`/v1/sales?${day}&groupId=${group.id}`)).body.items,
    ).toHaveLength(2);
    await a.post(`/v1/sales/${first}/correct`, { reason: "Oops", lines: [] });
    const voided = (await w.a.get(`/v1/sales?${day}&status=VOIDED`)).body;
    expect(voided.items.map((s: any) => s.id)).toEqual([first]);
  });

  it("exports exactly the lens on screen", async () => {
    await network();
    const res = await fetch(
      `${api.url}/v1/reports/sales.csv?${day}&productId=${w.products[2]!.id}`,
      { headers: { Authorization: `Bearer ${w.admin.token}` } },
    );
    const lines = (await res.text()).trim().split("\r\n");
    expect(lines).toHaveLength(2);
    expect(lines[1]).toContain("Shampoo Argan");
  });
});
