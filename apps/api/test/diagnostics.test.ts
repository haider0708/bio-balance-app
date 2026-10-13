import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
import { buildWorld, type World } from "./world";

let api: Api;
let w: World;
beforeAll(async () => {
  await resetDatabase();
  api = await startApi();
  w = await buildWorld(api);
});
afterAll(() => api?.close());

const crash = {
  platform: "android",
  appVersion: "3.3.1 (41)",
  message: "Null check operator used on a null value",
  stack: "#0 SaleScreen.build (package:biobalance/sales.dart:12)\n#1 ...",
};

describe("errors the app meets", () => {
  it("are counted once per kind, without saying who met them", async () => {
    const anonymous = client(api);
    for (let i = 0; i < 3; i++)
      expect((await anonymous.post("/v1/client-errors", crash)).status).toBe(
        201,
      );
    await anonymous.post("/v1/client-errors", {
      ...crash,
      platform: "ios",
    });
    const list = (await w.a.get("/v1/client-errors")).body;
    expect(list).toHaveLength(2);
    const android = list.find((e: any) => e.platform === "android");
    expect(android).toMatchObject({ count: 3, appVersion: "3.3.1 (41)" });
    const db = await owner();
    const columns = (
      await db.query(
        `SELECT column_name FROM information_schema.columns WHERE table_name = 'ClientError'`,
      )
    ).rows.map((r) => r.column_name);
    await db.end();
    expect(columns).not.toContain("userId");
  });

  it("are only shown to the admin, and only well-formed reports are kept", async () => {
    expect((await w.n.get("/v1/client-errors")).status).toBe(403);
    expect(
      (
        await client(api).post("/v1/client-errors", {
          ...crash,
          platform: "windows",
        })
      ).status,
    ).toBe(400);
  });
});
