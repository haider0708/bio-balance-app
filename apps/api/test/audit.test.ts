import { PrismaLedger } from "../src/modules/operations/infrastructure/prisma-ledger";
import express from "express";
import { EventEmitter } from "node:events";
import {
  cleanupAuthentication,
  scheduleMaintenance,
} from "../src/shared/jobs/maintenance";
import { NotificationsService } from "../src/modules/notifications/notifications.service";
import { TrainingService } from "../src/modules/training/training.service";
import { uploadIngress } from "../src/modules/training/infrastructure/upload-ingress";
import { accountTokenMessage } from "../src/modules/identity/account-links";
import { csvCell } from "../src/shared/domain/csv";
import { afterAll, describe, expect, it, vi } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import { PasswordHasher } from "../src/modules/identity/password-hasher";
import {
  IdentityService,
  tokenHash,
} from "../src/modules/identity/identity.service";
import { CatalogService } from "../src/modules/catalog/catalog.service";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { AdminService } from "../src/modules/reporting/admin.service";
import { ReportingService } from "../src/modules/reporting/reporting.service";
import {
  decodeHistoryCursor,
  syncCursor,
} from "../src/shared/domain/pagination";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw new Error("ISOLATED_TEST_DATABASE_REQUIRED");
const owner = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.TEST_OWNER_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
  }),
});
const db = new Database(),
  workspace = new WorkspaceService(db);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

async function account(admin = false) {
  const user = await owner.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Audit account",
      platformAdmin: admin,
      passwordHash: await new PasswordHasher().hash("old-test-password"),
    },
  });
  const session = await owner.session.create({
    data: {
      userId: user.id,
      tokenHash: tokenHash(randomUUID()),
      expiresAt: new Date(Date.now() + 3600000),
    },
  });
  return { ...user, sessionId: session.id };
}

describe("audit regressions against PostgreSQL", () => {
  it("does not issue a session for a password replaced after verification", async () => {
    const user = await account();
    let verified!: () => void, release!: () => void;
    const atVerification = new Promise<void>((r) => {
      verified = r;
    });
    const continueLogin = new Promise<void>((r) => {
      release = r;
    });
    const passwords = new PasswordHasher();
    const verify = passwords.verify.bind(passwords);
    vi.spyOn(passwords, "verify").mockImplementation(async (...args) => {
      const valid = await verify(...args);
      verified();
      await continueLogin;
      return valid;
    });
    const pending = new IdentityService(db, passwords).login(
      user.email,
      "old-test-password",
      undefined,
      randomUUID(),
    );
    const rejected = expect(pending).rejects.toMatchObject({
      code: "INVALID_CREDENTIALS",
    });
    await atVerification;
    const token = randomUUID(),
      secondToken = randomUUID();
    for (const raw of [token, secondToken])
      await owner.accessToken.create({
        data: {
          email: user.email,
          tokenHash: tokenHash(raw),
          purpose: "reset",
          permissions: [],
          expiresAt: new Date(Date.now() + 60000),
        },
      });
    await new IdentityService(db).reset(
      token,
      "new-test-password",
      randomUUID(),
    );
    release();
    await rejected;
    expect(
      await owner.session.count({
        where: { userId: user.id, revokedAt: null },
      }),
    ).toBe(0);
    await expect(
      new IdentityService(db).reset(
        secondToken,
        "another-password",
        randomUUID(),
      ),
    ).rejects.toMatchObject({ code: "RESET_EXPIRED" });
    const login = await new IdentityService(db).login(
      user.email,
      "new-test-password",
      undefined,
      randomUUID(),
    );
    expect((await new IdentityService(db).authenticate(login.token)).id).toBe(
      user.id,
    );
  }, 20000);

  it("rejects unknown account-flow tokens without hashing", async () => {
    const passwords = new PasswordHasher();
    const hash = vi.spyOn(passwords, "hash"),
      verify = vi.spyOn(passwords, "verify");
    const identity = new IdentityService(db, passwords);
    await expect(
      identity.activate(
        randomUUID(),
        "Invalid",
        "a-test-password",
        randomUUID(),
      ),
    ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
    await expect(
      identity.reset(randomUUID(), "a-test-password", randomUUID()),
    ).rejects.toMatchObject({ code: "RESET_EXPIRED" });
    expect(hash).not.toHaveBeenCalled();
    expect(verify).not.toHaveBeenCalled();
  });

  it("admits exactly the fixed-window limit during concurrent rollover", async () => {
    const key = `audit:${randomUUID()}`;
    await owner.loginAttempt.create({
      data: { key, count: 99, windowStart: new Date(Date.now() - 3600000) },
    });
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, () =>
        new IdentityService(db).throttle(key, 3),
      ),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(3);
    expect(
      (await owner.loginAttempt.findUniqueOrThrow({ where: { key } })).count,
    ).toBe(20);
  });

  it("rechecks revoked sessions on every global read and mutation", async () => {
    const actor = await account(true);
    const org = await owner.organization.create({
      data: { name: "Audit org" },
    });
    await owner.session.update({
      where: { id: actor.sessionId },
      data: { revokedAt: new Date() },
    });
    const calls = [
      () => workspace.organizations(actor),
      () => workspace.stores(actor),
      () =>
        workspace.createStore(actor, {
          organizationId: org.id,
          name: "Denied",
          address: "Test address",
          city: "Tunis",
        }),
      () => new AdminService(db).overview(actor),
      () => new ReportingService(db, workspace).overview(actor),
      () =>
        new CatalogService(db).save(actor, {
          reference: randomUUID(),
          name: "Denied",
          description: "",
          active: true,
        }),
    ];
    for (const call of calls)
      await expect(call()).rejects.toMatchObject({ code: "SESSION_EXPIRED" });
    expect(await owner.store.count({ where: { organizationId: org.id } })).toBe(
      0,
    );
  });

  it("rejects stale administrator privileges and concurrent catalog overwrite", async () => {
    const actor = await account(true),
      service = new CatalogService(db);
    const product = await service.save(actor, {
      reference: randomUUID(),
      name: "Initial",
      description: "",
      active: true,
    });
    const results = await Promise.allSettled(
      ["First", "Second"].map((name) =>
        service.save(actor, {
          id: product.id,
          expectedVersion: 1,
          reference: product.reference,
          name,
          description: "",
          active: true,
        }),
      ),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(results.find((r) => r.status === "rejected")).toMatchObject({
      reason: { code: "VERSION_CONFLICT" },
    });
    expect(
      (await owner.product.findUniqueOrThrow({ where: { id: product.id } }))
        .version,
    ).toBe(2);
    await owner.user.update({
      where: { id: actor.id },
      data: { platformAdmin: false },
    });
    await expect(
      service.save(actor, {
        reference: randomUUID(),
        name: "Denied",
        description: "",
        active: true,
      }),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
  });
});

describe("bounded input and resource admission", () => {
  it("refuses hash work instead of accumulating an unbounded queue", async () => {
    const passwords = new PasswordHasher(1);
    const first = passwords.hash("test-password");
    await expect(passwords.hash("another-password")).rejects.toMatchObject({
      code: "AUTH_BUSY",
      status: 429,
    });
    await first;
    expect(await passwords.hash("test-password")).toMatch(/^\$argon2id/);
  });
  it("maps malformed cursor contents to a client error and bounds bigint cursors", () => {
    for (const value of [
      "notjson",
      "bnVsbA",
      Buffer.from(
        JSON.stringify({ id: "-".repeat(36), date: "2026-01-01" }),
      ).toString("base64url"),
    ])
      expect(() => decodeHistoryCursor(value)).toThrowError(
        expect.objectContaining({ code: "INVALID_CURSOR", status: 400 }),
      );
    expect(syncCursor.safeParse("9999999999999999999").success).toBe(false);
    const id = randomUUID(),
      date = "2026-09-22T10:00:00.000Z";
    expect(
      decodeHistoryCursor(
        Buffer.from(JSON.stringify({ id, date })).toString("base64url"),
      ),
    ).toEqual({ id, date: new Date(date) });
  });
});

describe("audit resource and export controls", () => {
  it("caps devices, replaces renewed tokens, and removes logout endpoints", async () => {
    const actor = await account(),
      identity = new IdentityService(db),
      notifications = new NotificationsService(db, workspace);
    const sessions = [];
    for (let i = 0; i < 10; i++) {
      const token = randomUUID();
      const session = await owner.session.create({
        data: {
          userId: actor.id,
          tokenHash: tokenHash(token),
          expiresAt: new Date(Date.now() + 3600000),
        },
      });
      sessions.push({ session, token });
      await notifications.device(
        { ...actor, sessionId: session.id },
        randomUUID(),
        "android",
      );
    }
    await expect(
      notifications.device(actor, randomUUID(), "android"),
    ).rejects.toMatchObject({ code: "DEVICE_LIMIT" });
    const first = { ...actor, sessionId: sessions[0]!.session.id };
    await notifications.device(first, "renewed-" + randomUUID(), "android");
    expect(await owner.deviceToken.count({ where: { userId: actor.id } })).toBe(
      10,
    );
    await identity.logout(sessions[0]!.token);
    expect(await owner.deviceToken.count({ where: { userId: actor.id } })).toBe(
      9,
    );
  });
  it("prunes expired authentication telemetry without deleting live counters or history", async () => {
    const expired = `expired:${randomUUID()}`,
      live = `live:${randomUUID()}`;
    await owner.loginAttempt.createMany({
      data: [
        {
          key: expired,
          count: 1,
          windowStart: new Date(Date.now() - 2 * 86400000),
        },
        { key: live, count: 1 },
      ],
    });
    const actor = await account();
    await owner.deviceToken.create({
      data: {
        userId: actor.id,
        token: randomUUID(),
        platform: "android",
        sessionId: actor.sessionId,
      },
    });
    await owner.session.update({
      where: { id: actor.sessionId },
      data: { revokedAt: new Date() },
    });
    await cleanupAuthentication(db);
    expect(
      await owner.loginAttempt.findUnique({ where: { key: expired } }),
    ).toBeNull();
    expect(
      await owner.loginAttempt.findUnique({ where: { key: live } }),
    ).not.toBeNull();
    expect(await owner.deviceToken.count({ where: { userId: actor.id } })).toBe(
      0,
    );
    expect(
      await owner.session.findUnique({ where: { id: actor.sessionId } }),
    ).not.toBeNull();
    const now = new Date("2089-09-22T10:00:00Z");
    await Promise.all([
      scheduleMaintenance(db, false, now),
      scheduleMaintenance(db, false, now),
    ]);
    expect(
      await owner.job.count({ where: { key: "auth-cleanup:2089-09-22T10" } }),
    ).toBe(1);
  });
  it("rejects upload authorization before reading its body", async () => {
    const app = express(),
      identity = new IdentityService(db);
    app.use("/uploads", uploadIngress(identity, new TrainingService(db)));
    let read = false;
    app.put("/uploads/:id", (_req, res) => {
      read = true;
      res.json({ ok: true });
    });
    const server = app.listen(0, "127.0.0.1");
    await new Promise<void>((r) => server.once("listening", r));
    try {
      const port = (server.address() as import("node:net").AddressInfo).port;
      const response = await fetch(
        `http://127.0.0.1:${port}/uploads/${randomUUID()}`,
        {
          method: "PUT",
          headers: { "Content-Type": "application/octet-stream" },
          body: "untrusted",
        },
      );
      expect(response.status).toBe(401);
      expect(read).toBe(false);
    } finally {
      await new Promise<void>((r) => server.close(() => r()));
    }
  });
  it("does not admit more upload buffers while authorization is pending", async () => {
    let release!: (value: any) => void;
    const identity = {
      authenticate: () =>
        new Promise((r) => {
          release = r;
        }),
    };
    const handler = uploadIngress(
      identity as any,
      { uploadStatus: async () => ({}) } as any,
      1,
    );
    const response = () =>
      Object.assign(new EventEmitter(), {
        destroyed: true,
        statusCode: 0,
        headersSent: false,
        header() {
          return this;
        },
        setHeader() {},
        status(code: number) {
          this.statusCode = code;
          return this;
        },
        json() {
          this.emit("finish");
          return this;
        },
      });
    const request = () => ({
      method: "PUT",
      path: `/${randomUUID()}`,
      headers: {},
      is: () => true,
    });
    const first = response(),
      second = response();
    const pending = handler(request() as any, first as any, () => {});
    await handler(request() as any, second as any, () => {});
    expect(second.statusCode).toBe(429);
    release({});
    await pending;
    first.emit("close");
  });
  it("uses manual account codes by default and accepts only HTTPS routes", () => {
    const original = process.env.RECOVERY_URL;
    try {
      delete process.env.RECOVERY_URL;
      expect(accountTokenMessage("reset", "code")).not.toContain("://");
      process.env.RECOVERY_URL = "biobalance://recover";
      expect(() => accountTokenMessage("reset", "code")).toThrowError(
        expect.objectContaining({ code: "ACCOUNT_LINK_CONFIGURATION" }),
      );
      process.env.RECOVERY_URL = "https://accounts.example.test/recover";
      expect(accountTokenMessage("reset", "code")).toContain(
        "https://accounts.example.test/recover?token=code",
      );
    } finally {
      if (original === undefined) delete process.env.RECOVERY_URL;
      else process.env.RECOVERY_URL = original;
    }
  });
  it("preserves CSV text and neutralizes leading whitespace and control formulas", () => {
    for (const text of ["=1+1", " +SUM(1,2)", "\t=1", "-10", "@x"])
      expect(csvCell(text)).toBe(`"'${text}"`);
    expect(csvCell('Name "A"')).toBe('"Name ""A"""');
  });
});

it("retains every pending operational item in immutable snapshot pages", async () => {
  const actor = await account(true);
  const org = await owner.organization.create({
    data: { name: "Paged audit" },
  });
  const store = await owner.store.create({
    data: {
      organizationId: org.id,
      name: "Large store",
      address: "Test address",
      city: "Tunis",
    },
  });
  const reward = await owner.reward.create({
    data: {
      organizationId: org.id,
      storeId: store.id,
      title: "Gift",
      cost: 1,
      description: "Test",
    },
  });
  const product = await owner.product.create({
    data: { reference: randomUUID(), name: "Product" },
  });
  await owner.rewardClaim.createMany({
    data: Array.from({ length: 205 }, () => ({
      id: randomUUID(),
      organizationId: org.id,
      storeId: store.id,
      userId: actor.id,
      rewardId: reward.id,
      title: "Gift",
      cost: 1,
      quantity: 1,
      status: "requested",
    })),
  });
  const orders = Array.from({ length: 205 }, () => ({
    id: randomUUID(),
    organizationId: org.id,
    storeId: store.id,
    createdBy: actor.id,
    status: "dispatched",
    lines: [{ productId: product.id, quantity: 1 }],
  }));
  await owner.replenishmentOrder.createMany({ data: orders });
  await owner.delivery.createMany({
    data: orders.map((o) => ({
      id: randomUUID(),
      organizationId: org.id,
      storeId: store.id,
      orderId: o.id,
      status: "dispatched",
      lines: o.lines,
    })),
  });
  const snapshot = await workspace.snapshot(
    actor,
    org.id,
    store.id,
    undefined,
    3,
  );
  expect(snapshot.claims).toHaveLength(200);
  for (const resource of ["claims", "orders", "deliveries"] as const) {
    const first = snapshot.snapshotPages[resource];
    expect(first).toBeTruthy();
    const page = await workspace.snapshotPage(actor, org.id, store.id, first!);
    expect(page).toMatchObject({
      resource,
      cursor: snapshot.cursor,
      nextPage: null,
    });
    expect((page as any).items).toHaveLength(5);
    if (resource === "orders")
      expect((page as any).items[0].fulfillment[0].inTransit).toBe(1);
  }
  // Materialized data does not change when a later transaction updates a row.
  const before = await workspace.snapshotPage(
    actor,
    org.id,
    store.id,
    snapshot.snapshotPages.claims!,
  );
  await owner.rewardClaim.updateMany({
    where: { storeId: store.id },
    data: { status: "cancelled" },
  });
  expect(
    await workspace.snapshotPage(
      actor,
      org.id,
      store.id,
      snapshot.snapshotPages.claims!,
    ),
  ).toEqual(before);
  await owner.inventoryLot.createMany({
    data: Array.from({ length: 1005 }, (_, i) => ({
      organizationId: org.id,
      storeId: store.id,
      productId: product.id,
      batch: `audit-${i}`,
      expiry: new Date("2099-01-01"),
      sellable: 1,
    })),
  });
  const lots = await db.scoped(actor, org.id, store.id, (tx, scope) =>
    new PrismaLedger(tx, scope).lotsForProduct(product.id, 1005),
  );
  expect(lots).toHaveLength(1005);
});
