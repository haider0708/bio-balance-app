import { assertTestDatabases } from "./test-database.cjs";
import { afterAll, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { Database } from "../src/shared/infrastructure/database";
import {
  IdentityService,
  tokenHash,
} from "../src/modules/identity/identity.service";
import { PasswordHasher } from "../src/modules/identity/password-hasher";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { JobRunner } from "../src/shared/jobs/job-runner";
import { cleanupAuthentication } from "../src/shared/jobs/maintenance";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw Error("ISOLATED_TEST_DATABASE_REQUIRED");
assertTestDatabases(process.env.DATABASE_URL);
const db = new Database();
// These tests exercise authorization transactions, not password cost/algorithms.
class TestPasswords extends PasswordHasher {
  override async hash(value: string) {
    return `test:${value}`;
  }
  override async verify(hash: string, value: string) {
    return hash === `test:${value}`;
  }
}
const identity = new IdentityService(db, new TestPasswords());
afterAll(() => db.$disconnect());
async function user(admin = false) {
  return db.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Final audit",
      passwordHash: "test:original-password",
      platformAdmin: admin,
    },
  });
}
async function inviteFixture() {
  const admin = await user(true),
    issuer = await user();
  const org = await db.organization.create({ data: { name: "Audit" } });
  const store = await db.store.create({
    data: {
      organizationId: org.id,
      name: "Audit",
      address: "Test",
      city: "Tunis",
    },
  });
  await db.membership.create({
    data: {
      organizationId: org.id,
      storeId: store.id,
      userId: issuer.id,
      permissions: ["manage", "sell"],
    },
  });
  const email = `${randomUUID()}@example.test`;
  await identity.invite(issuer, {
    email,
    organizationId: org.id,
    storeId: store.id,
    permissions: ["manage", "sell"],
  });
  const invitation = await db.accessToken.findFirstOrThrow({
    where: { email },
  });
  const job = await db.job.findUniqueOrThrow({
    where: { key: `invite:${invitation.id}` },
  });
  const token = (job.payload as { token: string }).token;
  return { admin, issuer, org, store, email, invitation, token };
}

it("cannot consume a store invitation after its issuer loses management permission", async () => {
  const f = await inviteFixture();
  await new WorkspaceService(db).setMember(
    f.admin,
    f.org.id,
    f.store.id,
    f.issuer.id,
    { active: true, permissions: ["sell"] },
  );
  await expect(
    identity.activate(f.token, "Recipient", "new-password", randomUUID()),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
  expect(await db.user.findUnique({ where: { email: f.email } })).toBeNull();
  expect(
    (await db.accessToken.findUniqueOrThrow({ where: { id: f.invitation.id } }))
      .usedAt,
  ).toBeNull();
});

it("accepts an organization owner's invitation without requiring store membership", async () => {
  const f = await inviteFixture();
  await db.organizationMembership.create({
    data: { organizationId: f.org.id, userId: f.issuer.id },
  });
  await new WorkspaceService(db).setMember(
    f.admin,
    f.org.id,
    f.store.id,
    f.issuer.id,
    { active: false, permissions: [] },
  );
  await expect(
    identity.activate(f.token, "Recipient", "new-password", randomUUID()),
  ).resolves.toMatchObject({ ok: true });
});

it("rejects a disabled issuer and an invitation with no attributable issuer", async () => {
  for (const legacy of [false, true]) {
    const f = await inviteFixture();
    if (legacy)
      await db.accessToken.update({
        where: { id: f.invitation.id },
        data: { createdBy: null },
      });
    else
      await db.user.update({
        where: { id: f.issuer.id },
        data: { disabled: true },
      });
    await expect(
      identity.activate(f.token, "Recipient", "new-password", randomUUID()),
    ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
    expect(await db.user.findUnique({ where: { email: f.email } })).toBeNull();
  }
});

it("does not change a disabled account's password or consume its reset token", async () => {
  const account = await user(),
    token = randomUUID();
  const reset = await db.accessToken.create({
    data: {
      email: account.email,
      tokenHash: tokenHash(token),
      purpose: "reset",
      permissions: [],
      expiresAt: new Date(Date.now() + 60000),
    },
  });
  await db.user.update({ where: { id: account.id }, data: { disabled: true } });
  await expect(
    identity.reset(token, "replacement-password", randomUUID()),
  ).rejects.toMatchObject({ code: "RESET_EXPIRED" });
  expect(
    (await db.user.findUniqueOrThrow({ where: { id: account.id } }))
      .passwordHash,
  ).toBe(account.passwordHash);
  expect(
    (await db.accessToken.findUniqueOrThrow({ where: { id: reset.id } }))
      .usedAt,
  ).toBeNull();
});

it("scrubs failed credential email while retaining job failure diagnostics", async () => {
  const row = await db.job.create({
    data: {
      kind: "email",
      key: `reset:${randomUUID()}`,
      payload: { to: "synthetic@example.test", text: "sensitive-code" },
      status: "running",
      leaseToken: randomUUID(),
      attempts: 8,
      lockedAt: new Date(),
    },
  });
  const runner = new JobRunner(db, ["email"], async () => {});
  await runner.fail(
    {
      ...row,
      payload: row.payload as Record<string, string>,
      leaseToken: row.leaseToken!,
    },
    new Error("SMTP_UNAVAILABLE"),
  );
  const failed = await db.job.findUniqueOrThrow({ where: { id: row.id } });
  expect(failed).toMatchObject({
    status: "failed",
    lastError: "SMTP_UNAVAILABLE",
  });
  expect(failed.payload).toEqual({});
});

it("globally prunes expired snapshot pages but retains usable pages", async () => {
  const f = await inviteFixture();
  const create = (expiresAt: Date) =>
    db.scoped(f.issuer, f.org.id, f.store.id, (tx) =>
      tx.syncSnapshotPage.create({
        data: {
          actorId: f.issuer.id,
          organizationId: f.org.id,
          storeId: f.store.id,
          permissions: "sell",
          payload: {},
          expiresAt,
        },
      }),
    );
  const expired = await create(new Date(Date.now() - 60000));
  const current = await create(new Date(Date.now() + 60000));
  const legacyMail = await db.job.create({
    data: {
      kind: "email",
      key: `legacy:${randomUUID()}`,
      status: "failed",
      payload: { text: "expired-credential" },
      lastError: "SMTP_UNAVAILABLE",
    },
  });
  // The caller has no cross-tenant read capability, before or after cleanup.
  expect(await db.syncSnapshotPage.findMany()).toEqual([]);
  await cleanupAuthentication(db);
  expect(
    (await db.job.findUniqueOrThrow({ where: { id: legacyMail.id } })).payload,
  ).toEqual({});
  expect(await db.syncSnapshotPage.findMany()).toEqual([]);
  const remaining = await db.scoped(f.issuer, f.org.id, f.store.id, (tx) =>
    tx.syncSnapshotPage.findMany(),
  );
  expect(remaining.map((p) => p.id)).not.toContain(expired.id);
  expect(remaining.map((p) => p.id)).toContain(current.id);
});
