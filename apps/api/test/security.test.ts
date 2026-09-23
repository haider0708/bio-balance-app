import { assertTestDatabases } from "./test-database.cjs";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createHash, randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { Database } from "../src/shared/infrastructure/database";
import { cleanupAuthentication } from "../src/shared/jobs/maintenance";
import { bootstrap } from "../src/main";
import { tokenHash } from "../src/modules/identity/identity.service";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw Error("ISOLATED_TEST_DATABASE_REQUIRED");
assertTestDatabases(process.env.DATABASE_URL);
const db = new Database();
const second = new Database();
const prefix = (id: string) => createHash("sha256").update(id).digest("hex");
let app: Awaited<ReturnType<typeof bootstrap>>, origin: string;
beforeAll(async () => {
  process.env.PORT = "0";
  app = await bootstrap();
  origin = `http://127.0.0.1:${app.getHttpServer().address().port}`;
});
afterAll(async () => {
  await app?.close();
  await db.$disconnect();
  await second.$disconnect();
});

it("does not apply general authenticated quotas across sessions; preserves no-store and logout", async () => {
  const user = await db.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Security test",
      passwordHash: "not-a-login",
    },
  });
  const tokens = [randomUUID(), randomUUID()];
  for (const token of tokens)
    await db.session.create({
      data: {
        userId: user.id,
        tokenHash: tokenHash(token),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
  await db.requestBudget.create({
    data: { key: `${prefix(user.id)}:read`, count: 359 },
  });
  const first = await fetch(`${origin}/v1/identity/me`, {
    headers: { authorization: `Bearer ${tokens[0]}` },
  });
  expect(first.status).toBe(200);
  expect(first.headers.get("cache-control")).toBe("no-store");
  const rejected = await fetch(`${origin}/v1/identity/me`, {
    headers: { authorization: `Bearer ${tokens[1]}` },
  });
  expect(rejected.status).toBe(200);
  expect(rejected.headers.get("retry-after")).toBeNull();
  await db.requestBudget.create({data:{key:`${prefix(user.id)}:all`,count:1200}});
  const logout = await fetch(`${origin}/v1/identity/logout`, {
    method: "POST",
    headers: { authorization: `Bearer ${tokens[0]}` },
  });
  expect(logout.status).toBe(201);
  expect(
    (
      await db.session.findUniqueOrThrow({
        where: { tokenHash: tokenHash(tokens[0]!) },
      })
    ).revokedAt,
  ).not.toBeNull();
});

it("rejects compressed request bodies and exposes bounded HTTP timeouts", async () => {
  const response = await fetch(`${origin}/v1/identity/login`, {
    method: "POST",
    headers: { "content-type": "application/json", "content-encoding": "gzip" },
    body: gzipSync('{"email":"a@example.test"}'),
  });
  expect(response.status).toBe(415);
  expect(await response.json()).toMatchObject({ code: "HTTP_415" });
  expect(app.getHttpServer().headersTimeout).toBe(10000);
  expect(app.getHttpServer().requestTimeout).toBe(30000);
});

it("expires abuse telemetry without deleting current counters", async () => {
  const old = randomUUID(),
    current = randomUUID();
  await db.requestBudget.createMany({
    data: [
      { key: old, count: 1, windowStart: new Date(Date.now() - 90000000) },
      { key: current, count: 1 },
    ],
  });
  await cleanupAuthentication(db);
  expect(await db.requestBudget.findUnique({ where: { key: old } })).toBeNull();
  expect(
    await db.requestBudget.findUnique({ where: { key: current } }),
  ).not.toBeNull();
});

it("maintenance rechecks expiry after a concurrent counter refresh", async () => {
  const key = `maintenance-${randomUUID()}`;
  await db.requestBudget.create({
    data: { key, count: 1, windowStart: new Date(Date.now() - 90000000) },
  });
  let unlock!: () => void, locked!: () => void;
  const release = new Promise<void>((r) => {
    unlock = r;
  });
  const ready = new Promise<void>((r) => {
    locked = r;
  });
  const refreshing = second.$transaction(
    async (tx) => {
      await tx.requestBudget.update({
        where: { key },
        data: { count: 2, windowStart: new Date() },
      });
      locked();
      await release;
    },
    { timeout: 10000 },
  );
  await ready;
  const cleaning = cleanupAuthentication(db);
  try {
    let waiting = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const [state] = await db.$queryRaw<{ waiting: boolean }[]>`SELECT EXISTS(
        SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND
        wait_event_type='Lock' AND query LIKE 'DELETE FROM "RequestBudget"%') AS waiting`;
      if (state?.waiting) {
        waiting = true;
        break;
      }
      await new Promise((r) => setTimeout(r, 10));
    }
    expect(waiting).toBe(true);
  } finally {
    unlock();
  }
  await refreshing;
  await cleaning;
  expect(
    (await db.requestBudget.findUniqueOrThrow({ where: { key } })).count,
  ).toBe(2);
});
