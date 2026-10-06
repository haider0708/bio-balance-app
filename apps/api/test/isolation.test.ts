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

/** Everything one region owns, so we can look for it in what another region receives. */
async function nordWorld() {
  await w.a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Serums",
    amountMillimes: 500,
    startsOn: today(),
  });
  const pdv = await approvedPdv(w, "n", "Magasin Secret Nord");
  await stockPlace(w, pdv.id, w.nord, [20, 20, 20]);
  const seller = await teamMember(w, pdv.id, "Vendeur Secret Nord");
  const m = client(api, seller.token);
  const sale = await m.post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[0]!.id, quantity: 3 }],
  });
  const order = (
    await w.n.post("/v1/restocks", {
      destId: pdv.id,
      lines: [{ productId: w.products[1]!.id, quantity: 4 }],
    })
  ).body;
  await w.a.post(`/v1/restocks/${order.id}/assign`, { depotId: w.depotId });
  const group = (await w.n.post("/v1/groups", { name: "Groupe Secret Nord" }))
    .body;
  return { pdv, seller, m, saleId: sale.body.id, order, group };
}

describe("regions never see each other's data", () => {
  it("a responsable of another region receives nothing from this one, on any screen", async () => {
    const nord = await nordWorld();
    const secrets = [
      nord.pdv.id,
      "Magasin Secret Nord",
      "Vendeur Secret Nord",
      nord.saleId,
      nord.order.id,
      nord.order.number,
      nord.group.id,
      "Groupe Secret Nord",
      w.depotId, // the grossiste of Nord
      "Depot Hedi",
      nord.seller.id,
    ];
    const routes = [
      "/v1/pdvs",
      "/v1/groups",
      "/v1/users",
      "/v1/depots",
      "/v1/sales",
      `/v1/sales/days?from=${addDays(today(), -30)}&to=${today()}`,
      "/v1/restocks",
      "/v1/stock/declarations",
      "/v1/notifications",
      "/v1/wallet",
      "/v1/payouts",
      "/v1/dashboard",
      `/v1/reports/sales?groupBy=pdv&from=${addDays(today(), -30)}&to=${today()}`,
      `/v1/reports/sales?groupBy=product&from=${addDays(today(), -30)}&to=${today()}`,
      "/v1/reports/stock",
      "/v1/reports/stock/attention",
    ];
    for (const route of routes) {
      const res = await w.s.get(route);
      const text = JSON.stringify(res.body);
      for (const secret of secrets)
        expect(text, `${route} must not contain ${secret}`).not.toContain(
          secret,
        );
    }
    // And by id: it simply does not exist for them.
    for (const route of [
      `/v1/pdvs/${nord.pdv.id}`,
      `/v1/sales/${nord.saleId}`,
      `/v1/restocks/${nord.order.id}`,
      `/v1/stock/locations/${nord.pdv.id}`,
      `/v1/users/${nord.seller.id}`,
    ])
      expect([404, 403], route).toContain((await w.s.get(route)).status);
  });

  it("a team member sees only their own sales, and a grossiste only their own orders", async () => {
    const nord = await nordWorld();
    const sud = await approvedPdv(w, "s", "Magasin Sud");
    await stockPlace(w, sud.id, w.sud, [20, 20, 20]);
    const seller = client(
      api,
      (await teamMember(w, sud.id, "Vendeur Sud")).token,
    );
    await seller.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    });
    const mine = (await seller.get("/v1/sales")).body.items;
    expect(mine).toHaveLength(1);
    expect(JSON.stringify(mine)).not.toContain(nord.saleId);
    expect([403, 404]).toContain(
      (await seller.get(`/v1/sales/${nord.saleId}`)).status,
    );
    expect([403, 404]).toContain(
      (await seller.get(`/v1/stock/locations/${nord.pdv.id}`)).status,
    );

    const other = await createAccount({
      role: "GROSSISTE",
      regionCode: "SUD",
      name: "Slim",
      depot: { name: "Depot Sud" },
    });
    const g = client(api, other.token);
    expect(JSON.stringify((await g.get("/v1/restocks")).body)).not.toContain(
      nord.order.id,
    );
    expect([403, 404]).toContain(
      (await g.get(`/v1/restocks/${nord.order.id}`)).status,
    );
    expect([403, 404]).toContain(
      (await g.get(`/v1/stock/locations/${w.depotId}`)).status,
    );
  });
});
