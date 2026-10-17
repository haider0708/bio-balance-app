import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { client, resetDatabase, startApi, type Api } from "./helpers";
import { buildWorld, type World } from "./world";

let api: Api;
let w: World;
beforeAll(async () => {
  api = await startApi();
});
afterAll(async () => {
  delete process.env.MIN_APP_BUILD;
  await api?.close();
});
beforeEach(async () => {
  await resetDatabase();
  delete process.env.MIN_APP_BUILD;
  w = await buildWorld(api);
  // The settings are kept for ten seconds by each API instance: forget them between tests.
  const { SettingsService } = await import("../src/core/settings");
  api.app.get(SettingsService).forget();
});

describe("what the phones check when they start", () => {
  it("allows every build and links the stores until a minimum is set", async () => {
    const res = await client(api).get("/v1/app-config");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      minimumBuild: 0,
      minimumBuilds: { ios: 0, android: 0 },
      stores: {
        android:
          "https://play.google.com/store/apps/details?id=tn.biobalance.app",
        ios: null,
      },
    });
  });

  it("falls back to the server's MIN_APP_BUILD until the admin sets one", async () => {
    process.env.MIN_APP_BUILD = "41";
    const { SettingsService } = await import("../src/core/settings");
    api.app.get(SettingsService).forget();
    expect((await client(api).get("/v1/app-config")).body.minimumBuild).toBe(
      41,
    );
  });

  it("gives each platform its own minimum, and an app that does not say the lower one", async () => {
    const saved = await w.a.put("/v1/settings", {
      minimumBuild: { ios: 45 },
      stores: { ios: "https://apps.apple.com/app/id6822445997" },
    });
    expect(saved.status).toBe(200);
    expect(saved.body.minimumBuild).toEqual({ ios: 45, android: 0 });
    const c = client(api);
    expect((await c.get("/v1/app-config?platform=ios")).body).toMatchObject({
      minimumBuild: 45,
      stores: { ios: "https://apps.apple.com/app/id6822445997" },
    });
    expect(
      (await c.get("/v1/app-config?platform=android")).body.minimumBuild,
    ).toBe(0);
    // Forcing one platform never forces an app that cannot say which it is.
    expect((await c.get("/v1/app-config")).body.minimumBuild).toBe(0);
    await w.a.put("/v1/settings", { minimumBuild: { android: 43 } });
    expect((await c.get("/v1/app-config")).body.minimumBuild).toBe(43);
  });
});

describe("the admin's settings", () => {
  it("are the admin's alone, validated, and in the audit log", async () => {
    expect((await w.n.get("/v1/settings")).status).toBe(403);
    expect(
      (await w.n.put("/v1/settings", { supplierChoice: true })).status,
    ).toBe(403);
    const bad = await w.a.put("/v1/settings", {
      hours: {
        enabled: true,
        days: Array.from({ length: 7 }, () => ({
          open: "21:00",
          close: "08:00",
        })),
      },
    });
    expect(bad.status).toBe(400);
    expect(
      (await w.a.put("/v1/settings", { minimumBuild: { ios: -1 } })).status,
    ).toBe(400);
    const ok = await w.a.put("/v1/settings", { supplierChoice: true });
    expect(ok.body.supplierChoice).toBe(true);
    const read = (await w.a.get("/v1/settings")).body;
    expect(read).toMatchObject({
      supplierChoice: true,
      hours: { enabled: false },
      open: true,
    });
    const audit = (await w.a.get("/v1/audit?limit=20")).body.items as any[];
    expect(audit.map((e) => e.action)).toContain("settings.changed");
  });
});
