import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import argon2 from "argon2";
import {
  createAccount,
  client,
  owner,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { encryptSecret, totp } from "../src/modules/auth/mfa";
import { Secret } from "otpauth";

let api: Api;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(resetDatabase);

describe("sign-in", () => {
  it("signs a responsable in and returns who they are", async () => {
    const db = await owner();
    const hash = await argon2.hash("a-long-password", {
      type: argon2.argon2id,
    });
    await db.query(
      `INSERT INTO "User"(id,email,name,role,status,"regionId","passwordHash")
       VALUES (gen_random_uuid(),'nord@example.test','Nora','RESPONSABLE','ACTIVE',(SELECT id FROM "Region" WHERE code='NORD'),$1)`,
      [hash],
    );
    await db.end();
    const anon = client(api);
    const login = await anon.post("/v1/auth/login", {
      email: "Nord@Example.test",
      password: "a-long-password",
    });
    expect(login.status).toBe(201);
    expect(login.body.me).toMatchObject({
      role: "RESPONSABLE",
      region: { code: "NORD" },
    });
    const me = await client(api, login.body.token).get("/v1/me");
    expect(me.body.email).toBe("nord@example.test");
  });

  it("refuses a wrong password and unknown accounts the same way", async () => {
    const anon = client(api);
    const a = await anon.post("/v1/auth/login", {
      email: "nobody@example.test",
      password: "whatever-password",
    });
    expect(a.status).toBe(401);
    expect(a.body.code).toBe("INVALID_CREDENTIALS");
  });

  it("requires the authenticator code for the admin", async () => {
    const secret = new Secret({ size: 20 });
    const db = await owner();
    const hash = await argon2.hash("admin-password-123", {
      type: argon2.argon2id,
    });
    await db.query(
      `INSERT INTO "User"(id,email,name,role,status,"passwordHash","mfaSecret") VALUES (gen_random_uuid(),'admin@example.test','Admin','ADMIN','ACTIVE',$1,$2)`,
      [hash, encryptSecret(secret.hex)],
    );
    await db.end();
    const anon = client(api);
    const noCode = await anon.post("/v1/auth/login", {
      email: "admin@example.test",
      password: "admin-password-123",
    });
    expect(noCode.body.code).toBe("MFA_REQUIRED");
    const step = BigInt(Math.floor(Date.now() / 30_000));
    const ok = await anon.post("/v1/auth/login", {
      email: "admin@example.test",
      password: "admin-password-123",
      otp: totp(secret.hex, step),
    });
    expect(ok.status).toBe(201);
    // The same code cannot be replayed.
    const replay = await anon.post("/v1/auth/login", {
      email: "admin@example.test",
      password: "admin-password-123",
      otp: totp(secret.hex, step),
    });
    expect(replay.status).toBe(401);
  });

  it("rejects requests without a session", async () => {
    expect((await client(api).get("/v1/me")).status).toBe(401);
  });
});

describe("invitation and password reset", () => {
  it("lets an approved member activate with the code from the email", async () => {
    const admin = await createAccount({ role: "ADMIN" });
    const a = client(api, admin.token);
    const nord = (await a.get("/v1/regions")).body.find(
      (r: any) => r.code === "NORD",
    );
    const created = await a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: nord.id,
      name: "Nora Nord",
      email: "nora@example.test",
    });
    expect(created.status).toBe(201);
    expect(created.body.activated).toBe(false);

    const db = await owner();
    const job = (
      await db.query(
        `SELECT payload FROM "Job" WHERE kind='email' ORDER BY "createdAt" DESC LIMIT 1`,
      )
    ).rows[0].payload;
    await db.end();
    expect(job.template).toBe("invite");

    const anon = client(api);
    const bad = await anon.post("/v1/auth/activate", {
      email: "nora@example.test",
      code: "ZZZZZZZZ",
      password: "a-long-password",
    });
    expect(bad.body.code).toBe("INVALID_CODE");
    const ok = await anon.post("/v1/auth/activate", {
      email: "nora@example.test",
      code: job.code,
      password: "a-long-password",
    });
    expect(ok.status).toBe(201);
    const login = await anon.post("/v1/auth/login", {
      email: "nora@example.test",
      password: "a-long-password",
    });
    expect(login.status).toBe(201);
    // A used code is dead.
    const again = await anon.post("/v1/auth/activate", {
      email: "nora@example.test",
      code: job.code,
      password: "another-long-password",
    });
    expect(again.status).toBe(422);
  });

  it("resets a forgotten password and closes old sessions", async () => {
    const db = await owner();
    const hash = await argon2.hash("old-password-123", {
      type: argon2.argon2id,
    });
    await db.query(
      `INSERT INTO "User"(id,email,name,role,status,"passwordHash") VALUES (gen_random_uuid(),'g@example.test','G','GROSSISTE','ACTIVE',$1)`,
      [hash],
    );
    const anon = client(api);
    const first = await anon.post("/v1/auth/login", {
      email: "g@example.test",
      password: "old-password-123",
    });
    expect(
      (await anon.post("/v1/auth/forgot-password", { email: "g@example.test" }))
        .status,
    ).toBe(201);
    expect(
      (
        await anon.post("/v1/auth/forgot-password", {
          email: "unknown@example.test",
        })
      ).status,
    ).toBe(201);
    const code = (
      await db.query(`SELECT payload FROM "Job" WHERE key LIKE 'reset:%'`)
    ).rows[0].payload.code;
    await db.end();
    const reset = await anon.post("/v1/auth/reset-password", {
      email: "g@example.test",
      code,
      password: "brand-new-password",
    });
    expect(reset.status).toBe(201);
    expect((await client(api, first.body.token).get("/v1/me")).status).toBe(
      401,
    );
    expect(
      (
        await anon.post("/v1/auth/login", {
          email: "g@example.test",
          password: "brand-new-password",
        })
      ).status,
    ).toBe(201);
  });
});

describe("taking back an invitation", () => {
  it("kills the code and frees the email before activation, and refuses once the account exists", async () => {
    const admin = await createAccount({ role: "ADMIN" });
    const a = client(api, admin.token);
    const regions = (await a.get("/v1/regions")).body;
    const nord = regions.find((r: any) => r.code === "NORD");
    const sud = regions.find((r: any) => r.code === "SUD");
    const created = await a.post("/v1/users", {
      role: "GROSSISTE",
      regionId: nord.id,
      name: "Mounir",
      email: "mounir@example.test",
      depot: { name: "Depot Sfax", address: "ZI", city: "Sfax" },
    });
    const db = await owner();
    const code = (
      await db.query(
        `SELECT payload FROM "Job" WHERE kind='email' ORDER BY "createdAt" DESC LIMIT 1`,
      )
    ).rows[0].payload.code;
    await db.end();

    expect(
      (await a.post(`/v1/users/${created.body.id}/cancel-invite`)).status,
    ).toBe(201);
    const anon = client(api);
    const dead = await anon.post("/v1/auth/activate", {
      email: "mounir@example.test",
      code,
      password: "a-long-password",
    });
    expect(dead.status).toBe(422);
    // The address is free again, with a fresh depot.
    const again = await a.post("/v1/users", {
      role: "GROSSISTE",
      regionId: sud.id,
      name: "Mounir",
      email: "mounir@example.test",
      depot: { name: "Depot Gabes", address: "ZI", city: "Gabes" },
    });
    expect(again.status).toBe(201);

    // Once the person has an account, only deactivation is left.
    const db2 = await owner();
    const fresh = (
      await db2.query(
        `SELECT payload FROM "Job" WHERE kind='email' ORDER BY "createdAt" DESC LIMIT 1`,
      )
    ).rows[0].payload.code;
    await db2.end();
    await anon.post("/v1/auth/activate", {
      email: "mounir@example.test",
      code: fresh,
      password: "a-long-password",
    });
    const refused = await a.post(`/v1/users/${again.body.id}/cancel-invite`);
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("ALREADY_ACTIVATED");
    expect(
      (await a.post(`/v1/users/${again.body.id}/suspend`, {})).body.status,
    ).toBe("SUSPENDED");
  });
});
