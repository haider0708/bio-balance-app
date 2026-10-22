import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { Database } from "../src/core/database";
import { SettingsService } from "../src/core/settings";
import { WhatsAppDelivery } from "../src/whatsapp/delivery";
import { WahaTransport } from "../src/whatsapp/transport";
import type { WhatsAppTransport } from "../src/whatsapp/transport";
import { owner, resetDatabase, startApi, type Api } from "./helpers";
import { approvedPdv, buildWorld, type World } from "./world";

let api: Api;
let w: World;
let db: Database;
beforeAll(async () => {
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  // Settings are kept for ten seconds per instance: forget what a previous test saved.
  api.app.get(SettingsService).forget();
});

/** A sender that records what it was asked to send. */
function fake(options: { has?: boolean | null } = {}) {
  const sent: { phone: string; text: string }[] = [];
  const transport: WhatsAppTransport = {
    hasWhatsApp: async () => (options.has === undefined ? true : options.has),
    send: async (phone, text) => {
      sent.push({ phone, text });
    },
    status: async () => "CONNECTED",
  };
  return { sent, transport };
}

const turn = (enabled: boolean) =>
  w.a.put("/v1/settings", { whatsapp: { enabled } });

async function invite(phone: string | null = "00216 21 345 678") {
  const pdv = await approvedPdv(w);
  const res = await w.a.post("/v1/users", {
    role: "VENDEUR",
    pdvId: pdv.id,
    name: "Hanen Smiri",
    email: "hanen@example.test",
    ...(phone !== null && { phone }),
  });
  return res;
}

async function jobs(kind: string) {
  const o = await owner();
  try {
    return (
      await o.query(
        `SELECT id, key, payload, status FROM "Job" WHERE kind = $1 ORDER BY "createdAt"`,
        [kind],
      )
    ).rows as { id: string; key: string; payload: any; status: string }[];
  } finally {
    await o.end();
  }
}

describe("the phone of a new account", () => {
  it("is required, read in every way a person writes it, and stored as +216XXXXXXXX", async () => {
    expect((await invite(null)).body.code).toBe("PHONE_REQUIRED");
    expect((await invite("12 345")).body.code).toBe("PHONE_INVALID");
    expect((await invite("+33 6 12 34 56 78")).body.code).toBe("PHONE_INVALID");
    const ok = await invite("00216 21 345 678");
    expect(ok.status).toBe(201);
    expect(ok.body.phone).toBe("+21621345678");
    // A responsable adding a team member has the same rule.
    const pdv = await approvedPdv(w, "n", "Para Marsa");
    const member = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim",
      email: "karim@example.test",
      phone: " +216-21.345.679 ",
    });
    expect(member.body.phone).toBe("+21621345679");
    expect(
      (
        await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
          name: "Sami",
          email: "sami@example.test",
        })
      ).body.code,
    ).toBe("PHONE_REQUIRED");
    // Changing it later is checked the same way.
    const changed = await w.a.patch(`/v1/users/${ok.body.id}`, {
      phone: "22 333 444",
    });
    expect(changed.body.phone).toBe("+21622333444");
    expect(
      (await w.a.patch(`/v1/users/${ok.body.id}`, { phone: "nope" })).body.code,
    ).toBe("PHONE_INVALID");
  });
});

describe("codes by WhatsApp", () => {
  const delivery = (t: WhatsAppTransport | null, cap?: number) =>
    new WhatsAppDelivery(db, t, api.app.get(SettingsService), cap);

  it("queues a WhatsApp message next to the email, and the email never depends on it", async () => {
    await invite();
    const email = await jobs("email");
    const wa = await jobs("whatsapp");
    expect(email.length).toBe(1);
    expect(wa.length).toBe(1);
    expect(wa[0]!.payload.code).toBe(email[0]!.payload.code);
  });

  it("sends the code to the number when the channel is on, in the person's language", async () => {
    await turn(true);
    await invite();
    const { sent, transport } = fake();
    const job = (await jobs("whatsapp"))[0]!;
    expect(await delivery(transport).deliver(job)).toBe("sent");
    expect(sent).toHaveLength(1);
    expect(sent[0]!.phone).toBe("+21621345678");
    expect(sent[0]!.text).toContain(job.payload.code);
    expect(sent[0]!.text).toContain("Bonjour Hanen Smiri");
  });

  it("stays silent when the channel is off, not set up, or the number is not usable", async () => {
    await invite();
    const job = (await jobs("whatsapp"))[0]!;
    const off = fake();
    expect(await delivery(off.transport).deliver(job)).toBe("suppressed");
    await turn(true);
    expect(await delivery(null).deliver(job)).toBe("suppressed");
    // A number that has no WhatsApp is not tried.
    const none = fake({ has: false });
    expect(await delivery(none.transport).deliver(job)).toBe("suppressed");
    expect(none.sent).toHaveLength(0);
    // An old, badly written number from before the rule is skipped, never guessed.
    const o = await owner();
    try {
      await o.query(`UPDATE "User" SET phone = '71 000' WHERE email = $1`, [
        "hanen@example.test",
      ]);
    } finally {
      await o.end();
    }
    const old = fake();
    expect(await delivery(old.transport).deliver(job)).toBe("suppressed");
    expect(old.sent).toHaveLength(0);
  });

  it("does not send a code that was used or replaced, and respects the daily cap", async () => {
    await turn(true);
    const res = await invite();
    const first = (await jobs("whatsapp"))[0]!;
    // Sending the invitation again replaces the code: the first one must not go out.
    await w.a.post(`/v1/users/${res.body.id}/resend-invite`, {});
    const { sent, transport } = fake();
    expect(await delivery(transport).deliver(first)).toBe("suppressed");
    const latest = (await jobs("whatsapp")).at(-1)!;
    expect(await delivery(transport).deliver(latest)).toBe("sent");
    expect(sent).toHaveLength(1);
    // Over the cap the job waits and is retried later.
    await expect(delivery(transport, 1).deliver(latest)).rejects.toThrow(
      "WHATSAPP_DAILY_CAP",
    );
  });

  it("a password reset and a password change are also sent", async () => {
    await turn(true);
    const res = await invite();
    const o = await owner();
    try {
      await o.query(
        `UPDATE "User" SET "passwordHash" = 'x', status = 'ACTIVE' WHERE id = $1`,
        [res.body.id],
      );
    } finally {
      await o.end();
    }
    const asked = await (
      await fetch(`${api.url}/v1/auth/forgot-password`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: "hanen@example.test" }),
      })
    ).status;
    expect(asked).toBeLessThan(300);
    const wa = await jobs("whatsapp");
    expect(wa.some((j) => j.key.startsWith("wa:reset:"))).toBe(true);
  });

  it("can be switched on and off by the admin only, and shows whether it is set up", async () => {
    const before = await w.a.get("/v1/settings");
    expect(before.body.whatsapp).toMatchObject({
      enabled: false,
      status: "NOT_CONFIGURED",
    });
    expect((await turn(true)).body.whatsapp.enabled).toBe(true);
    expect(
      (await w.n.put("/v1/settings", { whatsapp: { enabled: false } })).status,
    ).toBe(403);
  });
});

describe("the WAHA sender", () => {
  it("sends one message at a time, spaced, through the private HTTP API", async () => {
    const calls: { url: string; body: any; key: string | null }[] = [];
    const naps: number[] = [];
    const t = new WahaTransport({
      url: "http://waha:3000/",
      apiKey: "secret",
      gapMs: () => 4000,
      sleep: async (ms) => {
        naps.push(ms);
      },
      fetchImpl: (async (url: string, init: RequestInit) => {
        calls.push({
          url,
          body: init.body ? JSON.parse(String(init.body)) : null,
          key: (init.headers as Record<string, string>)["x-api-key"] ?? null,
        });
        return new Response(JSON.stringify({ ok: true }), { status: 201 });
      }) as unknown as typeof fetch,
    });
    await Promise.all([
      t.send("+21621345678", "one"),
      t.send("+21622333444", "two"),
    ]);
    expect(calls.map((c) => c.body.text)).toEqual(["one", "two"]);
    expect(calls[0]).toMatchObject({
      url: "http://waha:3000/api/sendText",
      key: "secret",
      body: { chatId: "21621345678@c.us", session: "default" },
    });
    expect(naps.length).toBeGreaterThan(0);
  });

  it("fails with a safe word that holds no number and no code", async () => {
    const t = new WahaTransport({
      url: "http://waha:3000",
      apiKey: "k",
      gapMs: () => 0,
      fetchImpl: (async () => {
        throw new Error("connect ECONNREFUSED 21621345678 code ABCD2345");
      }) as unknown as typeof fetch,
    });
    await expect(t.send("+21621345678", "x")).rejects.toThrow(
      /^WHATSAPP_UNREACHABLE$/,
    );
    expect(await t.status()).toBe("DISCONNECTED");
  });
});
