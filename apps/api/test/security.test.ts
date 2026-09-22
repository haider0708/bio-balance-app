import { assertTestDatabases } from "./test-database.cjs";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createHash, randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { Database } from "../src/shared/infrastructure/database";
import {
  RequestBudget,
  requestCategory,
} from "../src/shared/infrastructure/request-budget";
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
const budget = new RequestBudget(db),
  replica = new RequestBudget(second);
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

it("classifies expensive routes and counts sync work independently of batch size", async () => {
  expect(requestCategory("GET", "/v1/reports/stores/id/sales.csv")).toBe(
    "export",
  );
  expect(requestCategory("POST", "/v1/sync/push")).toBe("sync");
  expect(requestCategory("GET", "/V1/REPORTS/stores/id/sales.csv")).toBe(
    "export",
  );
  expect(requestCategory("GET", "/v1/stores/id/snapshot/")).toBe("export");
  expect(requestCategory("PUT", "/v1/media/uploads/id")).toBe("media");
  const id = randomUUID();
  for (let i = 0; i < 6; i++)
    await budget.consume(id, "POST", "/v1/sync/push", {
      operations: Array(100).fill({}),
    });
  await expect(
    replica.consume(id, "POST", "/v1/sync/status", { operations: [{}] }),
  ).rejects.toMatchObject({ code: "RATE_LIMITED", status: 429 });
  await expect(
    budget.consume(id, "GET", "/v1/stores"),
  ).resolves.toBeUndefined();
});

it("atomically limits concurrent replicas while preserving unrelated accounts", async () => {
  const id = randomUUID();
  const results = await Promise.allSettled(
    Array.from({ length: 25 }, (_, i) =>
      (i % 2 ? budget : replica).consume(id, "GET", "/v1/reports/overview"),
    ),
  );
  expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(12);
  for (const result of results)
    if (result.status === "rejected") {
      expect(result.reason.code).toBe("RATE_LIMITED");
      expect(result.reason.details.retryAfterSeconds).toBeGreaterThan(0);
      expect(result.reason.details.retryAfterSeconds).toBeLessThanOrEqual(60);
    }
  await expect(
    replica.consume(randomUUID(), "GET", "/v1/reports/overview"),
  ).resolves.toBeUndefined();
  const row = await db.requestBudget.findUniqueOrThrow({
    where: { key: `${prefix(id)}:export` },
  });
  expect(row.count).toBe(25);
  expect(row.key).not.toContain(id);
});

it("resets expired windows and never extends them with rejected requests", async () => {
  const id = randomUUID(),
    key = `${prefix(id)}:export`;
  await budget.consume(id, "GET", "/v1/reports/overview");
  const previous = await db.requestBudget.update({
    where: { key },
    data: { count: 12, windowStart: new Date(Date.now() - 20000) },
  });
  await expect(
    budget.consume(id, "GET", "/v1/reports/overview"),
  ).rejects.toMatchObject({ status: 429 });
  expect(
    (await db.requestBudget.findUniqueOrThrow({ where: { key } })).windowStart,
  ).toEqual(previous.windowStart);
  await db.requestBudget.update({
    where: { key },
    data: { windowStart: new Date(Date.now() - 61000) },
  });
  await budget.consume(id, "GET", "/v1/reports/overview");
  expect(
    (await db.requestBudget.findUniqueOrThrow({ where: { key } })).count,
  ).toBe(1);
});

it("enforces HTTP budgets across sessions with French errors, retry hints and no-store", async () => {
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
  expect(rejected.status).toBe(429);
  expect(Number(rejected.headers.get("retry-after"))).toBeGreaterThan(0);
  expect(await rejected.json()).toMatchObject({ code: "RATE_LIMITED" });
  await db.requestBudget.update({
    where: { key: `${prefix(user.id)}:all` },
    data: { count: 1200 },
  });
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
