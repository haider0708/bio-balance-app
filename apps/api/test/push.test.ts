import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { Database } from "../src/core/database";
import { formatMillimes, noticeText } from "../src/core/notice-text";
import {
  ApnsTransport,
  type PushDeviceTarget,
  type PushMessage,
  type PushOutcome,
  type PushTransport,
} from "../src/push/apns";
import { PushDelivery } from "../src/push/push-delivery";

let api: Api;
let db: Database;
beforeAll(async () => {
  api = await startApi();
  db = new Database();
});
afterAll(async () => {
  await db.$disconnect();
  await api.close();
});
beforeEach(resetDatabase);

const token = (n: number) => n.toString(16).padStart(64, "a");

class FakeApple implements PushTransport {
  sent: { device: PushDeviceTarget; message: PushMessage }[] = [];
  answer: (device: PushDeviceTarget) => PushOutcome = () => "sent";
  async send(device: PushDeviceTarget, message: PushMessage) {
    this.sent.push({ device, message });
    return this.answer(device);
  }
  close() {}
}

async function sql<T = Record<string, unknown>>(
  query: string,
  values: unknown[] = [],
) {
  const c = await owner();
  try {
    return (await c.query(query, values)).rows as T[];
  } finally {
    await c.end();
  }
}

async function notice(
  userId: string,
  key: string,
  params: object,
  age = "0 minutes",
) {
  await sql(
    `INSERT INTO "Notification"(id,"userId",kind,key,params,"createdAt")
     VALUES (gen_random_uuid(),$1,'SYSTEM',$2,$3,(now() AT TIME ZONE 'UTC') - $4::interval)`,
    [userId, key, JSON.stringify(params), age],
  );
}

describe("push alerts", () => {
  it("a phone registers for its session; the last person signed in on it gets its alerts", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const sami = await createAccount({
      role: "RESPONSABLE",
      regionCode: "SUD",
    });
    const n = client(api, nora.token);
    expect(
      (await n.post("/v1/me/push-device", { token: "xyz", platform: "IOS" }))
        .status,
    ).toBe(400);
    const ok = await n.post("/v1/me/push-device", {
      token: token(1).toUpperCase(),
      platform: "IOS",
    });
    expect(ok.status).toBe(201);
    // No Apple key on this server: the phone keeps its own background check.
    expect(ok.body).toEqual({ push: false });
    await client(api, sami.token).post("/v1/me/push-device", {
      token: token(1),
      platform: "IOS",
      sandbox: true,
    });
    const rows = await sql<{ userId: string; sandbox: boolean }>(
      `SELECT "userId", sandbox FROM "PushDevice"`,
    );
    expect(rows).toEqual([{ userId: sami.id, sandbox: true }]);
    // Signing out ends the session; the device row goes with it once sessions are purged.
    await client(api, sami.token).post("/v1/auth/logout");
    await sql(`DELETE FROM "Session" WHERE "revokedAt" IS NOT NULL`);
    expect(await sql(`SELECT 1 FROM "PushDevice"`)).toHaveLength(0);
  });

  it("each new notification is pushed once, in the person's language, with the unread count", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const sami = await createAccount({
      role: "RESPONSABLE",
      regionCode: "SUD",
    });
    await sql(`UPDATE "User" SET locale='en' WHERE id=$1`, [sami.id]);
    await client(api, nora.token).post("/v1/me/push-device", {
      token: token(1),
      platform: "IOS",
    });
    await client(api, sami.token).post("/v1/me/push-device", {
      token: token(2),
      platform: "IOS",
    });
    await notice(nora.id, "sale.recorded", {
      seller: "Karim",
      units: 3,
      place: "Para Lac",
      amountMillimes: 2100,
    });
    await notice(sami.id, "restock.cancelled", { number: "R-12" });
    // From before the phone was listening: marked, never pushed.
    await notice(sami.id, "restock.completed", { number: "R-9" }, "2 hours");

    const apple = new FakeApple();
    const pushes = new PushDelivery(db, apple);
    expect(await pushes.tick()).toBe(3);
    expect(await pushes.tick()).toBe(0);
    const byToken = new Map(apple.sent.map((s) => [s.device.token, s.message]));
    expect(apple.sent).toHaveLength(2);
    expect(byToken.get(token(1))).toMatchObject({
      body: `Karim a vendu 3 unités à Para Lac · ${formatMillimes(2100, "fr")} gagnés.`,
      badge: 1,
      thread: "sale",
    });
    expect(byToken.get(token(2))).toMatchObject({
      body: "Restock R-12 was cancelled.",
      badge: 2,
    });
  });

  it("many alerts at once become one, and a phone Apple no longer knows is forgotten", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    await client(api, nora.token).post("/v1/me/push-device", {
      token: token(3),
      platform: "IOS",
    });
    for (let i = 0; i < 5; i++)
      await notice(nora.id, "restock.cancelled", { number: `R-${i}` });
    const apple = new FakeApple();
    apple.answer = () => "gone";
    await new PushDelivery(db, apple).tick();
    expect(apple.sent.map((s) => s.message.body)).toEqual([
      "5 nouvelles notifications",
    ]);
    expect(await sql(`SELECT 1 FROM "PushDevice"`)).toHaveLength(0);
  });

  it("without an Apple key nothing is sent and nothing piles up", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    await notice(nora.id, "restock.cancelled", { number: "R-1" });
    expect(await new PushDelivery(db, null).tick()).toBe(1);
    expect(
      await sql(`SELECT 1 FROM "Notification" WHERE "pushedAt" IS NULL`),
    ).toHaveLength(0);
    expect(ApnsTransport.fromEnv({})).toBeNull();
  });

  it("the Apple sign-in token is a valid ES256 token", () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const apns = ApnsTransport.fromEnv({
      APNS_KEY_ID: "KEY123",
      APNS_TEAM_ID: "TEAM456",
      APNS_KEY_P8: Buffer.from(
        privateKey.export({ type: "pkcs8", format: "pem" }),
      ).toString("base64"),
    })!;
    const jwt = (apns as unknown as { bearer(): string }).bearer();
    const [header, claims, signature] = jwt.split(".");
    expect(JSON.parse(Buffer.from(header!, "base64url").toString())).toEqual({
      alg: "ES256",
      kid: "KEY123",
    });
    expect(
      JSON.parse(Buffer.from(claims!, "base64url").toString()),
    ).toMatchObject({
      iss: "TEAM456",
    });
    expect(Buffer.from(signature!, "base64url")).toHaveLength(64);
    apns.close();
  });

  it("words notifications like the app", () => {
    expect(noticeText("en", "payout.approved", { amountMillimes: 12500 })).toBe(
      `Your payout of ${formatMillimes(12500, "en")} was approved.`,
    );
    expect(formatMillimes(12500, "en")).toBe("12.500 TND");
    expect(
      noticeText("fr", "stock.adjusted", {
        place: "Para Lac",
        note: " recompté ",
      }),
    ).toBe("Le stock de Para Lac a été corrigé : recompté");
    expect(noticeText("fr", "unknown.key", {})).toBeNull();
  });
});
