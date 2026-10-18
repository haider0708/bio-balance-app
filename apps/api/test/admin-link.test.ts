import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Secret, TOTP } from "otpauth";
import { Database } from "../src/core/database";
import { addAdministrator } from "../src/modules/auth/admins";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";

let api: Api;
let db: Database;
beforeAll(async () => {
  await resetDatabase();
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api?.close());

const tokenOf = (link: string) => link.split("#")[1]!;
const claim = (token: string) =>
  client(api).post("/v1/setup-link/claim", { token });
const code = (key: string) =>
  new TOTP({
    secret: Secret.fromBase32(key),
    digits: 6,
    period: 30,
  }).generate();

describe("adding an administrator", () => {
  it("shows the QR code once through a link, and the new admin can sign in with it", async () => {
    const link = await addAdministrator(
      db,
      {
        email: "Second.Admin@Example.test",
        name: "Second Admin",
        password: "a-long-test-password",
      },
      "https://api.example.test/",
    );
    expect(link).toMatch(/^https:\/\/api\.example\.test\/s#[\w-]{40,}$/);

    // The page itself carries no secret and cannot be framed or indexed.
    const page = await fetch(`${api.url}/s`);
    expect(page.status).toBe(200);
    expect(page.headers.get("content-security-policy")).toContain(
      "frame-ancestors 'none'",
    );
    expect(await page.text()).not.toContain(tokenOf(link));

    const first = await claim(tokenOf(link));
    expect(first.status).toBe(201);
    expect(first.body.svg).toContain("<svg");
    expect(first.body.key).toMatch(/^[A-Z2-7]{32}$/);
    // One look only.
    const second = await claim(tokenOf(link));
    expect(second.status).toBe(410);
    expect(second.body.code).toBe("LINK_USED");

    // The password alone is not enough; with the app's code the admin is in.
    const noCode = await client(api).post("/v1/auth/login", {
      email: "second.admin@example.test",
      password: "a-long-test-password",
    });
    expect(noCode.status).toBe(401);
    expect(noCode.body.code).toBe("MFA_REQUIRED");
    const signedIn = await client(api).post("/v1/auth/login", {
      email: "second.admin@example.test",
      password: "a-long-test-password",
      otp: code(first.body.key),
    });
    expect(signedIn.status).toBe(201);
    expect(signedIn.body.me.role).toBe("ADMIN");

    // Nothing of the secret stays in the database.
    const ownerDb = await owner();
    try {
      const { rows } = await ownerDb.query(
        `SELECT secret, "usedAt" FROM "SetupLink"`,
      );
      expect(rows[0].secret).toBeNull();
      expect(rows[0].usedAt).not.toBeNull();
    } finally {
      await ownerDb.end();
    }
  });

  it("refuses a made-up link, an expired link and an email that already has an account", async () => {
    expect((await claim("x".repeat(43))).status).toBe(410);
    expect((await claim("short")).status).toBe(410);
    const link = await addAdministrator(
      db,
      {
        email: "late@example.test",
        name: "Late Admin",
        password: "a-long-test-password",
      },
      "https://api.example.test",
    );
    const ownerDb = await owner();
    try {
      await ownerDb.query(
        `UPDATE "SetupLink" SET "expiresAt" = now() - interval '1 minute'`,
      );
    } finally {
      await ownerDb.end();
    }
    expect((await claim(tokenOf(link))).status).toBe(410);
    await expect(
      addAdministrator(
        db,
        {
          email: "late@example.test",
          name: "Again",
          password: "a-long-test-password",
        },
        "https://api.example.test",
      ),
    ).rejects.toThrow("already has an account");
  });

  it("gives a fresh authenticator on request, ending the old one and the sessions", async () => {
    const first = await claim(
      tokenOf(
        await addAdministrator(
          db,
          {
            email: "again@example.test",
            name: "Again Admin",
            password: "a-long-test-password",
          },
          "https://api.example.test",
        ),
      ),
    );
    const session = await client(api).post("/v1/auth/login", {
      email: "again@example.test",
      password: "a-long-test-password",
      otp: code(first.body.key),
    });
    expect(session.status).toBe(201);

    const newLink = await addAdministrator(
      db,
      { email: "again@example.test", again: true },
      "https://api.example.test",
    );
    // The signed-in session ended, the old code no longer works, the new key does.
    expect((await client(api, session.body.token).get("/v1/me")).status).toBe(
      401,
    );
    const next = await claim(tokenOf(newLink));
    expect(next.body.key).not.toBe(first.body.key);
    const old = await client(api).post("/v1/auth/login", {
      email: "again@example.test",
      password: "a-long-test-password",
      otp: code(first.body.key),
    });
    expect(old.status).toBe(401);
  });

  it("a kept link can be opened again and again, even past its expiry", async () => {
    const link = await addAdministrator(
      db,
      {
        email: "keep.admin@example.test",
        name: "Keep Admin",
        password: "a-long-test-password",
      },
      "https://api.example.test/",
    );
    const o = await owner();
    try {
      await o.query(
        `UPDATE "SetupLink" SET keep = true, "expiresAt" = now() - interval '1 day'`,
      );
    } finally {
      await o.end();
    }
    const first = await claim(tokenOf(link));
    const second = await claim(tokenOf(link));
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.body.key).toBe(first.body.key);
  });
});
