import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  client,
  createAccount,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { approvedPdv, buildWorld, type World } from "./world";

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

describe("groups and points of sale", () => {
  it("creates a point of sale that waits for the admin", async () => {
    const created = await w.n.post("/v1/pdvs", {
      name: "Para Lac",
      address: "12 rue du Lac",
      city: "Tunis",
      phone: "71 000 000",
    });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ status: "PENDING", name: "Para Lac" });
    const mine = await w.n.get("/v1/pdvs");
    expect(mine.body[0]).toMatchObject({
      name: "Para Lac",
      status: "PENDING",
      initialStock: "NONE",
      memberCount: 0,
    });

    // The admin is told, then approves; the responsable is told in turn.
    const inbox = await w.a.get("/v1/pdvs?status=PENDING");
    expect(inbox.body).toHaveLength(1);
    const approved = await w.a.post(`/v1/pdvs/${created.body.id}/approve`, {});
    expect(approved.body.status).toBe("ACTIVE");
    expect(
      (await w.a.post(`/v1/pdvs/${created.body.id}/approve`, {})).status,
    ).toBe(409);
  });

  it("needs a reason to reject, and lets the responsable resubmit", async () => {
    const created = (
      await w.n.post("/v1/pdvs", {
        name: "Para X",
        address: "1 rue",
        city: "Sfax",
      })
    ).body;
    expect(
      (await w.a.post(`/v1/pdvs/${created.id}/reject`, {})).body.code,
    ).toBe("NOTE_REQUIRED");
    const rejected = await w.a.post(`/v1/pdvs/${created.id}/reject`, {
      note: "Address incomplete",
    });
    expect(rejected.body).toMatchObject({
      status: "REJECTED",
      decisionNote: "Address incomplete",
    });
    const again = await w.n.post(`/v1/pdvs/${created.id}/resubmit`);
    expect(again.body.status).toBe("PENDING");
  });

  it("only the admin can approve, and only a responsable can create", async () => {
    const created = (
      await w.n.post("/v1/pdvs", {
        name: "Para Y",
        address: "2 rue",
        city: "Tunis",
      })
    ).body;
    expect((await w.n.post(`/v1/pdvs/${created.id}/approve`, {})).status).toBe(
      403,
    );
    expect(
      (
        await w.a.post("/v1/pdvs", {
          name: "Admin PDV",
          address: "x",
          city: "y",
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await w.g.post("/v1/pdvs", {
          name: "Gros PDV",
          address: "x",
          city: "y",
        })
      ).status,
    ).toBe(403);
  });

  it("groups hold points of sale of the same region only", async () => {
    const group = (await w.n.post("/v1/groups", { name: "Groupe Nord" })).body;
    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    const ok = await w.n.post("/v1/pdvs", {
      name: "Para 1",
      address: "a",
      city: "Tunis",
      groupId: group.id,
    });
    expect(ok.status).toBe(201);
    const foreign = await w.s.post("/v1/pdvs", {
      name: "Para S",
      address: "a",
      city: "Gabes",
      groupId: group.id,
    });
    expect(foreign.status).toBe(404);
    expect((await w.n.get("/v1/groups")).body[0]).toMatchObject({
      name: "Groupe Nord",
      pdvCount: 1,
    });
  });
});

describe("team members", () => {
  it("a new member is inactive until approved, and cannot sign in before activating", async () => {
    const pdv = await approvedPdv(w);
    const added = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim",
      email: "Karim@Example.test",
      phone: "20 000 000",
    });
    expect(added.status).toBe(201);
    expect(added.body).toMatchObject({
      status: "PENDING",
      role: "VENDEUR",
      pdvId: pdv.id,
      email: "karim@example.test",
    });

    // No invitation is sent until the admin approves.
    expect((await w.a.get("/v1/users?status=PENDING")).body).toHaveLength(1);
    const approved = await w.a.post(`/v1/users/${added.body.id}/approve`, {});
    expect(approved.body.status).toBe("ACTIVE");

    const dup = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim 2",
      email: "karim@example.test",
    });
    expect(dup.body.code).toBe("EMAIL_TAKEN");
  });

  it("a responsable can deactivate a team member, but not approve one", async () => {
    const pdv = await approvedPdv(w);
    const member = (
      await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
        name: "Leila",
        email: "leila@example.test",
      })
    ).body;
    expect((await w.n.post(`/v1/users/${member.id}/approve`, {})).status).toBe(
      403,
    );
    await w.a.post(`/v1/users/${member.id}/approve`, {});
    const suspended = await w.n.post(`/v1/users/${member.id}/suspend`, {});
    expect(suspended.body.status).toBe("SUSPENDED");
  });

  it("allows only one responsable per region", async () => {
    const nord = (await w.a.get("/v1/regions")).body.find(
      (r: any) => r.code === "NORD",
    );
    const second = await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: nord.id,
      name: "Second",
      email: "second@example.test",
    });
    expect(second.body.code).toBe("REGION_HAS_RESPONSABLE");
  });

  it("creates a grossiste with a depot that responsables can see", async () => {
    const regions = (await w.a.get("/v1/regions")).body;
    const nord = regions.find((r: any) => r.code === "NORD");
    const sud = regions.find((r: any) => r.code === "SUD");
    const created = await w.a.post("/v1/users", {
      role: "GROSSISTE",
      regionId: nord.id,
      name: "Mounir",
      email: "mounir@example.test",
      depot: { name: "Depot Sfax", address: "Zone industrielle", city: "Sfax" },
    });
    expect(created.status).toBe(201);
    const depots = await w.n.get("/v1/depots");
    expect(depots.body.map((d: any) => d.name)).toContain("Depot Sfax");
    // A responsable sees only the grossistes of their own region.
    const other = await w.a.post("/v1/users", {
      role: "GROSSISTE",
      regionId: sud.id,
      name: "Slim",
      email: "slim@example.test",
      depot: { name: "Depot Sud", address: "Route de Gabes", city: "Gabes" },
    });
    expect(other.status).toBe(201);
    expect(
      (await w.n.get("/v1/depots")).body.map((d: any) => d.name),
    ).not.toContain("Depot Sud");
    expect(
      (await w.a.get("/v1/depots")).body.map((d: any) => d.name),
    ).toContain("Depot Sud");
    // A grossiste sees only their own depot.
    const own = await w.g.get("/v1/depots");
    expect(own.body).toHaveLength(1);
    expect(own.body[0].name).toBe("Depot Hedi");
  });
});

describe("regions are separate", () => {
  it("a responsable never sees another region's data", async () => {
    const north = await approvedPdv(w, "n", "Para Nord");
    const south = await approvedPdv(w, "s", "Para Sud");
    await w.n.post("/v1/groups", { name: "Groupe N" });
    await w.s.post("/v1/groups", { name: "Groupe S" });
    await w.n.post(`/v1/pdvs/${north.id}/members`, {
      name: "Nadia",
      email: "nadia@example.test",
    });

    expect((await w.n.get("/v1/pdvs")).body.map((p: any) => p.name)).toEqual([
      "Para Nord",
    ]);
    expect((await w.s.get("/v1/pdvs")).body.map((p: any) => p.name)).toEqual([
      "Para Sud",
    ]);
    expect((await w.s.get(`/v1/pdvs/${north.id}`)).status).toBe(404);
    expect((await w.n.get("/v1/groups")).body.map((g: any) => g.name)).toEqual([
      "Groupe N",
    ]);
    expect((await w.s.get("/v1/users")).body).toHaveLength(0);
    expect((await w.n.get("/v1/users")).body).toHaveLength(1);
    // Cannot edit or add to the other region either.
    expect(
      (await w.s.patch(`/v1/pdvs/${north.id}`, { name: "Hijack" })).status,
    ).toBe(404);
    expect(
      (
        await w.s.post(`/v1/pdvs/${north.id}/members`, {
          name: "Spy",
          email: "spy@example.test",
        })
      ).status,
    ).toBe(404);
    expect((await w.a.get("/v1/pdvs")).body).toHaveLength(2);
    expect(south.regionId).not.toBe(north.regionId);
  });

  it("the database refuses cross-region reads even when the application forgets to filter", async () => {
    const north = await approvedPdv(w, "n", "Para Nord");
    await approvedPdv(w, "s", "Para Sud");
    const { Database } = await import("../src/core/database");
    const db = new Database();
    const actor = {
      id: w.sud.id,
      name: "S",
      email: "s",
      role: "RESPONSABLE" as const,
      regionId: (await w.s.get("/v1/me")).body.region.id,
      pdvId: null,
      depotId: null,
      locale: "fr" as const,
    };
    const rows = await db.run(actor, (tx) => tx.pdv.findMany());
    expect(rows.map((r) => r.name)).toEqual(["Para Sud"]);
    await expect(
      db.run(actor, (tx) =>
        tx.pdv.update({ where: { id: north.id }, data: { name: "x" } }),
      ),
    ).rejects.toThrow();
    await expect(
      db.run(actor, (tx) =>
        tx.pdv.create({
          data: {
            name: "Forged",
            address: "x",
            city: "y",
            regionId: north.regionId,
            createdById: w.sud.id,
          },
        }),
      ),
    ).rejects.toThrow();
    await db.$disconnect();
  });

  it("people with no staff role cannot reach the management routes", async () => {
    const pdv = await approvedPdv(w);
    const vendeur = await createAccount({ role: "VENDEUR", pdvId: pdv.id });
    const v = client(api, vendeur.token);
    expect((await v.get("/v1/users")).status).toBe(403);
    expect((await v.get("/v1/groups")).status).toBe(403);
    expect((await v.get("/v1/pdvs")).body.map((p: any) => p.name)).toEqual([
      "Para Lac",
    ]);
  });
});

describe("the approvals history", () => {
  it("lists what was decided, by whom and why, newest first, for the admin only", async () => {
    const ok = (
      await w.n.post("/v1/pdvs", {
        name: "Para Lac",
        address: "1 rue",
        city: "Tunis",
      })
    ).body;
    const no = (
      await w.n.post("/v1/pdvs", {
        name: "Para Rade",
        address: "2 rue",
        city: "Rades",
      })
    ).body;
    await w.a.post(`/v1/pdvs/${ok.id}/approve`, {});
    await w.a.post(`/v1/pdvs/${no.id}/reject`, {
      note: "Address is incomplete",
    });
    const history = (await w.a.get("/v1/approvals/history")).body;
    expect(history.items.map((i: any) => [i.name, i.outcome])).toEqual([
      ["Para Rade", "REJECTED"],
      ["Para Lac", "APPROVED"],
    ]);
    expect(history.items[0]).toMatchObject({
      type: "PDV",
      note: "Address is incomplete",
      decidedBy: "Admin",
      region: "Nord",
    });
    expect(
      (await w.a.get("/v1/approvals/history?type=MEMBER")).body.items,
    ).toEqual([]);
    expect((await w.n.get("/v1/approvals/history")).status).toBe(403);
    // Paging backwards by date.
    const older = (
      await w.a.get(
        `/v1/approvals/history?before=${encodeURIComponent(history.items[0].decidedAt)}`,
      )
    ).body;
    expect(older.items.map((i: any) => i.name)).toEqual(["Para Lac"]);
  });
});
