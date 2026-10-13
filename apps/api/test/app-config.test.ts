import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { client, startApi, type Api } from "./helpers";

let api: Api;
beforeAll(async () => {
  api = await startApi();
});
afterAll(async () => {
  delete process.env.MIN_APP_BUILD;
  await api?.close();
});

describe("what the phones check when they start", () => {
  it("allows every build and links the stores until a minimum is set", async () => {
    const res = await client(api).get("/v1/app-config");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      minimumBuild: 0,
      stores: {
        android:
          "https://play.google.com/store/apps/details?id=tn.biobalance.app",
        ios: null,
      },
    });
  });

  it("gives the minimum build the server is set to, without signing in", async () => {
    process.env.MIN_APP_BUILD = "41";
    expect((await client(api).get("/v1/app-config")).body.minimumBuild).toBe(
      41,
    );
  });
});
