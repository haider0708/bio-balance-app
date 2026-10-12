import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { generateKeyPairSync, createVerify } from "node:crypto";
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
import { FcmTransport } from "../src/push/fcm";
import { PushDelivery } from "../src/push/push-delivery";
import { NotificationSignal } from "../src/push/signal";
import { pushConfigured, transportsFromEnv } from "../src/push/transports";

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
/** A Firebase-looking registration token. */
const fcmToken = (n: number) => `fcm${n}:APA91b${"x".repeat(60)}_-`;

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
    const pushes = new PushDelivery(db, { IOS: apple });
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
    await new PushDelivery(db, { IOS: apple }).tick();
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
    expect(await new PushDelivery(db, {}).tick()).toBe(1);
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

  it("an Android phone registers with its Firebase token and is told the server pushes", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const n = client(api, nora.token);
    expect(
      (
        await n.post("/v1/me/push-device", {
          token: "short",
          platform: "ANDROID",
        })
      ).status,
    ).toBe(400);
    // An Apple-style token is not an Android one, and the other way round.
    expect(
      (
        await n.post("/v1/me/push-device", {
          token: fcmToken(1),
          platform: "IOS",
        })
      ).status,
    ).toBe(400);
    const ok = await n.post("/v1/me/push-device", {
      token: fcmToken(1),
      platform: "ANDROID",
    });
    expect(ok.status).toBe(201);
    expect(ok.body).toEqual({ push: false });
    process.env.FCM_SERVICE_ACCOUNT = "set";
    try {
      expect(
        (
          await n.post("/v1/me/push-device", {
            token: fcmToken(1),
            platform: "ANDROID",
          })
        ).body,
      ).toEqual({ push: true });
    } finally {
      delete process.env.FCM_SERVICE_ACCOUNT;
    }
    expect(await sql(`SELECT platform FROM "PushDevice"`)).toEqual([
      { platform: "ANDROID" },
    ]);
  });

  it("delivers to each phone through its own service, in order, and skips a platform without a key", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const n = client(api, nora.token);
    await n.post("/v1/me/push-device", { token: token(1), platform: "IOS" });
    await n.post("/v1/me/push-device", {
      token: fcmToken(2),
      platform: "ANDROID",
    });
    await notice(nora.id, "restock.cancelled", { number: "R-1" });
    await notice(nora.id, "restock.cancelled", { number: "R-2" });
    const apple = new FakeApple();
    const google = new FakeApple();
    await new PushDelivery(db, { IOS: apple, ANDROID: google }).tick();
    expect(apple.sent).toHaveLength(2);
    expect(google.sent.map((s) => s.device.token)).toEqual([
      fcmToken(2),
      fcmToken(2),
    ]);
    expect(google.sent[0]!.message.body).toContain("R-1");
    // Only Android has a key: the iPhone is left to its own background check.
    await notice(nora.id, "restock.cancelled", { number: "R-3" });
    apple.sent = [];
    google.sent = [];
    await new PushDelivery(db, { ANDROID: google }).tick();
    expect(apple.sent).toHaveLength(0);
    expect(google.sent).toHaveLength(1);
  });

  it("an Android phone Google no longer knows is forgotten, one that is merely slow is kept", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const n = client(api, nora.token);
    await n.post("/v1/me/push-device", {
      token: fcmToken(3),
      platform: "ANDROID",
    });
    await notice(nora.id, "restock.cancelled", { number: "R-1" });
    const google = new FakeApple();
    google.answer = () => "failed";
    await new PushDelivery(db, { ANDROID: google }).tick();
    expect(await sql(`SELECT 1 FROM "PushDevice"`)).toHaveLength(1);
    await notice(nora.id, "restock.cancelled", { number: "R-2" });
    google.answer = () => "gone";
    await new PushDelivery(db, { ANDROID: google }).tick();
    expect(await sql(`SELECT 1 FROM "PushDevice"`)).toHaveLength(0);
  });

  it("a notification wakes the worker through the database at once", async () => {
    const nora = await createAccount({
      role: "RESPONSABLE",
      regionCode: "NORD",
    });
    const wake = new NotificationSignal(process.env.DATABASE_URL ?? "");
    wake.start();
    try {
      for (let i = 0; i < 100 && !wake.listening; i++)
        await new Promise((r) => setTimeout(r, 20));
      expect(wake.listening).toBe(true);
      await wake.wait(1000); // the catch-up signal after connecting
      const started = Date.now();
      const waiting = wake.wait(10_000);
      await notice(nora.id, "restock.cancelled", { number: "R-1" });
      await waiting;
      expect(Date.now() - started).toBeLessThan(2000);
      // A signal that arrives before anyone waits is not lost.
      await notice(nora.id, "restock.cancelled", { number: "R-2" });
      await new Promise((r) => setTimeout(r, 300));
      const before = Date.now();
      await wake.wait(10_000);
      expect(Date.now() - before).toBeLessThan(1000);
    } finally {
      await wake.stop();
    }
  });
});

describe("Firebase transport", () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const account = {
    client_email: "push@project.iam.gserviceaccount.com",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }) as string,
    project_id: "demo-project",
    token_uri: "https://oauth.test/token",
  };
  const message: PushMessage = {
    title: "BioBalance",
    body: "Amira a vendu 3 unités",
    badge: 4,
    thread: "sale",
  };
  const target = { token: fcmToken(1), sandbox: false };

  /** A fake Google: answers the sign-in, then each send from the queue. */
  function google(answers: { status: number; body?: object }[]) {
    const calls: { url: string; init: RequestInit }[] = [];
    const queue = [...answers];
    const http = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      if (url === account.token_uri)
        return Response.json({ access_token: "access-1", expires_in: 3600 });
      const next = queue.shift() ?? { status: 200 };
      return Response.json(next.body ?? {}, { status: next.status });
    }) as unknown as typeof fetch;
    return {
      calls,
      http,
      sends: () => calls.filter((c) => c.url !== account.token_uri),
    };
  }

  it("signs in with a valid RS256 token, once, and sends the alert as Android wants it", async () => {
    const fake = google([{ status: 200 }, { status: 200 }]);
    const fcm = new FcmTransport(account, fake.http);
    expect(await fcm.send(target, message)).toBe("sent");
    expect(await fcm.send(target, message)).toBe("sent");
    const signIns = fake.calls.filter((c) => c.url === account.token_uri);
    expect(signIns).toHaveLength(1);
    const assertion = new URLSearchParams(String(signIns[0]!.init.body)).get(
      "assertion",
    )!;
    const [header, claims, signature] = assertion.split(".");
    expect(JSON.parse(Buffer.from(header!, "base64url").toString())).toEqual({
      alg: "RS256",
      typ: "JWT",
    });
    expect(
      JSON.parse(Buffer.from(claims!, "base64url").toString()),
    ).toMatchObject({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    });
    expect(
      createVerify("RSA-SHA256")
        .update(`${header}.${claims}`)
        .verify(publicKey, Buffer.from(signature!, "base64url")),
    ).toBe(true);
    const send = fake.sends()[0]!;
    expect(send.url).toBe(
      "https://fcm.googleapis.com/v1/projects/demo-project/messages:send",
    );
    expect((send.init.headers as Record<string, string>).authorization).toBe(
      "Bearer access-1",
    );
    expect(JSON.parse(String(send.init.body))).toEqual({
      message: {
        token: target.token,
        notification: { title: "BioBalance", body: "Amira a vendu 3 unités" },
        data: { route: "notifications" },
        android: {
          priority: "HIGH",
          ttl: "86400s",
          notification: {
            channel_id: "biobalance_alerts",
            icon: "ic_stat_biobalance",
            color: "#0C6B45",
            default_sound: true,
            notification_count: 4,
          },
        },
      },
    });
  });

  it("forgets a phone only for a bad or removed token, retries trouble, and never drops phones over its own mistakes", async () => {
    const unregistered = google([
      {
        status: 404,
        body: {
          error: {
            status: "NOT_FOUND",
            details: [{ errorCode: "UNREGISTERED" }],
          },
        },
      },
    ]);
    expect(
      await new FcmTransport(account, unregistered.http).send(target, message),
    ).toBe("gone");

    const badToken = google([
      {
        status: 400,
        body: {
          error: {
            status: "INVALID_ARGUMENT",
            message:
              "The registration token is not a valid FCM registration token",
          },
        },
      },
    ]);
    expect(
      await new FcmTransport(account, badToken.http).send(target, message),
    ).toBe("gone");

    // A malformed message of ours is an invalid argument too: the phone must be kept.
    const ourMistake = google([
      {
        status: 400,
        body: {
          error: {
            status: "INVALID_ARGUMENT",
            message: "Invalid value at 'message.android'",
          },
        },
      },
    ]);
    expect(
      await new FcmTransport(account, ourMistake.http).send(target, message),
    ).toBe("failed");

    // A busy service is tried again and the alert still arrives.
    const busy = google([{ status: 503 }, { status: 429 }, { status: 200 }]);
    expect(
      await new FcmTransport(account, busy.http).send(target, message),
    ).toBe("sent");
    expect(busy.sends()).toHaveLength(3);

    // A refused access token is replaced and the same alert is sent again.
    const expired = google([{ status: 401 }, { status: 200 }]);
    expect(
      await new FcmTransport(account, expired.http).send(target, message),
    ).toBe("sent");
    expect(
      expired.calls.filter((c) => c.url === account.token_uri),
    ).toHaveLength(2);
  });

  it("is configured from the environment, per platform", () => {
    expect(FcmTransport.fromEnv({})).toBeNull();
    expect(transportsFromEnv({})).toEqual({});
    const env = {
      FCM_SERVICE_ACCOUNT: Buffer.from(JSON.stringify(account)).toString(
        "base64",
      ),
    };
    expect(Object.keys(transportsFromEnv(env))).toEqual(["ANDROID"]);
    expect(pushConfigured("ANDROID", env)).toBe(true);
    expect(pushConfigured("IOS", env)).toBe(false);
    expect(pushConfigured("ANDROID", {})).toBe(false);
  });
});
