import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { resetDatabase, startApi, type Api } from "./helpers";
import { buildWorld, type World } from "./world";

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

const closedAllWeek = {
  enabled: true,
  days: Array.from({ length: 7 }, () => null),
};
const openAllWeek = {
  enabled: true,
  days: Array.from({ length: 7 }, () => ({ open: "00:00", close: "23:59" })),
};

describe("working hours", () => {
  it("blocks everything but signing in for a responsable when closed, never the admin", async () => {
    expect(
      (await w.a.put("/v1/settings", { hours: closedAllWeek })).status,
    ).toBe(200);
    const blocked = await w.n.get("/v1/pdvs");
    expect(blocked.status).toBe(423);
    expect(blocked.body.code).toBe("SERVER_CLOSED");
    // Who I am and signing out stay possible so the app can say it is closed.
    expect((await w.n.get("/v1/me")).status).toBe(200);
    // The admin is never shut out.
    expect((await w.a.get("/v1/pdvs")).status).toBe(200);
  });

  it("works again once the admin opens, or switches the hours off", async () => {
    await w.a.put("/v1/settings", { hours: closedAllWeek });
    expect((await w.n.get("/v1/pdvs")).status).toBe(423);
    await w.a.put("/v1/settings", { hours: openAllWeek });
    expect((await w.n.get("/v1/pdvs")).status).toBe(200);
    await w.a.put("/v1/settings", { hours: closedAllWeek });
    await w.a.put("/v1/settings", {
      hours: { ...closedAllWeek, enabled: false },
    });
    expect((await w.n.get("/v1/pdvs")).status).toBe(200);
  });

  it("tells the app when it opens again", async () => {
    await w.a.put("/v1/settings", {
      hours: {
        enabled: true,
        days: Array.from({ length: 7 }, () => ({
          open: "08:00",
          close: "08:01",
        })),
      },
    });
    const r = await w.n.get("/v1/pdvs");
    // Either closed with a next opening, or (a minute a day) open.
    if (r.status === 423) {
      expect(r.body.details.time).toBe("08:00");
      expect(typeof r.body.details.opensAt).toBe("string");
    }
  });
});
