import "reflect-metadata";
import type { INestApplication } from "@nestjs/common";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import path from "node:path";
import { mkdtempSync } from "node:fs";
import { Client } from "pg";
import { tokenHash } from "../src/modules/auth/codes";

const appUrl =
  process.env.TEST_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
const ownerUrl =
  process.env.TEST_OWNER_DATABASE_URL ??
  "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test";

process.env.DATABASE_URL = appUrl;
process.env.MFA_ENCRYPTION_KEY ??= randomBytes(32).toString("base64");
process.env.MEDIA_ROOT = mkdtempSync(path.join(tmpdir(), "bb-media-"));
process.env.NODE_ENV = "test";

export interface Api {
  url: string;
  app: INestApplication;
  close(): Promise<void>;
}

export async function startApi(): Promise<Api> {
  const { bootstrap } = await import("../src/main");
  process.env.PORT = "0";
  const app = await bootstrap();
  const address = app.getHttpServer().address();
  return {
    url: `http://127.0.0.1:${address.port}`,
    app,
    close: () => app.close(),
  };
}

/** A direct connection as the table owner, used to prepare and inspect data. */
export async function owner() {
  const client = new Client({ connectionString: ownerUrl });
  await client.connect();
  return client;
}

/** Empty every business table (the three fixed regions stay). */
export async function resetDatabase() {
  const db = await owner();
  try {
    const { rows } = await db.query<{ tablename: string }>(
      `SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename NOT IN ('_prisma_migrations','Region')`,
    );
    await db.query(
      `TRUNCATE ${rows.map((r) => `"${r.tablename}"`).join(",")} RESTART IDENTITY CASCADE`,
    );
  } finally {
    await db.end();
  }
}

export interface Account {
  id: string;
  email: string;
  token: string;
}

/** Create an active account with a live session, skipping the sign-in screen. */
export async function createAccount(input: {
  role: "ADMIN" | "RESPONSABLE" | "GROSSISTE" | "VENDEUR";
  email?: string;
  name?: string;
  regionCode?: string;
  pdvId?: string;
  depot?: { name: string };
  status?: "ACTIVE" | "PENDING";
}): Promise<Account> {
  const db = await owner();
  try {
    const email =
      input.email ??
      `${input.role.toLowerCase()}-${randomBytes(4).toString("hex")}@example.test`;
    let regionId: string | null = null;
    if (input.regionCode)
      regionId = (
        await db.query(`SELECT id FROM "Region" WHERE code=$1`, [
          input.regionCode,
        ])
      ).rows[0].id;
    if (input.pdvId && !regionId)
      regionId = (
        await db.query(`SELECT "regionId" FROM "Pdv" WHERE id=$1`, [
          input.pdvId,
        ])
      ).rows[0].regionId;
    const { rows } = await db.query(
      `INSERT INTO "User"(id,email,name,role,status,"regionId","pdvId","passwordHash")
       VALUES (gen_random_uuid(),$1,$2,$3::"Role",$4::"Status",$5,$6,'x') RETURNING id`,
      [
        email,
        input.name ?? email.split("@")[0],
        input.role,
        input.status ?? "ACTIVE",
        regionId,
        input.pdvId ?? null,
      ],
    );
    const id = rows[0].id as string;
    if (input.depot)
      await db.query(
        `INSERT INTO "Depot"(id,"userId",name,address,city) VALUES (gen_random_uuid(),$1,$2,'1 rue du Test','Tunis')`,
        [id, input.depot.name],
      );
    const token = randomBytes(32).toString("base64url");
    await db.query(
      `INSERT INTO "Session"(id,"userId","tokenHash","expiresAt") VALUES (gen_random_uuid(),$1,$2,now()+interval '1 day')`,
      [id, tokenHash(token)],
    );
    return { id, email, token };
  } finally {
    await db.end();
  }
}

export async function regionId(code: string) {
  const db = await owner();
  try {
    return (await db.query(`SELECT id FROM "Region" WHERE code=$1`, [code]))
      .rows[0].id as string;
  } finally {
    await db.end();
  }
}

export interface Response<T = any> {
  status: number;
  body: T;
}

/** A tiny typed fetch client for the API under test. */
export function client(api: Api, token?: string) {
  const call = async <T = any>(
    method: string,
    route: string,
    body?: unknown,
  ): Promise<Response<T>> => {
    const res = await fetch(`${api.url}${route}`, {
      method,
      headers: {
        ...(token && { Authorization: `Bearer ${token}` }),
        ...(body !== undefined && { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : undefined };
  };
  return {
    get: <T = any>(r: string) => call<T>("GET", r),
    post: <T = any>(r: string, b: unknown = {}) => call<T>("POST", r, b),
    patch: <T = any>(r: string, b: unknown) => call<T>("PATCH", r, b),
    put: <T = any>(r: string, b: unknown) => call<T>("PUT", r, b),
    delete: <T = any>(r: string) => call<T>("DELETE", r),
    upload: async (purpose: string, bytes: Buffer): Promise<Response> => {
      const res = await fetch(
        `${api.url}/v1/media?purpose=${purpose}&filename=photo.jpg`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/octet-stream",
          },
          body: new Uint8Array(bytes),
        },
      );
      return { status: res.status, body: await res.json() };
    },
  };
}

/** The smallest valid JPEG header followed by filler: enough for the content check. */
export const fakeJpeg = () =>
  Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), randomBytes(2000)]);
