import { beforeAll, afterAll, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import { IdentityService } from "../src/modules/identity/identity.service";
import { InvitationManagementService } from "../src/modules/identity/invitation-management";
import { PasswordHasher } from "../src/modules/identity/password-hasher";
import { GroupService } from "../src/modules/tenancy/group.service";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { GroupRequests } from "../src/modules/tenancy/group.contracts";
import { assertTestDatabases } from "./test-database.cjs";
process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
const ownerUrl =
  process.env.TEST_OWNER_DATABASE_URL ??
  "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test";
assertTestDatabases(process.env.DATABASE_URL, ownerUrl);
const owner = new PrismaClient({
  adapter: new PrismaPg({ connectionString: ownerUrl }),
});
const db = new Database(),
  workspace = new WorkspaceService(db),
  groups = new GroupService(db, workspace);
class Passwords extends PasswordHasher {
  override async hash(p: string) {
    return `test:${p}`;
  }
}
const identity = new IdentityService(db, new Passwords()),
  invitations = new InvitationManagementService(db);
const account = (admin = false) => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: "Fixture",
  platformAdmin: admin,
});
const admin = account(true),
  manager = account(),
  other = account(),
  seller = account();
let group: string, store: string, second: string;
const list = () =>
  invitations.list(manager, {
    organizationId: group,
    includeArchived: "false",
  });
async function invite() {
  return identity.invite(manager, {
    kind: "salesperson",
    organizationId: group,
    storeIds: [store],
    email: `${randomUUID()}@example.test`,
    permissions: [],
  });
}
async function code(id: string) {
  return (await owner.job.findUniqueOrThrow({ where: { key: `invite:${id}` } }))
    .payload as { token: string };
}
beforeAll(async () => {
  for (const a of [admin, manager, other, seller])
    await owner.user.create({ data: { ...a, passwordHash: "test:none" } });
  group = (
    await owner.organization.create({ data: { name: "Invitation tests" } })
  ).id;
  store = (
    await owner.store.create({
      data: {
        organizationId: group,
        name: "One",
        address: "Test",
        city: "Tunis",
      },
    })
  ).id;
  second = (
    await owner.store.create({
      data: {
        organizationId: group,
        name: "Two",
        address: "Test",
        city: "Tunis",
      },
    })
  ).id;
  await owner.organizationMembership.create({
    data: { organizationId: group, userId: manager.id },
  });
  await owner.membership.create({
    data: {
      organizationId: group,
      storeId: store,
      userId: seller.id,
      permissions: ["sell"],
    },
  });
});
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});
it("blocks changing one's own group access even when another responsible exists", async () => {
  const colleague = account();
  await owner.user.create({
    data: { ...colleague, passwordHash: "test:none" },
  });
  await owner.organizationMembership.create({
    data: { organizationId: group, userId: colleague.id },
  });
  for (const input of [
    { role: "responsible" as const, active: false, storeIds: [] },
    { role: "salesperson" as const, active: true, storeIds: [store] },
  ]) {
    await expect(
      groups.member(manager, group, manager.id, input),
    ).rejects.toMatchObject({ code: "SELF_ACCESS_CHANGE" });
  }
  expect(
    (
      await owner.organizationMembership.findUniqueOrThrow({
        where: {
          organizationId_userId: { organizationId: group, userId: manager.id },
        },
      })
    ).active,
  ).toBe(true);
  await expect(
    identity.invite(manager, {
      organizationId: group,
      storeId: store,
      email: manager.email,
      permissions: ["sell"],
    }),
  ).rejects.toMatchObject({ code: "SELF_ACCESS_CHANGE" });
});
it("tracks expiry, resend, replacement and single-use activation without exposing tokens", async () => {
  const first = await invite(),
    old = await code(first.id);
  await owner.accessToken.update({
    where: { id: first.id },
    data: { expiresAt: new Date(Date.now() - 1000) },
  });
  expect((await list()).items.find((x) => x.id === first.id)?.status).toBe(
    "expired",
  );
  const request = {
    action: "resend" as const,
    expectedVersion: 1,
    operationId: randomUUID(),
  };
  const [a, b] = await Promise.all([
    invitations.action(manager, first.id, request),
    invitations.action(manager, first.id, request),
  ]);
  expect(a).toEqual(b);
  expect((await list()).items.find((x) => x.id === first.id)?.status).toBe(
    "replaced",
  );
  await expect(
    identity.activate(old.token, "Seller", "password-for-test", randomUUID()),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
  const next = await code(a.id);
  await identity.activate(
    next.token,
    "Seller",
    "password-for-test",
    randomUUID(),
  );
  const rows = await list();
  expect(rows.items.find((x) => x.id === a.id)?.status).toBe("accepted");
  expect(JSON.stringify(rows)).not.toContain("tokenHash");
  await expect(
    identity.activate(next.token, "Seller", "password-for-test", randomUUID()),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
  await expect(
    invitations.action(manager, a.id, {
      action: "revoke",
      expectedVersion: 2,
      operationId: randomUUID(),
    }),
  ).rejects.toMatchObject({ code: "INVITATION_CLOSED" });
});
it("revokes codes and archives history without deleting identities", async () => {
  const first = await invite(),
    token = await code(first.id);
  await invitations.action(manager, first.id, {
    action: "revoke",
    expectedVersion: 1,
    operationId: randomUUID(),
  });
  expect((await list()).items.find((x) => x.id === first.id)?.status).toBe(
    "revoked",
  );
  await expect(
    identity.activate(token.token, "Seller", "password-for-test", randomUUID()),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
  await invitations.action(manager, first.id, {
    action: "archive",
    expectedVersion: 2,
    operationId: randomUUID(),
  });
  expect((await list()).items.some((x) => x.id === first.id)).toBe(false);
  expect(
    (
      await invitations.list(manager, {
        organizationId: group,
        includeArchived: "true",
      })
    ).items.find((x) => x.id === first.id)?.status,
  ).toBe("archived");
  expect(await owner.accessToken.count({ where: { id: first.id } })).toBe(1);
});
it("denies another group, sellers and non-admin global invitation history", async () => {
  const first = await invite();
  for (const actor of [other, seller]) {
    await expect(
      invitations.list(actor, {
        organizationId: group,
        includeArchived: "false",
      }),
    ).rejects.toMatchObject({ code: "GROUP_ACCESS_REVOKED" });
    await expect(
      invitations.action(actor, first.id, {
        action: "revoke",
        expectedVersion: 1,
        operationId: randomUUID(),
      }),
    ).rejects.toMatchObject({ code: "GROUP_ACCESS_REVOKED" });
  }
  await expect(
    invitations.list(manager, { includeArchived: "false" }),
  ).rejects.toMatchObject({ code: "FORBIDDEN" });
  await expect(
    invitations.list(admin, { includeArchived: "false" }),
  ).resolves.toHaveProperty("items");
});
it("rejects stale versions and changed retry payloads", async () => {
  const first = await invite(),
    operationId = randomUUID();
  await invitations.action(manager, first.id, {
    action: "revoke",
    expectedVersion: 1,
    operationId,
  });
  await expect(
    invitations.action(manager, first.id, {
      action: "archive",
      expectedVersion: 1,
      operationId: randomUUID(),
    }),
  ).rejects.toMatchObject({ code: "VERSION_CONFLICT" });
  await expect(
    invitations.action(manager, first.id, {
      action: "archive",
      expectedVersion: 2,
      operationId,
    }),
  ).rejects.toMatchObject({ code: "OPERATION_REUSED" });
});
it("rejects multi-store invitations and assignments and transfers one assignment atomically", async () => {
  expect(
    GroupRequests.Member.safeParse({
      active: true,
      role: "salesperson",
      storeIds: [store, second],
    }).success,
  ).toBe(false);
  await expect(
    identity.invite(manager, {
      kind: "salesperson",
      organizationId: group,
      storeIds: [store, second],
      email: `${randomUUID()}@example.test`,
      permissions: [],
    }),
  ).rejects.toMatchObject({ code: "STORE_REQUIRED" });
  await groups.member(manager, group, seller.id, {
    active: true,
    role: "salesperson",
    storeIds: [second],
  });
  expect(
    await owner.membership.findMany({
      where: { userId: seller.id, active: true },
      select: { storeId: true },
    }),
  ).toEqual([{ storeId: second }]);
  await expect(
    workspace.setMember(manager, group, store, seller.id, {
      active: true,
      permissions: ["sell"],
    }),
  ).rejects.toMatchObject({ code: "SELLER_ALREADY_ASSIGNED" });
  expect(
    await owner.membership.count({
      where: { userId: seller.id, active: true },
    }),
  ).toBe(1);
});
it("keeps unknown historical closed tokens distinct from accepted invitations", async () => {
  const first = await invite();
  await owner.accessToken.update({
    where: { id: first.id },
    data: { usedAt: new Date() },
  });
  expect((await list()).items.find((x) => x.id === first.id)?.status).toBe(
    "closed",
  );
});
it("tracks global invitations and retries one resend without creating another grant or email", async () => {
  const first = await identity.invite(admin, {
    kind: "new_group",
    email: `${randomUUID()}@example.test`,
    permissions: [],
  });
  const request = {
    action: "resend" as const,
    expectedVersion: 1,
    operationId: randomUUID(),
  };
  const [a, b] = await Promise.all([
    invitations.action(admin, first.id, request),
    invitations.action(admin, first.id, request),
  ]);
  expect(a).toEqual(b);
  expect(
    await owner.accessToken.count({
      where: { email: first.email, purpose: "invite", usedAt: null },
    }),
  ).toBe(1);
  expect(await owner.job.count({ where: { key: `invite:${a.id}` } })).toBe(1);
  expect(
    (await invitations.list(admin, { includeArchived: "false" })).items.find(
      (x) => x.id === a.id,
    )?.status,
  ).toBe("pending");
});
it("rejects an assignment in another group without silently removing the original", async () => {
  const otherGroup = (
    await owner.organization.create({ data: { name: "Other seller group" } })
  ).id;
  const otherStore = (
    await owner.store.create({
      data: {
        organizationId: otherGroup,
        name: "Other",
        address: "Test",
        city: "Sfax",
      },
    })
  ).id;
  await owner.membership.create({
    data: {
      organizationId: otherGroup,
      storeId: otherStore,
      userId: seller.id,
      permissions: ["sell"],
      active: false,
    },
  });
  await expect(
    groups.member(admin, otherGroup, seller.id, {
      active: true,
      role: "salesperson",
      storeIds: [otherStore],
    }),
  ).rejects.toMatchObject({ code: "SELLER_ALREADY_ASSIGNED" });
  expect(
    await owner.membership.findMany({
      where: { userId: seller.id, active: true },
      select: { storeId: true },
    }),
  ).toEqual([{ storeId: second }]);
});
it("does not issue unusable invitations into a suspended group or store", async () => {
  const suspended = (
    await owner.organization.create({
      data: { name: "Suspended", status: "suspended" },
    })
  ).id;
  await expect(
    identity.invite(admin, {
      kind: "responsible",
      organizationId: suspended,
      email: `${randomUUID()}@example.test`,
      permissions: [],
    }),
  ).rejects.toMatchObject({ code: "WORKSPACE_INACTIVE" });
  const closedStore = (
    await owner.store.create({
      data: {
        organizationId: group,
        name: "Suspended",
        address: "Test",
        city: "Tunis",
        status: "suspended",
      },
    })
  ).id;
  await expect(
    identity.invite(admin, {
      kind: "salesperson",
      organizationId: group,
      storeIds: [closedStore],
      email: `${randomUUID()}@example.test`,
      permissions: [],
    }),
  ).rejects.toMatchObject({ code: "STORE_SCOPE" });
});
