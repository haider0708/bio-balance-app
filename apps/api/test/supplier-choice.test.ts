import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { SettingsService } from "../src/core/settings";
import { client, resetDatabase, startApi, type Api } from "./helpers";
import { approvedPdv, buildWorld, stockPlace, type World } from "./world";
import { regionId } from "./helpers";

/**
 * A responsable the admin allows (with the global switch on) may suggest the grossiste of a
 * store's restock. The order still goes to the admin, who decides.
 */
let api: Api;
let w: World;
let sudDepotId: string;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  api.app.get(SettingsService).forget();
  sudDepotId = (
    await w.a.post("/v1/depots", {
      regionId: await regionId("SUD"),
      name: "Depot Sfax",
      address: "2 rue du Port",
      city: "Sfax",
    })
  ).body.id;
});

const lines = () => [{ productId: w.products[0]!.id, quantity: 6 }];
const order = (
  c: ReturnType<typeof client>,
  pdv: string,
  supplierId?: string,
) => c.post("/v1/restocks", { destId: pdv, lines: lines(), supplierId });

async function allow(on = true) {
  await w.a.put("/v1/settings", { supplierChoice: on });
  const people = (await w.a.get("/v1/users?role=RESPONSABLE")).body as any[];
  const nord = people.find((p) => p.id === w.nord.id);
  return w.a.put(`/v1/users/${nord.id}/supplier-choice`, { allowed: true });
}

describe("choosing the grossiste of a restock", () => {
  it("is off until the admin turns on the switch and allows the responsable", async () => {
    const pdv = await approvedPdv(w);
    const refused = await order(w.n, pdv.id, w.depotId);
    expect(refused.status).toBe(403);
    expect(refused.body.code).toBe("SUPPLIER_CHOICE_OFF");
    // The global switch alone is not enough.
    await w.a.put("/v1/settings", { supplierChoice: true });
    expect((await order(w.n, pdv.id, w.depotId)).body.code).toBe(
      "SUPPLIER_CHOICE_OFF",
    );
    expect((await w.n.get("/v1/me")).body.canChooseSupplier).toBe(false);
    // Allowing the person while the switch is off is not enough either.
    await w.a.put("/v1/settings", { supplierChoice: false });
    await w.a.put(`/v1/users/${w.nord.id}/supplier-choice`, { allowed: true });
    expect((await order(w.n, pdv.id, w.depotId)).body.code).toBe(
      "SUPPLIER_CHOICE_OFF",
    );
  });

  it("lets an allowed responsable suggest any grossiste, and the admin approves it as suggested", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.nord, [50, 0, 0]);
    expect((await allow()).status).toBe(200);
    expect((await w.n.get("/v1/me")).body.canChooseSupplier).toBe(true);
    const told = (await w.n.get("/v1/notifications")).body.items.map(
      (n: any) => n.key,
    );
    expect(told).toContain("supplier.allowed");

    // Another region's grossiste is fine: there is no region restriction.
    const placed = await order(w.n, pdv.id, sudDepotId);
    expect(placed.status).toBe(201);
    expect(placed.body).toMatchObject({
      status: "REQUESTED",
      suggestedSupplier: { id: sudDepotId, name: "Depot Sfax" },
    });
    const adminTold = (await w.a.get("/v1/notifications")).body.items.find(
      (n: any) => n.key === "restock.requested_from",
    );
    expect(adminTold.params).toMatchObject({ depot: "Depot Sfax" });
    // The admin sees the suggestion on the order and can still choose differently.
    const seen = (await w.a.get(`/v1/restocks/${placed.body.id}`)).body;
    expect(seen.suggestedSupplier.name).toBe("Depot Sfax");
    const assigned = await w.a.post(`/v1/restocks/${placed.body.id}/assign`, {
      depotId: w.depotId,
    });
    expect(assigned.body).toMatchObject({
      status: "ASSIGNED",
      supplier: { id: w.depotId },
      suggestedSupplier: { id: sudDepotId },
    });
    // Or as suggested, from BioBalance, or refused.
    const second = (await order(w.n, pdv.id, sudDepotId)).body;
    expect(
      (
        await w.a.post(`/v1/restocks/${second.id}/assign`, {
          depotId: sudDepotId,
        })
      ).body.supplier.id,
    ).toBe(sudDepotId);
    const third = (await order(w.n, pdv.id, w.depotId)).body;
    expect(
      (await w.a.post(`/v1/restocks/${third.id}/send-direct`, {})).body.source,
    ).toBe("BIOBALANCE");
    const fourth = (await order(w.n, pdv.id, w.depotId)).body;
    expect(
      (await w.a.post(`/v1/restocks/${fourth.id}/cancel`, { note: "Not now" }))
        .body.status,
    ).toBe("CANCELLED");
  });

  it("shows the grossistes and whether they cover the order, never another region's quantities", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.nord, [50, 0, 0]);
    await allow();
    const list = await w.n.post("/v1/restocks/suppliers", { lines: lines() });
    expect(list.status).toBe(201);
    const [first, second] = list.body as any[];
    expect(first).toMatchObject({ id: w.depotId, missing: 0 });
    expect(second).toMatchObject({ id: sudDepotId, missing: 1 });
    expect(JSON.stringify(list.body)).not.toMatch(/"held"|"quantity"/);
    expect(first.lines[0]).toEqual({
      productId: w.products[0]!.id,
      enough: true,
    });
    expect(pdv.id).toBeTruthy();
    // Not for a responsable who is not allowed, nor for anyone else.
    expect(
      (await w.s.post("/v1/restocks/suppliers", { lines: lines() })).body.code,
    ).toBe("SUPPLIER_CHOICE_OFF");
    expect(
      (await w.a.post("/v1/restocks/suppliers", { lines: lines() })).status,
    ).toBe(403);
  });

  it("refuses a made-up or suspended grossiste, a team member, and a second responsable not allowed", async () => {
    const pdv = await approvedPdv(w);
    await allow();
    expect((await order(w.n, pdv.id, randomUUID())).body.code).toBe(
      "DEPOT_NOT_FOUND",
    );
    await w.a.patch(`/v1/depots/${sudDepotId}`, { status: "SUSPENDED" });
    expect((await order(w.n, pdv.id, sudDepotId)).body.code).toBe(
      "DEPOT_NOT_FOUND",
    );
    // The other responsable was not allowed.
    const sudPdv = await approvedPdv(w, "s", "Para Sfax");
    expect((await order(w.s, sudPdv.id, w.depotId)).body.code).toBe(
      "SUPPLIER_CHOICE_OFF",
    );
    // Switching off takes it away from everyone at once.
    await w.a.put("/v1/settings", { supplierChoice: false });
    expect((await order(w.n, pdv.id, w.depotId)).body.code).toBe(
      "SUPPLIER_CHOICE_OFF",
    );
    // An order without a suggestion works as before.
    expect((await order(w.n, pdv.id)).status).toBe(201);
  });

  it("is the admin's to give, to a responsable only", async () => {
    expect(
      (
        await w.n.put(`/v1/users/${w.nord.id}/supplier-choice`, {
          allowed: true,
        })
      ).status,
    ).toBe(403);
    const admins = (await w.a.get("/v1/users?role=ADMIN")).body as any[];
    const target = admins[0]?.id ?? w.admin.id;
    expect(
      (await w.a.put(`/v1/users/${target}/supplier-choice`, { allowed: true }))
        .status,
    ).not.toBe(200);
    // Taking it back tells the responsable.
    await allow();
    await w.a.put(`/v1/users/${w.nord.id}/supplier-choice`, { allowed: false });
    const keys = (await w.n.get("/v1/notifications")).body.items.map(
      (n: any) => n.key,
    );
    expect(keys).toContain("supplier.removed");
    const people = (await w.a.get("/v1/users?role=RESPONSABLE")).body as any[];
    expect(people.find((p) => p.id === w.nord.id).canChooseSupplier).toBe(
      false,
    );
  });
});
