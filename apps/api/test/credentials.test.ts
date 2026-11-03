import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { Database } from "../src/core/database";
import { SettingsService } from "../src/core/settings";
import { EmailDelivery, type EmailTransport } from "../src/email/delivery";
import { generateTempPassword } from "../src/core/temp-password";
import { decryptSecret } from "../src/modules/auth/mfa";
import { WhatsAppDelivery } from "../src/whatsapp/delivery";
import type { WhatsAppTransport } from "../src/whatsapp/transport";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
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
  api.app.get(SettingsService).forget();
});

type JobRow = { id: string; key: string; kind: string; payload: any };

async function jobs(kind: string): Promise<JobRow[]> {
  const o = await owner();
  try {
    return (
      await o.query(
        `SELECT id, key, kind, payload FROM "Job" WHERE payload->>'template' = 'credentials' AND kind = $1 ORDER BY "createdAt"`,
        [kind],
      )
    ).rows;
  } finally {
    await o.end();
  }
}

/** The temporary password of the latest message, as the person would read it. */
async function latestPassword() {
  const job = (await jobs("email")).at(-1)!;
  return decryptSecret(job.payload.sealed);
}

async function userRow(email: string) {
  const o = await owner();
  try {
    return (
      await o.query(
        `SELECT id, status, role, "passwordHash", "mustChangePassword", "passwordExpiresAt", "canOrder" FROM "User" WHERE email = $1`,
        [email],
      )
    ).rows[0];
  } finally {
    await o.end();
  }
}

const login = (email: string, password: string) =>
  client(api).post("/v1/auth/login", { email, password });

/** A responsable adds a member; the admin approves: the account and its password are made then. */
async function addAndApprove(
  duties = { sells: true, buys: false },
  email = "amira@example.test",
) {
  const pdv = await approvedPdv(w);
  const added = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
    name: "Amira Gharbi",
    email,
    phone: "21 345 678",
    duties,
  });
  expect(added.status).toBe(201);
  const approved = await w.a.post(`/v1/users/${added.body.id}/approve`, {});
  expect(approved.status).toBe(201);
  return { pdv, id: added.body.id as string, email };
}

describe("the generated password", () => {
  it("is ten readable characters with a capital, a lower-case letter and a digit, never twice the same", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 300; i++) {
      const p = generateTempPassword();
      expect(p).toHaveLength(10);
      expect(p).toMatch(/[A-Z]/);
      expect(p).toMatch(/[a-z]/);
      expect(p).toMatch(/[0-9]/);
      expect(p).not.toMatch(/[0OIl1]/);
      seen.add(p);
    }
    expect(seen.size).toBe(300);
  });
});

describe("a team member's account", () => {
  it("waits for the admin's approval, then gets a password by email and WhatsApp together", async () => {
    const pdv = await approvedPdv(w);
    const added = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Amira Gharbi",
      email: "amira@example.test",
      phone: "21 345 678",
    });
    expect(added.body.status).toBe("PENDING");
    // Nothing is made or sent before the approval: no password, no message.
    expect((await userRow("amira@example.test")).passwordHash).toBeNull();
    expect(await jobs("email")).toHaveLength(0);

    await w.a.post(`/v1/users/${added.body.id}/approve`, {});
    const user = await userRow("amira@example.test");
    expect(user).toMatchObject({
      status: "ACTIVE",
      mustChangePassword: true,
    });
    expect(user.passwordHash).toMatch(/^\$argon2id/);
    const days =
      (new Date(user.passwordExpiresAt).getTime() - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(6.9);
    expect(days).toBeLessThan(7.1);
    // One email and one WhatsApp message, made in the same moment, and no activation code anywhere.
    expect(await jobs("email")).toHaveLength(1);
    expect(await jobs("whatsapp")).toHaveLength(1);
    const o = await owner();
    try {
      expect(
        (
          await o.query(`SELECT 1 FROM "AccessToken" WHERE "userId" = $1`, [
            user.id,
          ])
        ).rowCount,
      ).toBe(0);
    } finally {
      await o.end();
    }
  });

  it("the password is never stored or queued in the clear", async () => {
    await addAndApprove();
    const password = await latestPassword();
    const o = await owner();
    try {
      const all = JSON.stringify(
        (await o.query(`SELECT payload FROM "Job"`)).rows,
      );
      expect(all).not.toContain(password);
      const audit = JSON.stringify(
        (await o.query(`SELECT details FROM "AuditEntry"`)).rows,
      );
      expect(audit).not.toContain(password);
      expect(
        (await o.query(`SELECT "passwordHash" FROM "User"`)).rows.some(
          (r: any) => r.passwordHash === password,
        ),
      ).toBe(false);
    } finally {
      await o.end();
    }
  });

  it("the admin creates a buyer: the account is active at once and the password is sent", async () => {
    const pdv = await approvedPdv(w);
    const made = await w.a.post("/v1/users", {
      role: "ACHETEUR",
      pdvId: pdv.id,
      name: "Aya Acheteuse",
      email: "aya@example.test",
      phone: "22 123 456",
    });
    expect(made.status).toBe(201);
    expect(await userRow("aya@example.test")).toMatchObject({
      status: "ACTIVE",
      role: "ACHETEUR",
      mustChangePassword: true,
    });
    expect(await jobs("email")).toHaveLength(1);
    expect(await jobs("whatsapp")).toHaveLength(1);
    expect(
      (await login("aya@example.test", await latestPassword())).status,
    ).toBe(201);
  });

  it("a responsable, an order manager and an admin are still invited with a code", async () => {
    const made = await w.a.post("/v1/users", {
      role: "ORDERS",
      name: "Omar Orders",
      email: "omar@example.test",
      phone: "22 123 457",
    });
    expect(made.status).toBe(201);
    expect(await jobs("email")).toHaveLength(0);
    const o = await owner();
    try {
      expect(
        (
          await o.query(
            `SELECT 1 FROM "Job" WHERE kind = 'email' AND payload->>'template' = 'invite'`,
          )
        ).rowCount,
      ).toBe(1);
    } finally {
      await o.end();
    }
  });
});

describe("the first sign-in", () => {
  it("works with the generated password, and nothing else works until a new one is chosen", async () => {
    const { email } = await addAndApprove();
    const password = await latestPassword();
    const res = await login(email, password);
    expect(res.status).toBe(201);
    expect(res.body.me).toMatchObject({ mustChangePassword: true });
    const c = client(api, res.body.token);
    // Only who I am, my password and signing out answer.
    expect((await c.get("/v1/me")).body.mustChangePassword).toBe(true);
    for (const route of [
      "/v1/dashboard",
      "/v1/products",
      "/v1/notifications",
      "/v1/wallet",
    ]) {
      const blocked = await c.get(route);
      expect(blocked.status, route).toBe(403);
      expect(blocked.body.code).toBe("PASSWORD_CHANGE_REQUIRED");
    }
    expect(
      (await c.post("/v1/me/push-device", { platform: "ANDROID", token: "x" }))
        .status,
    ).toBe(403);
  });

  it("choosing a new password opens everything and kills the generated one", async () => {
    const { email } = await addAndApprove();
    const temp = await latestPassword();
    const first = await login(email, temp);
    const c = client(api, first.body.token);
    // Too short is refused; no current password is asked for.
    expect((await c.post("/v1/me/password", { next: "short" })).status).toBe(
      400,
    );
    const changed = await c.post("/v1/me/password", {
      next: "My-own-password-42",
    });
    expect(changed.status).toBe(201);
    expect((await c.get("/v1/me")).body.mustChangePassword).toBe(false);
    expect((await c.get("/v1/products")).status).toBe(200);
    expect(await userRow(email)).toMatchObject({
      mustChangePassword: false,
      passwordExpiresAt: null,
    });
    expect((await login(email, temp)).status).toBe(401);
    expect((await login(email, "My-own-password-42")).status).toBe(201);
    // A later change asks for the current password again.
    const d = client(
      api,
      (await login(email, "My-own-password-42")).body.token,
    );
    expect(
      (await d.post("/v1/me/password", { next: "Another-one-77" })).status,
    ).toBe(401);
  });

  it("an expired generated password says so, to the person who knows it and to nobody else", async () => {
    const { email, id } = await addAndApprove();
    const temp = await latestPassword();
    const o = await owner();
    try {
      await o.query(
        `UPDATE "User" SET "passwordExpiresAt" = now() - interval '1 minute' WHERE id = $1`,
        [id],
      );
    } finally {
      await o.end();
    }
    const expired = await login(email, temp);
    expect(expired.status).toBe(401);
    expect(expired.body.code).toBe("TEMP_PASSWORD_EXPIRED");
    // A wrong password gives the usual answer: nothing is learned.
    expect((await login(email, "wrong-password-1")).body.code).toBe(
      "INVALID_CREDENTIALS",
    );
  });

  it("a session opened before the expiry stops working when it comes", async () => {
    const { email, id } = await addAndApprove();
    const first = await login(email, await latestPassword());
    const o = await owner();
    try {
      await o.query(
        `UPDATE "User" SET "passwordExpiresAt" = now() - interval '1 minute' WHERE id = $1`,
        [id],
      );
    } finally {
      await o.end();
    }
    expect((await client(api, first.body.token).get("/v1/me")).status).toBe(
      401,
    );
  });

  it("a reset by code while still on the generated password leaves nothing temporary", async () => {
    const { email } = await addAndApprove();
    const anon = client(api);
    expect(
      (await anon.post("/v1/auth/forgot-password", { email })).status,
    ).toBeLessThan(300);
    const o = await owner();
    let code: string;
    try {
      code = (
        await o.query(
          `SELECT payload->>'code' AS code FROM "Job" WHERE kind = 'email' AND payload->>'template' = 'reset'`,
        )
      ).rows[0].code;
    } finally {
      await o.end();
    }
    const reset = await anon.post("/v1/auth/reset-password", {
      email,
      code,
      password: "Chosen-by-reset-9",
    });
    expect(reset.status).toBeLessThan(300);
    expect(await userRow(email)).toMatchObject({
      mustChangePassword: false,
      passwordExpiresAt: null,
    });
    expect(
      (await login(email, "Chosen-by-reset-9")).body.me.mustChangePassword,
    ).toBe(false);
  });
});

describe("sending a new password", () => {
  it("the old one stops working at once and the new one is sent", async () => {
    const { email, id } = await addAndApprove();
    const old = await latestPassword();
    const session = (await login(email, old)).body.token as string;
    const sent = await w.n.post(`/v1/users/${id}/resend-invite`, {});
    expect(sent.status).toBe(201);
    expect(await jobs("email")).toHaveLength(2);
    expect(await jobs("whatsapp")).toHaveLength(2);
    const fresh = await latestPassword();
    expect(fresh).not.toBe(old);
    expect((await login(email, old)).status).toBe(401);
    expect((await client(api, session).get("/v1/me")).status).toBe(401);
    expect((await login(email, fresh)).status).toBe(201);
  });

  it("is refused for someone who already chose their own password, and for another region", async () => {
    const { id } = await addAndApprove();
    expect((await w.s.post(`/v1/users/${id}/resend-invite`, {})).status).toBe(
      404,
    );
    const o = await owner();
    try {
      await o.query(
        `UPDATE "User" SET "mustChangePassword" = false WHERE id = $1`,
        [id],
      );
    } finally {
      await o.end();
    }
    expect(
      (await w.n.post(`/v1/users/${id}/resend-invite`, {})).body.code,
    ).toBe("INVALID_STATE");
  });

  it("changing the email or the number while it waits sends a new one to the new contacts", async () => {
    const { id } = await addAndApprove();
    const old = await latestPassword();
    const edited = await w.a.patch(`/v1/users/${id}`, {
      email: "amira.new@example.test",
      phone: "22 333 444",
    });
    expect(edited.status).toBe(200);
    expect(await jobs("email")).toHaveLength(2);
    expect((await login("amira.new@example.test", old)).status).toBe(401);
    expect(
      (await login("amira.new@example.test", await latestPassword())).status,
    ).toBe(201);
  });

  it("an invitation can be taken back before the first sign-in, and the email is free again", async () => {
    const { id, email } = await addAndApprove();
    expect((await w.n.post(`/v1/users/${id}/cancel-invite`, {})).status).toBe(
      201,
    );
    expect(await userRow(email)).toBeUndefined();
  });

  it("an approval taken back kills the password that was sent", async () => {
    const { id, email } = await addAndApprove();
    const temp = await latestPassword();
    expect((await w.a.post(`/v1/users/${id}/reopen`, {})).status).toBe(201);
    expect(await userRow(email)).toMatchObject({
      status: "PENDING",
      mustChangePassword: false,
    });
    expect((await login(email, temp)).status).toBe(401);
  });
});

describe("the messages", () => {
  const sender = (
    sent: { to: string; subject: string; text: string; html: string }[],
  ): EmailTransport => ({
    send: async (to, content) => {
      sent.push({ to, ...content });
    },
  });
  const settings = {
    get: async () => ({
      whatsapp: { enabled: true },
      stores: {
        ios: "https://apps.apple.com/app/id1",
        android:
          "https://play.google.com/store/apps/details?id=tn.biobalance.app",
      },
    }),
  } as unknown as SettingsService;

  it("the email carries the address, the password, the links and the date; then the password is wiped from the queue", async () => {
    await addAndApprove();
    const password = await latestPassword();
    const sent: { to: string; subject: string; text: string; html: string }[] =
      [];
    const job = (await jobs("email"))[0]!;
    const delivery = new EmailDelivery(db, sender(sent), settings);
    expect(await delivery.deliver(job, async () => true)).toBe("accepted");
    expect(sent).toHaveLength(1);
    expect(sent[0]!.to).toBe("amira@example.test");
    expect(sent[0]!.subject).toBe("Votre compte BioBalance est prêt");
    for (const part of [sent[0]!.text, sent[0]!.html]) {
      expect(part).toContain(password);
      expect(part).toContain("amira@example.test");
      expect(part).toContain("play.google.com");
    }
    expect(sent[0]!.text).toContain("Amira Gharbi");
    // Sent: the password is gone from the stored message, so a retry or a leak finds nothing.
    const after = (await jobs("email"))[0]!;
    expect(after.payload.sealed).toBe("");
    expect(await delivery.deliver(after, async () => true)).toBe("suppressed");
    expect(sent).toHaveLength(1);
  });

  it("WhatsApp carries the same, in the person's language, and wipes it too", async () => {
    await addAndApprove();
    const password = await latestPassword();
    const sent: { phone: string; text: string }[] = [];
    const transport: WhatsAppTransport = {
      hasWhatsApp: async () => true,
      send: async (phone, text) => {
        sent.push({ phone, text });
      },
      status: async () => "CONNECTED",
    };
    const job = (await jobs("whatsapp"))[0]!;
    const delivery = new WhatsAppDelivery(db, transport, settings);
    expect(await delivery.deliver(job)).toBe("sent");
    expect(sent[0]!.phone).toBe("+21621345678");
    expect(sent[0]!.text).toContain(password);
    expect(sent[0]!.text).toContain("Bonjour Amira Gharbi");
    expect(sent[0]!.text).toContain("amira@example.test");
    expect((await jobs("whatsapp"))[0]!.payload.sealed).toBe("");
  });

  it("a replaced or changed password is never sent on a retry", async () => {
    const { id } = await addAndApprove();
    const first = (await jobs("email"))[0]!;
    await w.n.post(`/v1/users/${id}/resend-invite`, {});
    const sent: { to: string; subject: string; text: string; html: string }[] =
      [];
    const delivery = new EmailDelivery(db, sender(sent), settings);
    // The first message holds a password that no longer works: it is dropped.
    expect(await delivery.deliver(first, async () => true)).toBe("suppressed");
    expect(sent).toHaveLength(0);
    // The latest one goes out.
    expect(
      await delivery.deliver((await jobs("email"))[1]!, async () => true),
    ).toBe("accepted");
  });

  it("nothing leaves the test region and a deactivated person gets nothing", async () => {
    const { id } = await addAndApprove();
    await w.n.post(`/v1/users/${id}/suspend`, { note: "left" });
    const sent: { to: string; subject: string; text: string; html: string }[] =
      [];
    const delivery = new EmailDelivery(db, sender(sent), settings);
    expect(
      await delivery.deliver((await jobs("email"))[0]!, async () => true),
    ).toBe("suppressed");
    expect(sent).toHaveLength(0);
  });

  it("a number without WhatsApp or the channel off: the email still goes, the secret is wiped from the other", async () => {
    await addAndApprove();
    const transport: WhatsAppTransport = {
      hasWhatsApp: async () => false,
      send: async () => {
        throw new Error("never");
      },
      status: async () => "CONNECTED",
    };
    const delivery = new WhatsAppDelivery(db, transport, settings);
    expect(await delivery.deliver((await jobs("whatsapp"))[0]!)).toBe(
      "suppressed",
    );
    expect((await jobs("whatsapp"))[0]!.payload.sealed).toBe("");
    // The email job is a separate copy and is untouched.
    expect((await jobs("email"))[0]!.payload.sealed).not.toBe("");
  });
});
