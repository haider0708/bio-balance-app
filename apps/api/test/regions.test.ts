import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  client,
  createAccount,
  owner,
  regionId,
  resetDatabase,
  startApi,
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

let api: Api;
let w: World;

beforeAll(async () => {
  api = await startApi();
});
afterAll(async () => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

const names = (rows: { name: string }[]) => rows.map((r) => r.name).sort();

describe("regions", () => {
  it("the admin names them, creates them, and sees who looks after each", async () => {
    const overview = (await w.a.get("/v1/regions/overview")).body;
    expect(names(overview)).toEqual(["Centre", "Nord", "Sud"]);
    const nord = overview.find((r: any) => r.name === "Nord");
    expect(nord).toMatchObject({
      responsable: { name: "Nora Nord" },
      grossistes: 1,
      deletable: false,
    });
    expect(overview.find((r: any) => r.name === "Centre")).toMatchObject({
      responsable: null,
      deletable: true,
    });

    const made = await w.a.post("/v1/regions", { name: "Grand Tunis" });
    expect(made.status).toBe(201);
    expect(made.body.code).toBe("GRAND-TUNIS");
    expect(
      (await w.a.post("/v1/regions", { name: "grand tunis" })).body.code,
    ).toBe("REGION_NAME_TAKEN");
    const renamed = await w.a.patch(`/v1/regions/${made.body.id}`, {
      name: "Tunis Capitale",
    });
    expect(renamed.body.name).toBe("Tunis Capitale");
    expect(
      (await w.a.patch(`/v1/regions/${made.body.id}`, { name: "Nord" })).status,
    ).toBe(409);
    // Only the admin manages regions.
    expect((await w.n.post("/v1/regions", { name: "X" })).status).toBe(403);
    expect((await w.n.get("/v1/regions/overview")).status).toBe(403);
    expect(
      (await w.n.patch(`/v1/regions/${made.body.id}`, { name: "Y" })).status,
    ).toBe(403);
  });

  it("deletes a region only when nothing is left in it", async () => {
    const nord = await regionId("NORD");
    const refused = await w.a.delete(`/v1/regions/${nord}`);
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("REGION_NOT_EMPTY");
    const made = (await w.a.post("/v1/regions", { name: "Temporaire" })).body;
    expect((await w.a.delete(`/v1/regions/${made.id}`)).status).toBe(200);
    expect(names((await w.a.get("/v1/regions")).body)).not.toContain(
      "Temporaire",
    );
  });
});

describe("responsables", () => {
  it("can be created for a region, and moved: into an empty region, or swapped with the one there", async () => {
    const centre = await regionId("CENTRE");
    const created = await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: centre,
      name: "Cyrine Centre",
      email: "cyrine@example.test",
    });
    expect(created.status).toBe(201);
    // A region has one responsable.
    expect(
      (
        await w.a.post("/v1/users", {
          role: "RESPONSABLE",
          regionId: centre,
          name: "Second",
          email: "second@example.test",
        })
      ).body.code,
    ).toBe("REGION_HAS_RESPONSABLE");

    const nord = await regionId("NORD");
    const sud = await regionId("SUD");
    // Nora (Nord) wants Sud, where Sami is: not without an explicit swap.
    const refused = await w.a.post(`/v1/users/${w.nord.id}/move`, {
      regionId: sud,
    });
    expect(refused.body.code).toBe("REGION_HAS_RESPONSABLE");
    const swapped = await w.a.post(`/v1/users/${w.nord.id}/move`, {
      regionId: sud,
      swap: true,
    });
    expect(swapped.status).toBe(201);
    expect((await w.n.get("/v1/me")).body.region.name).toBe("Sud");
    expect((await w.s.get("/v1/me")).body.region.name).toBe("Nord");
    // Each sees the other region's depot now: Nord's grossiste belongs to whoever is in Nord.
    expect((await w.s.get("/v1/depots")).body.map((d: any) => d.name)).toEqual([
      "Depot Hedi",
    ]);
    expect((await w.n.get("/v1/depots")).body).toEqual([]);
    expect(
      (await w.a.post(`/v1/users/${w.nord.id}/move`, { regionId: sud })).body
        .code,
    ).toBe("SAME_REGION");
    // Into an empty region: simply moves.
    const empty = (await w.a.post("/v1/regions", { name: "Sahel" })).body.id;
    expect(
      (await w.a.post(`/v1/users/${w.nord.id}/move`, { regionId: empty }))
        .status,
    ).toBe(201);
    expect(nord).toBeDefined();
    // Vendeurs and other roles cannot be moved this way; only the admin moves.
    const pdv = await approvedPdv(w, "n");
    const member = await teamMember(w, pdv.id);
    expect(
      (await w.a.post(`/v1/users/${member.id}/move`, { regionId: sud })).body
        .code,
    ).toBe("NOT_A_RESPONSABLE");
    expect(
      (await w.n.post(`/v1/users/${w.sud.id}/move`, { regionId: empty }))
        .status,
    ).toBe(403);
  });

  it("a suspended responsable can be moved away, which frees the region to be deleted", async () => {
    const centre = await regionId("CENTRE");
    const created = (
      await w.a.post("/v1/users", {
        role: "RESPONSABLE",
        regionId: centre,
        name: "Cyrine Centre",
        email: "cyrine@example.test",
      })
    ).body;
    expect((await w.a.delete(`/v1/regions/${centre}`)).body.code).toBe(
      "REGION_NOT_EMPTY",
    );
    await w.a.post(`/v1/users/${created.id}/suspend`, { note: "left" });
    const nord = await regionId("NORD");
    expect(
      (await w.a.post(`/v1/users/${created.id}/move`, { regionId: nord }))
        .status,
    ).toBe(201);
    expect((await w.a.delete(`/v1/regions/${centre}`)).status).toBe(200);
  });
});

describe("moving a store", () => {
  async function busyStore() {
    const pdv = await approvedPdv(w, "n", "Para Lac");
    await stockPlace(w, pdv.id, w.nord, [20, 20, 20]);
    const seller = await teamMember(w, pdv.id, "Karim");
    const m = client(api, seller.token);
    const sale = await m.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 3 }],
    });
    expect(sale.status).toBe(201);
    return { pdv, seller, m, sale: sale.body };
  }

  it("takes its team, stock, sales and history to the new region and out of the old one", async () => {
    const { pdv, m, sale } = await busyStore();
    const sud = await regionId("SUD");
    const moved = await w.a.post(`/v1/pdvs/${pdv.id}/move`, { regionId: sud });
    expect(moved.status).toBe(201);

    expect((await w.s.get(`/v1/pdvs/${pdv.id}`)).body.name).toBe("Para Lac");
    expect((await w.n.get(`/v1/pdvs/${pdv.id}`)).status).toBe(404);
    expect(
      ((await w.s.get("/v1/sales")).body.items as any[]).map((x) => x.id),
    ).toContain(sale.id);
    expect(JSON.stringify((await w.n.get("/v1/sales")).body)).not.toContain(
      sale.id,
    );
    expect((await w.s.get(`/v1/stock/locations/${pdv.id}`)).status).toBe(200);
    expect((await w.n.get(`/v1/stock/locations/${pdv.id}`)).status).toBe(404);
    // The movement history followed, and the stock itself did not change.
    const movements = await w.s.get(
      `/v1/stock/locations/${pdv.id}/products/${w.products[0]!.id}/movements`,
    );
    expect(movements.body.length).toBeGreaterThanOrEqual(2);
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(17);
    // The team member keeps working, now in Sud.
    expect((await m.get("/v1/me")).body.region.name).toBe("Sud");
    expect(
      (
        await m.post("/v1/sales", {
          id: randomUUID(),
          lines: [{ productId: w.products[1]!.id, quantity: 1 }],
        })
      ).status,
    ).toBe(201);
    // Reports by region follow.
    const day = new Date().toISOString().slice(0, 10);
    const q = `from=${day}&to=${day}`;
    const byRegion = (await w.a.get(`/v1/reports/sales?groupBy=region&${q}`))
      .body;
    expect(byRegion.rows.map((r: any) => [r.label, r.units])).toEqual([
      ["Sud", 4],
    ]);
    // Both responsables were told.
    expect(
      (await w.s.get("/v1/notifications")).body.items.map((n: any) => n.key),
    ).toContain("pdv.moved.in");
    expect(
      (await w.n.get("/v1/notifications")).body.items.map((n: any) => n.key),
    ).toContain("pdv.moved.out");
  });

  it("leaves its group, or joins one of the new region; refuses a group of the wrong region", async () => {
    const pdv = await approvedPdv(w, "n");
    const sud = await regionId("SUD");
    const groupN = (
      await w.a.post("/v1/groups", {
        name: "Groupe Nord",
        regionId: await regionId("NORD"),
      })
    ).body;
    const groupS = (
      await w.a.post("/v1/groups", { name: "Groupe Sud", regionId: sud })
    ).body;
    await w.a.patch(`/v1/pdvs/${pdv.id}`, { groupId: groupN.id });
    expect(
      (
        await w.a.post(`/v1/pdvs/${pdv.id}/move`, {
          regionId: sud,
          groupId: groupN.id,
        })
      ).body.code,
    ).toBe("GROUP_OTHER_REGION");
    await w.a.post(`/v1/pdvs/${pdv.id}/move`, {
      regionId: sud,
      groupId: groupS.id,
    });
    expect((await w.a.get(`/v1/pdvs/${pdv.id}`)).body.groupId).toBe(groupS.id);
    await w.a.post(`/v1/pdvs/${pdv.id}/move`, {
      regionId: await regionId("NORD"),
    });
    expect((await w.a.get(`/v1/pdvs/${pdv.id}`)).body.groupId).toBeNull();
  });

  it("is refused while a delivery or a count is still open, and only the admin can do it", async () => {
    const pdv = await approvedPdv(w, "n");
    await stockPlace(w, pdv.id, w.nord, [5, 5, 5]);
    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 2 }],
      })
    ).body;
    const sud = await regionId("SUD");
    const blocked = await w.a.post(`/v1/pdvs/${pdv.id}/move`, {
      regionId: sud,
    });
    expect(blocked.status).toBe(409);
    expect(blocked.body.code).toBe("REGION_MOVE_BLOCKED");
    expect(
      (await w.n.post(`/v1/pdvs/${pdv.id}/move`, { regionId: sud })).status,
    ).toBe(403);
    await w.a.post(`/v1/restocks/${order.id}/cancel`, { note: "not needed" });
    expect(
      (await w.a.post(`/v1/pdvs/${pdv.id}/move`, { regionId: sud })).status,
    ).toBe(201);
    expect(
      (await w.a.post(`/v1/pdvs/${pdv.id}/move`, { regionId: sud })).body.code,
    ).toBe("SAME_REGION");
  });

  it("empties a region so it can be deleted", async () => {
    const pdv = await approvedPdv(w, "n");
    await stockPlace(w, pdv.id, w.nord, [3, 3, 3]);
    const made = (await w.a.post("/v1/regions", { name: "Temporaire" })).body;
    await w.a.post(`/v1/pdvs/${pdv.id}/move`, { regionId: made.id });
    expect((await w.a.delete(`/v1/regions/${made.id}`)).body.code).toBe(
      "REGION_NOT_EMPTY",
    );
    await w.a.post(`/v1/pdvs/${pdv.id}/move`, {
      regionId: await regionId("SUD"),
    });
    expect((await w.a.delete(`/v1/regions/${made.id}`)).status).toBe(200);
  });
});

describe("moving a group and a grossiste", () => {
  it("a group takes all of its stores along", async () => {
    const nord = await regionId("NORD");
    const sud = await regionId("SUD");
    const group = (
      await w.a.post("/v1/groups", { name: "Groupe Lac", regionId: nord })
    ).body;
    const a = await approvedPdv(w, "n", "Para A");
    const b = await approvedPdv(w, "n", "Para B");
    for (const p of [a, b])
      await w.a.patch(`/v1/pdvs/${p.id}`, { groupId: group.id });
    const moved = await w.a.post(`/v1/groups/${group.id}/move`, {
      regionId: sud,
    });
    expect(moved.body).toMatchObject({ ok: true, stores: 2 });
    expect(names((await w.s.get("/v1/pdvs")).body)).toEqual([
      "Para A",
      "Para B",
    ]);
    expect((await w.n.get("/v1/pdvs")).body).toEqual([]);
    expect((await w.s.get("/v1/groups")).body.map((g: any) => g.name)).toEqual([
      "Groupe Lac",
    ]);
  });

  it("a grossiste moves with its stock; its photos and history follow", async () => {
    await stockPlace(w, w.depotId, w.nord, [50, 40, 30]);
    const proof = await photo(w, w.admin);
    await w.a.patch(`/v1/depots/${w.depotId}`, { photoIds: [proof] });
    const sud = await regionId("SUD");
    expect(
      (await w.a.post(`/v1/depots/${w.depotId}/move`, { regionId: sud }))
        .status,
    ).toBe(201);
    expect((await w.s.get("/v1/depots")).body.map((d: any) => d.name)).toEqual([
      "Depot Hedi",
    ]);
    expect((await w.n.get("/v1/depots")).body).toEqual([]);
    expect(await levels(w, w.depotId)).toEqual({
      "Serum Vitamin C": 50,
      "Serum Niacinamide": 40,
      "Shampoo Argan": 30,
    });
    expect((await w.s.get(`/v1/stock/locations/${w.depotId}`)).status).toBe(
      200,
    );
    expect((await w.n.get(`/v1/stock/locations/${w.depotId}`)).status).toBe(
      404,
    );
    const photoOf = (token: string) =>
      fetch(`${api.url}/v1/media/${proof}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
    expect((await photoOf(w.sud.token)).status).toBe(200);
    expect((await photoOf(w.nord.token)).status).toBe(404);
  });

  it("only the move changes history: nothing else can touch a stock movement", async () => {
    await stockPlace(w, w.depotId, w.nord, [1, 1, 1]);
    const db = await owner();
    await expect(
      db.query(
        `UPDATE "StockMovement" SET delta = 99 WHERE "locationId" = $1`,
        [w.depotId],
      ),
    ).rejects.toThrow(/append-only/);
    await db.end();
  });
});
