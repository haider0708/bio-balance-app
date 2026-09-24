import { CatalogService } from "../src/modules/catalog/catalog.service";
import { CatalogRequests } from "../src/shared/contracts/requests";
import { assertTestDatabases } from "./test-database.cjs";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import {
  PrismaUnitOfWork,
  lotIdentity,
} from "../src/modules/operations/infrastructure/prisma-ledger";
import { OperationsService } from "../src/modules/operations/application/operations.service";
import {
  UnitOfWork,
  Ledger,
} from "../src/modules/operations/application/ports";
import {
  Actor,
  Command,
  Operation,
} from "../src/modules/operations/domain/contracts";
import {
  IdentityService,
  tokenHash,
} from "../src/modules/identity/identity.service";
import { TrainingService } from "../src/modules/training/training.service";
import { NotificationsService } from "../src/modules/notifications/notifications.service";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { GroupService } from "../src/modules/tenancy/group.service";
import { DashboardService } from "../src/modules/reporting/dashboard.service";
import {
  backfillReporting,
  reconcileReporting,
} from "../src/modules/reporting/backfill";
import { ExportService } from "../src/modules/reporting/export.service";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
assertTestDatabases(
  process.env.DATABASE_URL,
  process.env.TEST_OWNER_DATABASE_URL ??
    "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
);
const owner = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.TEST_OWNER_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
  }),
});
const db = new Database(),
  uow = new PrismaUnitOfWork(db),
  service = new OperationsService(uow),
  workspace = new WorkspaceService(db);
const actor: Actor = {
  id: randomUUID(),
  name: "Test manager",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const seller: Actor = {
  id: randomUUID(),
  name: "Test seller",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const foreign: Actor = {
  id: randomUUID(),
  name: "Other organization",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const admin: Actor = {
  ...actor,
  id: randomUUID(),
  email: `admin-${randomUUID()}@example.test`,
  platformAdmin: true,
};
const org = randomUUID(),
  store = randomUUID(),
  otherStore = randomUUID(),
  product = randomUUID(),
  saleId = randomUUID(),
  lineId = randomUUID();
let lotId = "";
const op = (command: Command, expectedVersion?: number): Operation => ({
  operationId: randomUUID(),
  storeId: store,
  organizationId: org,
  payloadVersion: 1,
  command,
  expectedVersion,
});
beforeAll(async () => {
  for (const a of [actor, seller, foreign, admin])
    await owner.user.create({
      data: {
        id: a.id,
        email: a.email,
        name: a.name,
        passwordHash: "test-only-not-a-login",
        platformAdmin: a.platformAdmin,
      },
    });
  await owner.organization.create({
    data: { id: org, name: "Integration test" },
  });
  for (const id of [store, otherStore])
    await owner.store.create({
      data: {
        id,
        organizationId: org,
        name: "Test store",
        address: "Test address",
        city: "Tunis",
      },
    });
  for (const [userId, permissions] of [
    [actor.id, ["manage", "sell", "receive"]],
    [seller.id, ["sell", "receive"]],
  ] as const)
    await owner.membership.create({
      data: {
        organizationId: org,
        storeId: store,
        userId,
        permissions: [...permissions],
      },
    });
  await owner.product.create({
    data: { id: product, reference: product, name: "Test serum" },
  });
  await workspace.configureProduct(actor, org, store, product, {
    priceMillimes: "49900",
    threshold: 5,
    pointsPerUnit: 10,
  });
}, 30000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});
describe.sequential("group redesign and reporting projections", () => {
  const seller: Actor = {
    id: randomUUID(),
    name: "Group seller",
    email: `group-seller-${randomUUID()}@example.test`,
    platformAdmin: false,
  };
  beforeAll(async () => {
    await owner.user.create({
      data: { ...seller, passwordHash: "test-only-not-a-login" },
    });
  });
  const groups = new GroupService(db, workspace),
    dashboards = new DashboardService(db);
  let groupId = "",
    newStore = "",
    newLot = "";
  const reportedSale = randomUUID(),
    reportedLine = randomUUID();
  const envelope = (command: Command, expectedVersion?: number): Operation => ({
    operationId: randomUUID(),
    organizationId: groupId,
    storeId: newStore,
    payloadVersion: 1,
    command,
    expectedVersion,
  });
  it("invites a future responsible without creating a group; consumes one grant idempotently", async () => {
    const identity = new IdentityService(db),
      email = `future-${randomUUID()}@example.test`;
    const count = await owner.organization.count();
    const invite = await identity.invite(admin, {
      email,
      kind: "new_group",
      permissions: ["manage", "sell", "receive"],
    });
    expect(await owner.organization.count()).toBe(count);
    expect(
      await owner.accessToken.findUnique({ where: { id: invite.id } }),
    ).toMatchObject({ kind: "new_group", organizationId: null });
    const grant = await owner.groupCreationGrant.create({
      data: { id: randomUUID(), userId: actor.id, createdBy: admin.id },
    });
    const request = {
      grantId: grant.id,
      operationId: randomUUID(),
      name: "Parahouse test",
    };
    const first = await groups.create(actor, request);
    groupId = first.id;
    expect((await groups.create(actor, request)).id).toBe(groupId);
    await expect(
      groups.create(actor, { ...request, name: "Different" }),
    ).rejects.toMatchObject({ code: "GRANT_USED" });
    expect(
      (await groups.list(actor)).items.find((g) => g.id === groupId)?.canManage,
    ).toBe(true);
    await expect(groups.team(foreign, groupId)).rejects.toMatchObject({
      code: "GROUP_ACCESS_REVOKED",
    });
    await expect(
      groups.member(actor, groupId, actor.id, {
        active: false,
        role: "responsible",
        storeIds: [],
      }),
    ).rejects.toMatchObject({ code: "SELF_ACCESS_CHANGE" });
    await expect(
      identity.invite(actor, {
        email,
        kind: "salesperson",
        permissions: ["sell"],
      }),
    ).rejects.toMatchObject({ code: "VALIDATION" });
    newStore = (
      await workspace.createStore(actor, {
        organizationId: groupId,
        name: "Parahouse Tunis",
        address: "Test",
        city: "Tunis",
      })
    ).id;
    expect(
      (await workspace.stores(actor)).some(
        (s) => s.id === newStore && s.permissions.includes("manage"),
      ),
    ).toBe(true);
    const teamInvite = await identity.invite(actor, {
      email: `team-${randomUUID()}@example.test`,
      kind: "salesperson",
      organizationId: groupId,
      storeIds: [newStore],
      permissions: ["sell", "receive"],
    });
    expect(teamInvite.id).toBeTruthy();
    expect(
      (await workspace.snapshot(actor, groupId, newStore)).onboarding.team,
    ).toBe(true);

    await owner.membership.create({
      data: {
        organizationId: groupId,
        storeId: newStore,
        userId: seller.id,
        permissions: ["sell", "receive"],
      },
    });
  });
  it("serializes responsible removal and grants the same access to newly created stores", async () => {
    const group = await owner.organization.create({
      data: { name: "Concurrent responsible fixture" },
    });
    const co = await owner.user.create({
      data: {
        email: `co-${randomUUID()}@example.test`,
        name: "Co responsible",
        passwordHash: "disabled-test-login",
      },
    });
    const coActor = {
      id: co.id,
      name: co.name,
      email: co.email,
      platformAdmin: false,
    };
    for (const userId of [actor.id, co.id])
      await owner.organizationMembership.create({
        data: { organizationId: group.id, userId },
      });
    const extra = await workspace.createStore(actor, {
      organizationId: group.id,
      name: "Second store",
      address: "Test",
      city: "Sousse",
    });
    expect(
      (await workspace.stores(coActor)).find((s) => s.id === extra.id)
        ?.permissions,
    ).toContain("manage");
    const changes = await Promise.allSettled([
      groups.member(actor, group.id, co.id, {
        active: false,
        role: "responsible",
        storeIds: [],
      }),
      groups.member(coActor, group.id, actor.id, {
        active: false,
        role: "responsible",
        storeIds: [],
      }),
    ]);
    expect(changes.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(
      await owner.organizationMembership.count({
        where: { organizationId: group.id, active: true },
      }),
    ).toBe(1);
    const remaining = await owner.organizationMembership.findFirstOrThrow({
      where: { organizationId: group.id, active: true },
    });
    const acting = remaining.userId === actor.id ? actor : coActor;
    await expect(
      groups.member(acting, group.id, acting.id, {
        active: false,
        role: "responsible",
        storeIds: [],
      }),
    ).rejects.toMatchObject({ code: "SELF_ACCESS_CHANGE" });
  });
  it("keeps net sales on their original Tunisian day after returns, corrections and repeated commands", async () => {
    const receipt = envelope({
      type: "stock.receive",
      reason: "opening",
      lines: [
        {
          productId: product,
          batch: "REPORT",
          expiry: "2027-12",
          quantity: 10,
        },
      ],
    });
    expect((await service.submit(actor, receipt)).status).toBe("accepted");
    newLot = (
      await owner.inventoryLot.findFirstOrThrow({
        where: { storeId: newStore, productId: product },
      })
    ).id;
    const create = envelope({
      type: "sale.create",
      saleId: reportedSale,
      occurredAt: "2026-08-31T22:59:00.000Z",
      lines: [
        {
          id: reportedLine,
          productId: product,
          quantity: 3,
          unitPriceMillimes: "10555",
          allocations: [{ lotId: newLot, quantity: 3 }],
        },
      ],
    });
    expect((await service.submit(seller, create)).status).toBe("accepted");
    expect((await service.submit(seller, create)).status).toBe("accepted");
    const query = {
      scope: "group" as const,
      organizationId: groupId,
      from: "2026-08-01",
      to: "2026-08-31",
    };
    expect(await dashboards.get(actor, query)).toMatchObject({
      netMillimes: 31665n,
      netUnits: 3n,
      saleCount: 1n,
    });
    const returned = envelope(
      {
        type: "sale.return",
        saleId: reportedSale,
        reason: "Retour septembre",
        lines: [
          { lineId: reportedLine, lotId: newLot, quantity: 1, sellable: true },
        ],
      },
      1,
    );
    expect((await service.submit(seller, returned)).status).toBe("accepted");
    await service.submit(seller, returned);
    expect(await dashboards.get(actor, query)).toMatchObject({
      netMillimes: 21110n,
      netUnits: 2n,
      saleCount: 1n,
    });
    expect(
      await dashboards.get(actor, {
        ...query,
        from: "2026-09-01",
        to: "2026-09-30",
      }),
    ).toMatchObject({ netMillimes: 0n, netUnits: 0n, saleCount: 0n });
    const correction = envelope(
      {
        type: "sale.correct",
        saleId: reportedSale,
        occurredAt: "2026-08-31T22:59:00.000Z",
        reason: "Prix corrigé",
        lines: [
          {
            id: reportedLine,
            productId: product,
            quantity: 3,
            unitPriceMillimes: "11000",
            allocations: [{ lotId: newLot, quantity: 3 }],
          },
        ],
      },
      2,
    );
    expect((await service.submit(actor, correction)).status).toBe("accepted");
    const result = await dashboards.get(actor, query);
    expect(result).toMatchObject({
      netMillimes: 22000n,
      netUnits: 2n,
      saleCount: 1n,
    });
    expect(result.comparisons.reduce((sum, s) => sum + s.netMillimes, 0n)).toBe(
      result.netMillimes,
    );
    expect(
      await dashboards.get(seller, {
        ...query,
        scope: "personal",
        storeId: newStore,
      }),
    ).toMatchObject({ netMillimes: 22000n });
    await expect(dashboards.get(seller, query)).rejects.toMatchObject({
      code: "GROUP_ACCESS_REVOKED",
    });
    await expect(
      dashboards.get(foreign, { ...query, scope: "store", storeId: newStore }),
    ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
    await expect(
      dashboards.get(actor, {
        ...query,
        scope: "network",
        organizationId: undefined,
      }),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
    const contribution = await owner.salesContribution.findUniqueOrThrow({
      where: { saleId: reportedSale },
    });
    expect(contribution.version).toBe(3);
    expect(contribution.day.toISOString().slice(0, 10)).toBe("2026-08-31");
    await owner.$executeRaw`SELECT project_biobalance_sale(${reportedSale}::uuid)`;
    expect((await dashboards.get(actor, query)).netMillimes).toBe(22000n);
  });
  it("backfills legacy rows in bounded pages, resumes, and reconciles with live revisions", async () => {
    const ids = Array.from({ length: 1100 }, () => randomUUID());
    await owner.$transaction(async (tx) => {
      await tx.$executeRawUnsafe(
        'ALTER TABLE "Sale" DISABLE TRIGGER "Sale_reporting"',
      );
      await tx.sale.createMany({
        data: ids.map((id) => ({
          id,
          organizationId: groupId,
          storeId: newStore,
          sellerId: actor.id,
          occurredAt: new Date("2025-01-02T10:00:00Z"),
          totalMillimes: 5000n,
          earnedPoints: 0n,
          lines: [
            {
              id: randomUUID(),
              productId: product,
              quantity: 2,
              unitPriceMillimes: "2500",
              allocations: [],
            },
          ],
        })),
      });
      await tx.$executeRawUnsafe(
        'ALTER TABLE "Sale" ENABLE TRIGGER "Sale_reporting"',
      );
    });
    const full: Pick<Database, "transaction"> = {
      transaction: (work) => owner.$transaction(work, { timeout: 15000 }),
    };
    expect(await backfillReporting(full)).toBe(1100);
    expect(await backfillReporting(full)).toBe(0);
    expect(
      await dashboards.get(actor, {
        scope: "group",
        organizationId: groupId,
        from: "2025-01-01",
        to: "2025-01-31",
      }),
    ).toMatchObject({
      saleCount: 1100n,
      netUnits: 2200n,
      netMillimes: 5500000n,
    });
    await expect(reconcileReporting(owner)).resolves.toEqual({
      saleMismatches: 0,
      dayMismatches: 0,
      productMismatches: 0,
    });
  });
  it("independently detects altered reporting totals without modifying sale history", async () => {
    await expect(reconcileReporting(owner)).resolves.toEqual({
      saleMismatches: 0,
      dayMismatches: 0,
      productMismatches: 0,
    });
    await owner.salesDay.updateMany({
      where: { storeId: newStore },
      data: { netMillimes: { increment: 1 } },
    });
    try {
      await expect(reconcileReporting(owner)).rejects.toThrow(
        "REPORTING_RECONCILIATION_FAILED",
      );
    } finally {
      await owner.salesDay.updateMany({
        where: { storeId: newStore },
        data: { netMillimes: { decrement: 1 } },
      });
    }
    expect(
      (await owner.sale.findUniqueOrThrow({ where: { id: reportedSale } }))
        .version,
    ).toBe(3);
  });
  it("returns scoped action lists and denies personal inventory supervision", async () => {
    const q = {
      scope: "group" as const,
      organizationId: groupId,
      from: "2026-08-01",
      to: "2026-08-31",
    };
    await expect(
      dashboards.attention(foreign, q, "low_stock"),
    ).rejects.toMatchObject({ code: "GROUP_ACCESS_REVOKED" });
    await expect(
      dashboards.attention(
        seller,
        { ...q, scope: "personal", storeId: newStore },
        "expired",
      ),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
    const rows = await dashboards.attention(actor, q, "low_stock");
    expect(
      rows.items.every(
        (r) => r.organizationId === groupId && r.storeId === newStore,
      ),
    ).toBe(true);
    await expect(groups.stores(foreign, groupId)).rejects.toMatchObject({
      code: "GROUP_ACCESS_REVOKED",
    });
  });
  it("reads an exact order with group/store identity and rejects a foreign scope", async () => {
    const id = randomUUID();
    await owner.replenishmentOrder.create({
      data: {
        id,
        organizationId: groupId,
        storeId: newStore,
        createdBy: actor.id,
        lines: [{ productId: product, quantity: 5 }],
      },
    });
    expect(
      (await dashboards.order(admin, groupId, newStore, id)).order,
    ).toMatchObject({
      id,
      groupName: "Parahouse test",
      storeName: "Parahouse Tunis",
    });
    await expect(
      dashboards.order(foreign, groupId, newStore, id),
    ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
    await expect(dashboards.order(admin, org, store, id)).rejects.toMatchObject(
      { code: "NOT_FOUND" },
    );
    await groups.member(actor, groupId, seller.id, {
      role: "salesperson",
      active: false,
      storeIds: [],
    });
    await expect(
      dashboards.order(seller, groupId, newStore, id),
    ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
  });
  it("exports a complete filtered snapshot beyond one page and rechecks access before download", async () => {
    const directory = await mkdtemp(path.join(tmpdir(), "biobalance-export-"));
    const oldRoot = process.env.MEDIA_ROOT;
    process.env.MEDIA_ROOT = directory;
    try {
      const reports = new ExportService(db, dashboards),
        id = randomUUID();
      const query = {
        scope: "group" as const,
        organizationId: groupId,
        from: "2026-08-01",
        to: "2026-08-31",
      };
      await owner.sale.createMany({
        data: Array.from({ length: 105 }, () => ({
          id: randomUUID(),
          organizationId: groupId,
          storeId: newStore,
          sellerId: seller.id,
          occurredAt: new Date("2026-08-20T10:00:00Z"),
          totalMillimes: 1000n,
          earnedPoints: 0n,
          lines: [
            {
              id: randomUUID(),
              productId: product,
              quantity: 1,
              unitPriceMillimes: "1000",
              allocations: [],
            },
          ],
        })),
      });
      const first = await dashboards.sales(actor, query);
      expect(first.items).toHaveLength(100);
      expect(
        (await dashboards.sales(actor, query, first.nextCursor!)).items,
      ).toHaveLength(6);
      const initial = await reports.create(actor, id, query);
      expect(
        (
          await reports.create(actor, id, {
            to: query.to,
            from: query.from,
            organizationId: groupId,
            scope: "group",
          })
        ).id,
      ).toBe(initial.id);
      await reports.process(id, randomUUID(), async () => true);
      await owner.job.update({
        where: { key: `export:${id}` },
        data: { status: "done" },
      });
      expect(await reports.get(actor, id)).toMatchObject({
        status: "ready",
        rows: 106,
      });
      const file = await reports.download(actor, id),
        csv = await readFile(file, "utf8");
      expect(csv).toContain("22,000");
      expect(csv).toContain(reportedSale);
      expect(csv.trim().split("\n")).toHaveLength(107);
      await expect(reports.download(foreign, id)).rejects.toMatchObject({
        code: "NOT_FOUND",
      });
      await owner.organizationMembership.update({
        where: {
          organizationId_userId: { organizationId: groupId, userId: actor.id },
        },
        data: { active: false },
      });
      await expect(reports.download(actor, id)).rejects.toMatchObject({
        code: "GROUP_ACCESS_REVOKED",
      });
      await owner.organizationMembership.update({
        where: {
          organizationId_userId: { organizationId: groupId, userId: actor.id },
        },
        data: { active: true },
      });
    } finally {
      if (oldRoot === undefined) delete process.env.MEDIA_ROOT;
      else process.env.MEDIA_ROOT = oldRoot;
      await rm(directory, { recursive: true, force: true });
    }
  });
});
it("keeps missing reference prices distinct from zero and never overwrites store prices", async () => {
  const catalog = new CatalogService(db),
    ref = randomUUID();
  const before = await owner.storeProduct.findUniqueOrThrow({
    where: { storeId_productId: { storeId: store, productId: product } },
  });
  await expect(
    catalog.save(admin, {
      reference: ref,
      name: "Reference price test",
      description: "",
      active: true,
      priceStatus: "sample",
    }),
  ).rejects.toMatchObject({ code: "INVALID_REFERENCE_PRICE" });
  const zero = await catalog.save(admin, {
    reference: ref,
    name: "Zero price test",
    description: "",
    active: true,
    referencePriceMillimes: "0",
    priceStatus: "verified",
  });
  expect(zero.referencePriceMillimes).toBe(0n);
  await expect(
    catalog.save(admin, {
      id: zero.id,
      expectedVersion: zero.version,
      reference: ref,
      name: zero.name,
      description: "",
      active: true,
      priceStatus: "missing",
    }),
  ).rejects.toMatchObject({ code: "INVALID_REFERENCE_PRICE" });
  const after = await owner.storeProduct.findUniqueOrThrow({
    where: { storeId_productId: { storeId: store, productId: product } },
  });
  expect(after.priceMillimes).toBe(before.priceMillimes);
  expect(
    CatalogRequests.Save.safeParse({
      reference: ref,
      name: "Unsafe URL",
      sourceUrls: ["javascript:alert(1)"],
    }).success,
  ).toBe(false);
});
it("exports complete append-only histories and rejects salesperson audit exports", async () => {
  const directory = await mkdtemp(
    path.join(tmpdir(), "biobalance-history-export-"),
  );
  const oldRoot = process.env.REPORT_EXPORT_ROOT;
  process.env.REPORT_EXPORT_ROOT = directory;
  const id = randomUUID(),
    reports = new ExportService(db, new DashboardService(db));
  try {
    await owner.auditEntry.createMany({
      data: Array.from({ length: 205 }, () => ({
        organizationId: org,
        storeId: store,
        actorId: actor.id,
        targetId: randomUUID(),
        action: "=Formula-safe test",
        details: {},
      })),
    });
    const query = {
      kind: "history" as const,
      organizationId: org,
      storeId: store,
      resource: "audit" as const,
    };
    await expect(
      reports.create(seller, randomUUID(), query),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
    await reports.create(actor, id, query);
    await reports.process(id, randomUUID(), async () => true);
    await owner.job.update({
      where: { key: `export:${id}` },
      data: { status: "done" },
    });
    const result = await reports.get(actor, id);
    const csv = await readFile(await reports.download(actor, id), "utf8");
    expect(result.rows).toBeGreaterThanOrEqual(205);
    expect(csv.trim().split("\n").length).toBe(result.rows + 1);
    expect(csv).toContain("'=Formula-safe test");
  } finally {
    if (oldRoot === undefined) delete process.env.REPORT_EXPORT_ROOT;
    else process.env.REPORT_EXPORT_ROOT = oldRoot;
    await rm(directory, { recursive: true, force: true });
  }
});
describe.sequential(
  "PostgreSQL transactions with a restricted application role",
  () => {
    it("denies missing RLS context and cross-store/organization requests", async () => {
      expect(await db.inventoryLot.findMany()).toEqual([]);
      expect(
        (
          await service.submit(
            foreign,
            op({
              type: "stock.receive",
              reason: "opening",
              lines: [
                {
                  productId: product,
                  batch: "T1",
                  expiry: "2027-12",
                  quantity: 10,
                },
              ],
            }),
          )
        ).code,
      ).toBe("STORE_ACCESS_REVOKED");
      expect(
        (
          await service.submit(seller, {
            ...op({ type: "stock.receive", reason: "opening", lines: [] }),
            storeId: otherStore,
          })
        ).code,
      ).toBe("STORE_ACCESS_REVOKED");
    });
    it("receives a batch atomically and deduplicates the operation", async () => {
      const operation = op({
        type: "stock.receive",
        reason: "opening",
        lines: [
          { productId: product, batch: "T1", expiry: "2027-12", quantity: 10 },
        ],
      });
      const first = await service.submit(actor, operation);
      expect(first.status).toBe("accepted");
      expect(await service.submit(actor, operation)).toEqual(first);
      const lots = await owner.inventoryLot.findMany({
        where: { storeId: store },
      });
      expect(lots).toHaveLength(1);
      expect(lots[0]!.sellable).toBe(10);
      lotId = lots[0]!.id;
      const reused = {
        ...operation,
        command: { ...operation.command, reason: "receipt" },
      } as Operation;
      expect((await service.submit(actor, reused)).code).toBe(
        "OPERATION_REUSED",
      );
    });
    it("records sales, adjustments and points together; retries retain their accepted rate", async () => {
      const sale = op({
        type: "sale.create",
        saleId,
        occurredAt: new Date().toISOString(),
        lines: [
          {
            id: lineId,
            productId: product,
            quantity: 2,
            unitPriceMillimes: "49900",
            allocations: [{ lotId, quantity: 2 }],
          },
        ],
      });
      expect((await service.submit(seller, sale)).status).toBe("accepted");
      await workspace.configureProduct(actor, org, store, product, {
        priceMillimes: "49900",
        threshold: 5,
        pointsPerUnit: 99,
        expectedVersion: 1,
      });
      expect((await service.submit(seller, sale)).data?.points).toBe("20");
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(8);
      expect(
        (
          await owner.pointsAccount.findUniqueOrThrow({
            where: { storeId_userId: { storeId: store, userId: seller.id } },
          })
        ).balance,
      ).toBe(20n);
    });
    it("allows only the original seller or a manager to correct; detects concurrent versions", async () => {
      const sale = await owner.sale.findUniqueOrThrow({
        where: { id: saleId },
      });
      const correction = op(
        {
          type: "sale.correct",
          saleId,
          occurredAt: sale.occurredAt.toISOString(),
          reason: "Correction test",
          lines: [
            {
              id: lineId,
              productId: product,
              quantity: 1,
              unitPriceMillimes: "49900",
              allocations: [{ lotId, quantity: 1 }],
            },
          ],
        },
        1,
      );
      const results = await Promise.all([
        service.submit(seller, correction),
        service.submit(actor, { ...correction, operationId: randomUUID() }),
      ]);
      expect(results.filter((r) => r.status === "accepted")).toHaveLength(1);
      expect(results.filter((r) => r.code === "VERSION_CONFLICT")).toHaveLength(
        1,
      );
      expect(
        (
          await owner.pointsAccount.findUniqueOrThrow({
            where: { storeId_userId: { storeId: store, userId: seller.id } },
          })
        ).balance,
      ).toBe(10n);
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(9);
    });
    it("reserves, fulfills a product reward once, and carries a later return into a negative balance", async () => {
      const reward = await workspace.reward(actor, org, store, {
        title: "Test reward",
        description: "",
        cost: 10,
        productId: product,
        quantity: 1,
        active: true,
      });
      const claimId = randomUUID();
      expect(
        (
          await service.submit(
            seller,
            op({ type: "reward.request", claimId, rewardId: reward.id }),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (
          await service.submit(
            seller,
            op({
              type: "reward.request",
              claimId: randomUUID(),
              rewardId: reward.id,
            }),
          )
        ).code,
      ).toBe("INSUFFICIENT_POINTS");
      const fulfill = op(
        { type: "reward.resolve", claimId, decision: "fulfilled" },
        1,
      );
      expect((await service.submit(actor, fulfill)).status).toBe("accepted");
      await service.submit(actor, fulfill);
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(8);
      expect(
        (
          await service.submit(
            seller,
            op(
              {
                type: "sale.return",
                saleId,
                reason: "Retour client",
                lines: [{ lineId, lotId, quantity: 1, sellable: true }],
              },
              2,
            ),
          )
        ).status,
      ).toBe("accepted");
      const account = await owner.pointsAccount.findUniqueOrThrow({
        where: { storeId_userId: { storeId: store, userId: seller.id } },
      });
      expect(account.balance).toBe(-10n);
      expect(account.reserved).toBe(0n);
      expect(
        (
          await service.submit(
            seller,
            op(
              {
                type: "sale.return",
                saleId,
                reason: "Doublon retour",
                lines: [{ lineId, lotId, quantity: 1, sellable: true }],
              },
              3,
            ),
          )
        ).code,
      ).toBe("RETURN_EXCEEDS_SALE");
    });
    it("rolls back mutations after failures in late transactional stages", async () => {
      for (const stage of ["move", "credit", "finish"] as const) {
        const failing: UnitOfWork = {
          run: (a, o, s, work) =>
            uow.run(a, o, s, (ledger) =>
              work(
                new Proxy(ledger, {
                  get(target, key) {
                    const value = Reflect.get(target, key);
                    if (key === stage)
                      return async (...args: unknown[]) => {
                        await value.apply(target, args);
                        throw new Error("Injected failure");
                      };
                    return typeof value === "function"
                      ? value.bind(target)
                      : value;
                  },
                }) as Ledger,
              ),
            ),
        };
        const id = randomUUID(),
          before = await owner.inventoryLot.findUniqueOrThrow({
            where: { id: lotId },
          });
        await expect(
          new OperationsService(failing).submit(
            seller,
            op({
              type: "sale.create",
              saleId: id,
              occurredAt: new Date().toISOString(),
              lines: [
                {
                  id: randomUUID(),
                  productId: product,
                  quantity: 1,
                  unitPriceMillimes: "1000",
                  allocations: [{ lotId, quantity: 1 }],
                },
              ],
            }),
          ),
        ).rejects.toThrow("Injected failure");
        expect(await owner.sale.findUnique({ where: { id } })).toBeNull();
        expect(
          (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
            .sellable,
        ).toBe(before.sellable);
      }
    });
    it("preserves insufficient-stock sales and creates one persistent discrepancy alert", async () => {
      for (let i = 0; i < 2; i++)
        expect(
          (
            await service.submit(
              seller,
              op({
                type: "sale.create",
                saleId: randomUUID(),
                occurredAt: new Date().toISOString(),
                lines: [
                  {
                    id: randomUUID(),
                    productId: product,
                    quantity: 20,
                    unitPriceMillimes: "1000",
                    allocations: [{ lotId, quantity: 20 }],
                  },
                ],
              }),
            )
          ).status,
        ).toBe("accepted");
      expect(
        await owner.alert.count({
          where: { storeId: store, kind: "discrepancy", active: true },
        }),
      ).toBe(1);
      expect(
        (
          await owner.notification.findMany({ where: { storeId: store } })
        ).every((n) => n.userId !== seller.id),
      ).toBe(true);
    });
    it("receives a shared delivery once and leaves shortages available for a follow-up", async () => {
      const orderId = randomUUID(),
        deliveryId = randomUUID();
      expect(
        (
          await service.submit(
            actor,
            op({
              type: "order.create",
              orderId,
              lines: [{ productId: product, quantity: 10 }],
            }),
          )
        ).status,
      ).toBe("accepted");
      const before = (
        await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } })
      ).sellable;
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.dispatch",
                orderId,
                deliveryId,
                lines: [{ productId: product, quantity: 10 }],
              },
              1,
            ),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(before);
      expect(
        (await workspace.fulfillment(actor, org, store, orderId)).lines,
      ).toEqual([
        {
          productId: product,
          ordered: 10,
          cancelled: 0,
          received: 0,
          inTransit: 10,
          remainingToDispatch: 0,
          remainingToReceive: 10,
        },
      ]);
      const receipt = op(
        {
          type: "delivery.receive",
          deliveryId,
          note: "Two missing",
          lines: [
            { productId: product, batch: "T1", expiry: "2027-12", quantity: 8 },
          ],
        },
        1,
      );
      const outcomes = await Promise.all([
        service.submit(actor, receipt),
        service.submit(actor, { ...receipt, operationId: randomUUID() }),
      ]);
      expect(outcomes.filter((r) => r.status === "accepted")).toHaveLength(1);
      expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(
        1,
      );
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(before + 8);
      const order = await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      });
      expect(order.status).toBe("partial");
      expect(
        (await workspace.fulfillment(admin, org, store, orderId)).lines[0],
      ).toMatchObject({
        received: 8,
        inTransit: 2,
        remainingToDispatch: 0,
        remainingToReceive: 2,
      });
      const snapshot = await workspace.snapshot(actor, org, store);
      expect(
        snapshot.orders.find((o) => o.id === orderId)?.fulfillment?.[0]
          .remainingToDispatch,
      ).toBe(0);
      await expect(
        workspace.fulfillment(foreign, org, store, orderId),
      ).rejects.toThrow();
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.resolve",
                deliveryId,
                decision: "settled",
                reason: "Remplacement des unités manquantes autorisé",
              },
              2,
            ),
          )
        ).status,
      ).toBe("accepted");
      const updated = await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      });
      const followup = randomUUID();
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.dispatch",
                orderId,
                deliveryId: followup,
                lines: [{ productId: product, quantity: 2 }],
              },
              updated.version,
            ),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (
          await service.submit(
            actor,
            op(
              {
                type: "delivery.receive",
                deliveryId: followup,
                note: "Complete",
                lines: [
                  {
                    productId: product,
                    batch: "T1",
                    expiry: "2027-12",
                    quantity: 2,
                  },
                ],
              },
              1,
            ),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (
          await owner.replenishmentOrder.findUniqueOrThrow({
            where: { id: orderId },
          })
        ).status,
      ).toBe("received");
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(before + 10);
    });
    it("records non-reception without consuming the receipt and requires resolution before replacement", async () => {
      const orderId = randomUUID(),
        deliveryId = randomUUID();
      await service.submit(
        actor,
        op({
          type: "order.create",
          orderId,
          lines: [{ productId: product, quantity: 6 }],
        }),
      );
      await service.submit(
        admin,
        op(
          {
            type: "delivery.dispatch",
            orderId,
            deliveryId,
            lines: [{ productId: product, quantity: 6 }],
          },
          1,
        ),
      );
      const invalid = await service.submit(
        actor,
        op({ type: "delivery.receive", deliveryId, lines: [], note: "   " }, 1),
      );
      expect(invalid.code).toBe("MISSING_DELIVERY_REASON");
      expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(
        0,
      );
      const missing = op(
        {
          type: "delivery.receive",
          deliveryId,
          lines: [],
          note: "Colis jamais arrivé",
        },
        1,
      );
      const result = await service.submit(actor, missing);
      expect(result.status).toBe("accepted");
      expect(await service.submit(actor, missing)).toEqual(result);
      expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(
        0,
      );
      expect(
        await owner.stockMovement.count({
          where: { operationId: missing.operationId },
        }),
      ).toBe(0);
      expect(
        (await owner.deliveryIssue.findUniqueOrThrow({ where: { deliveryId } }))
          .reason,
      ).toBe("Colis jamais arrivé");
      expect(
        (await workspace.fulfillment(actor, org, store, orderId)).lines[0],
      ).toMatchObject({ inTransit: 6, remainingToDispatch: 0 });
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.resolve",
                deliveryId,
                decision: "lost",
                reason: "Transporteur confirme la perte",
              },
              2,
            ),
          )
        ).status,
      ).toBe("accepted");
      const remaining = await workspace.fulfillment(actor, org, store, orderId);
      expect(remaining.lines[0]).toMatchObject({
        received: 0,
        inTransit: 0,
        remainingToDispatch: 6,
      });
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.dispatch",
                orderId,
                deliveryId: randomUUID(),
                lines: [{ productId: product, quantity: 7 }],
              },
              remaining.version,
            ),
          )
        ).code,
      ).toBe("DELIVERY_EXCEEDS_ORDER");
      expect(
        (
          await service.submit(
            admin,
            op(
              {
                type: "delivery.dispatch",
                orderId,
                deliveryId: randomUUID(),
                lines: [{ productId: product, quantity: 6 }],
              },
              remaining.version,
            ),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (await workspace.fulfillment(actor, org, store, orderId)).lines[0]
          .remainingToDispatch,
      ).toBe(0);
    });
    it("derives setup from saved choices and requires an explicit zero-point confirmation", async () => {
      const setupStore = randomUUID();
      await owner.store.create({
        data: {
          id: setupStore,
          organizationId: org,
          name: "Setup",
          address: "Test address",
          city: "Tunis",
        },
      });
      await owner.membership.create({
        data: {
          organizationId: org,
          storeId: setupStore,
          userId: actor.id,
          permissions: ["manage"],
        },
      });
      await expect(
        workspace.onboarding(actor, org, setupStore, { step: 5 }),
      ).rejects.toThrow("Complétez");
      let progress = await workspace.onboarding(actor, org, setupStore, {
        workingAlone: true,
        expectedVersion: 1,
      });
      expect(progress.onboarding.team).toBe(true);
      expect(progress.onboarding.stock).toBe(false);
      progress = await workspace.onboarding(actor, org, setupStore, {
        noOpeningStock: true,
        expectedVersion: progress.store.version,
      });
      expect(progress.onboarding.complete).toBe(true);
      await expect(
        workspace.configureProduct(actor, org, setupStore, product, {
          priceMillimes: "1000",
          threshold: 5,
          pointsPerUnit: 0,
        }),
      ).rejects.toThrow("Confirmez");
      expect(
        await owner.storeProduct.count({ where: { storeId: setupStore } }),
      ).toBe(0);
      const config = await workspace.configureProduct(
        actor,
        org,
        setupStore,
        product,
        {
          priceMillimes: "1000",
          threshold: 5,
          pointsPerUnit: 0,
          zeroPointsConfirmed: true,
        },
      );
      expect(config.zeroPointsConfirmed).toBe(true);
      const complete = await workspace.onboarding(actor, org, setupStore, {
        step: 5,
      });
      expect(complete.store.onboardingStep).toBe(5);
      const changed = await workspace.updateStore(actor, org, setupStore, {
        name: "Nouveau nom",
        address: "Adresse modifiée",
        city: "Sfax",
        phone: "12345678",
        expectedVersion: complete.store.version,
      });
      expect(changed.name).toBe("Nouveau nom");
      await expect(
        workspace.updateStore(actor, org, setupStore, {
          name: "Obsolète",
          address: "Test address",
          city: "Sfax",
          expectedVersion: complete.store.version,
        }),
      ).rejects.toThrow("modifié");
      await owner.storeProduct.update({
        where: { id: config.id },
        data: { zeroPointsConfirmed: false },
      });
      expect(
        (await workspace.snapshot(actor, org, setupStore)).onboarding?.complete,
      ).toBe(false);
    });
    it("sends deliberate announcements once with a frozen audience and no duplicate audit", async () => {
      const notifications = new NotificationsService(db, workspace),
        id = randomUUID();
      const before = await owner.change.count({ where: { storeId: store } });
      const results = await Promise.all([
        notifications.announce(
          actor,
          org,
          store,
          "Formation",
          "Nouveau produit",
          "salespeople",
          id,
        ),
        notifications.announce(
          actor,
          org,
          store,
          "Formation",
          "Nouveau produit",
          "salespeople",
          id,
        ),
      ]);
      expect(results[0]).toEqual(results[1]);
      expect(await owner.announcement.count({ where: { id } })).toBe(1);
      expect(await owner.notification.count({ where: { eventKey: id } })).toBe(
        2,
      );
      expect(await owner.auditEntry.count({ where: { targetId: id } })).toBe(1);
      expect(await owner.change.count({ where: { storeId: store } })).toBe(
        before + 1,
      );
      await expect(
        notifications.announce(
          actor,
          org,
          store,
          "Changed",
          "Autre texte",
          "salespeople",
          id,
        ),
      ).rejects.toThrow("autre contenu");
      await expect(
        notifications.announce(
          seller,
          org,
          store,
          "Message",
          "Interdit",
          "all",
          randomUUID(),
        ),
      ).rejects.toThrow("responsable");
    });
    it("replays training submissions without duplicate content and rejects stale edits", async () => {
      const training = new TrainingService(db),
        id = randomUUID(),
        submissionId = randomUUID();
      const input = {
        id,
        submissionId,
        expectedVersion: 0,
        title: "Formation produit",
        body: "<p>Conseils &amp; usage</p>",
        type: "article",
        productIds: [product],
        status: "draft",
      };
      const [first, replay] = await Promise.all([
        training.save(admin, input),
        training.save(admin, input),
      ]);
      expect(first).toEqual(replay);
      expect(first.version).toBe(1);
      expect(await owner.trainingContent.count({ where: { id } })).toBe(1);
      expect(await owner.auditEntry.count({ where: { targetId: id } })).toBe(1);
      await expect(training.save(seller, input)).rejects.toThrow("BioBalance");
      await expect(
        training.save(admin, { ...input, title: "Different title" }),
      ).rejects.toThrow("tentative");
      const published = await training.save(admin, {
        ...input,
        submissionId: randomUUID(),
        expectedVersion: 1,
        status: "published",
      });
      expect(published.version).toBe(2);
      await expect(
        training.save(admin, {
          ...input,
          submissionId: randomUUID(),
          expectedVersion: 1,
        }),
      ).rejects.toThrow("modifié");
      expect(await training.save(admin, input)).toEqual(first);
    });
    it("rejects another active seller editing the original seller's sale", async () => {
      await owner.membership.create({
        data: {
          organizationId: org,
          storeId: store,
          userId: foreign.id,
          permissions: ["sell"],
        },
      });
      const sale = await owner.sale.findUniqueOrThrow({
        where: { id: saleId },
      });
      const result = await service.submit(
        foreign,
        op(
          {
            type: "sale.correct",
            saleId,
            occurredAt: sale.occurredAt.toISOString(),
            reason: "Unauthorized",
            lines: sale.lines as any,
          },
          sale.version,
        ),
      );
      expect(result.code).toBe("FORBIDDEN");
      await owner.membership.update({
        where: { storeId_userId: { storeId: store, userId: foreign.id } },
        data: { active: false },
      });
    });
    it("synchronizes changed lots and invalidates a changed global catalog", async () => {
      const snapshot = await workspace.snapshot(actor, org, store);
      expect(snapshot.mode).toBe("snapshot");
      await service.submit(
        actor,
        op({
          type: "stock.receive",
          reason: "receipt",
          lines: [
            {
              productId: product,
              batch: "DELTA",
              expiry: "2028-01",
              quantity: 3,
            },
          ],
        }),
      );
      const delta = await workspace.snapshot(actor, org, store, {
        cursor: snapshot.cursor,
        catalogRevision: snapshot.catalogRevision,
      });
      expect(delta.mode).toBe("delta");
      expect(delta.products).toHaveLength(0);
      expect(delta.lots).toHaveLength(1);
      expect(delta.lots[0]!.batch).toBe("DELTA");
      expect(delta.lots[0]!.sellable).toBe(3);
      await owner.product.update({
        where: { id: product },
        data: { name: "Changed globally", version: { increment: 1 } },
      });
      const refreshed = await workspace.snapshot(actor, org, store, {
        cursor: delta.cursor,
        catalogRevision: delta.catalogRevision,
      });
      expect(refreshed.mode).toBe("snapshot");
      expect(refreshed.products.find((p) => p.id === product)?.name).toBe(
        "Changed globally",
      );
    });
    it("removes disabled team access from synchronized data and denies further operations", async () => {
      const before = await workspace.snapshot(actor, org, store);
      await workspace.setMember(actor, org, store, seller.id, {
        active: false,
        permissions: ["sell", "receive"],
      });
      const delta = await workspace.snapshot(actor, org, store, {
        cursor: before.cursor,
        catalogRevision: before.catalogRevision,
      });
      expect(delta.team.find((m) => m.userId === seller.id)?.active).toBe(
        false,
      );
      await expect(
        workspace.snapshot(seller, org, store),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
      await workspace.setMember(actor, org, store, seller.id, {
        active: true,
        permissions: ["sell", "receive"],
      });
    });
    it("keeps receipt-sale-damage-correction-return versions and ledgers consistent", async () => {
      const pointsRate = (
        await owner.storeProduct.findUniqueOrThrow({
          where: { storeId_productId: { storeId: store, productId: product } },
        })
      ).pointsPerUnit;
      const receipt = {
        ...op({
          type: "stock.receive",
          reason: "receipt",
          lines: [
            {
              productId: product,
              batch: "CHAIN",
              expiry: "2029-12-31",
              quantity: 10,
            },
          ],
        }),
        payloadVersion: 2 as const,
        dependencies: [],
      };
      const received = await service.submit(actor, receipt);
      const lot = await owner.inventoryLot.findFirstOrThrow({
        where: { storeId: store, batch: "CHAIN" },
      });
      expect(lot.version).toBe(2);
      const sale = randomUUID(),
        line = randomUUID(),
        occurredAt = new Date().toISOString();
      const lines = (quantity: number) => [
        {
          id: line,
          productId: product,
          quantity,
          unitPriceMillimes: "1000",
          allocations: [{ lotId: lot.id, quantity }],
        },
      ];
      const create = {
        ...op({
          type: "sale.create",
          saleId: sale,
          occurredAt,
          lines: lines(4),
        }),
        payloadVersion: 2 as const,
        dependencies: [receipt.operationId],
      };
      expect((await service.submit(actor, create)).status).toBe("accepted");
      const damage = {
        ...op(
          { type: "stock.damage", lotId: lot.id, quantity: 1, reason: "Casse" },
          3,
        ),
        payloadVersion: 2 as const,
        dependencies: [create.operationId],
      };
      expect(
        (await service.submit(actor, damage)).affectedVersions,
      ).toContainEqual({ resource: "lots", id: lot.id, version: 5 });
      const correct = {
        ...op(
          {
            type: "sale.correct",
            saleId: sale,
            occurredAt,
            lines: lines(3),
            reason: "Erreur de quantité",
          },
          1,
        ),
        payloadVersion: 2 as const,
        dependencies: [damage.operationId],
      };
      expect((await service.submit(actor, correct)).status).toBe("accepted");
      const returned = {
        ...op(
          {
            type: "sale.return",
            saleId: sale,
            reason: "Retour client",
            lines: [
              { lineId: line, lotId: lot.id, quantity: 1, sellable: true },
            ],
          },
          2,
        ),
        payloadVersion: 2 as const,
        dependencies: [correct.operationId],
      };
      const accepted = await service.submit(actor, returned);
      expect(accepted.status).toBe("accepted");
      expect(await service.submit(actor, receipt)).toEqual(received);
      expect(await service.submit(actor, returned)).toEqual(accepted);
      expect(
        await owner.inventoryLot.findUniqueOrThrow({ where: { id: lot.id } }),
      ).toMatchObject({ sellable: 7, damaged: 1, version: 7 });
      expect(
        await owner.stockMovement.count({ where: { lotId: lot.id } }),
      ).toBe(6);
      expect(await owner.saleRevision.count({ where: { saleId: sale } })).toBe(
        3,
      );
      const entries = await owner.pointsEntry.findMany({
        where: { storeId: store, sourceId: sale },
      });
      expect(entries.reduce((n, e) => n + e.amount, 0n)).toBe(
        BigInt(pointsRate * 2),
      );
      const pending = {
        ...op(
          { type: "stock.damage", lotId: lot.id, quantity: 1, reason: "Casse" },
          7,
        ),
        payloadVersion: 2 as const,
        dependencies: [randomUUID()],
      };
      expect((await service.submit(actor, pending)).status).toBe("blocked");
      expect(
        await owner.stockMovement.count({ where: { lotId: lot.id } }),
      ).toBe(6);
      const snapshot = await workspace.snapshot(
        actor,
        org,
        store,
        undefined,
        3,
        [returned.operationId],
      );
      expect(snapshot.appliedOperationIds).toEqual([returned.operationId]);
      expect(BigInt(snapshot.cursor)).toBeGreaterThanOrEqual(
        BigInt(accepted.committedCursor!),
      );
    });
    it("freezes snapshot pages and rechecks account, store, expiry and permissions", async () => {
      await owner.inventoryLot.createMany({
        data: Array.from({ length: 505 }, (_, i) => ({
          id: randomUUID(),
          organizationId: org,
          storeId: store,
          productId: product,
          batch: `PAGE-${i}`,
          expiry: new Date("2029-12-31"),
          sellable: 2,
        })),
      });
      const snapshot = await workspace.snapshot(
        actor,
        org,
        store,
        undefined,
        3,
      );
      const token = snapshot.snapshotPages.lots!;
      expect(token).toBeTruthy();
      const before = (await workspace.snapshotPage(
        actor,
        org,
        store,
        token,
      )) as any;
      const target = before.items[0];
      await service.submit(
        actor,
        op(
          {
            type: "stock.adjust",
            lotId: target.id,
            quantity: 9,
            reason: "Comptage",
          },
          target.version,
        ),
      );
      expect(await workspace.snapshotPage(actor, org, store, token)).toEqual(
        before,
      );
      await expect(
        workspace.snapshotPage(seller, org, store, token),
      ).rejects.toMatchObject({ code: "SNAPSHOT_EXPIRED" });
      await expect(
        workspace.snapshotPage(actor, org, otherStore, token),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
      await workspace.setMember(actor, org, store, seller.id, {
        active: false,
        permissions: ["sell"],
      });
      await expect(
        workspace.snapshotPage(seller, org, store, token),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
      await workspace.setMember(actor, org, store, seller.id, {
        active: true,
        permissions: ["sell", "receive"],
      });
      await owner.syncSnapshotPage.update({
        where: { id: token },
        data: { expiresAt: new Date(0) },
      });
      await expect(
        workspace.snapshotPage(actor, org, store, token),
      ).rejects.toMatchObject({ code: "SNAPSHOT_EXPIRED" });
    });
    it("checks invitation rights in the write transaction and rejects revoked sessions", async () => {
      const identity = new IdentityService(db);
      const email = `invite-${randomUUID()}@example.test`;
      await owner.membership.update({
        where: { storeId_userId: { storeId: store, userId: actor.id } },
        data: { permissions: ["sell"] },
      });
      await expect(
        identity.invite(actor, {
          email,
          organizationId: org,
          storeId: store,
          permissions: ["sell"],
        }),
      ).rejects.toMatchObject({ code: "FORBIDDEN" });
      expect(await owner.accessToken.count({ where: { email } })).toBe(0);
      await owner.membership.update({
        where: { storeId_userId: { storeId: store, userId: actor.id } },
        data: { permissions: ["manage", "sell", "receive"] },
      });
      const invitation = await identity.invite(actor, {
        email,
        organizationId: org,
        storeId: store,
        permissions: ["sell"],
      });
      expect(invitation.status).toBe("invited");
      expect(
        await owner.job.count({ where: { key: `invite:${invitation.id}` } }),
      ).toBe(1);
      const session = await owner.session.create({
        data: {
          userId: actor.id,
          tokenHash: randomUUID(),
          expiresAt: new Date(Date.now() + 60_000),
          revokedAt: new Date(),
        },
      });
      const result = await service.submit(
        { ...actor, sessionId: session.id },
        op({
          type: "stock.receive",
          reason: "receipt",
          lines: [
            {
              productId: product,
              batch: "REVOKED",
              expiry: "2029-12-31",
              quantity: 1,
            },
          ],
        }),
      );
      expect(result.code).toBe("SESSION_EXPIRED");
      expect(
        await owner.inventoryLot.count({
          where: { storeId: store, batch: "REVOKED" },
        }),
      ).toBe(0);
    });
    it("lets sellers declare a missing batch atomically without incoming stock", async () => {
      const id = lotIdentity(store, product, "MISSING", "2029-12-31"),
        saleId = randomUUID();
      const command: Command = {
        type: "sale.create",
        saleId,
        occurredAt: new Date().toISOString(),
        batchDeclarations: [
          {
            lotId: id,
            productId: product,
            batch: "MISSING",
            expiry: "2029-12",
          },
        ],
        lines: [
          {
            id: randomUUID(),
            productId: product,
            quantity: 2,
            unitPriceMillimes: "14990",
            allocations: [{ lotId: id, quantity: 2 }],
          },
        ],
      };
      const operation = op(command);
      const accepted = await service.submit(seller, operation);
      expect(accepted.status).toBe("accepted");
      expect(await service.submit(seller, operation)).toEqual(accepted);
      expect(
        await owner.inventoryLot.findUniqueOrThrow({ where: { id } }),
      ).toMatchObject({ sellable: -2, damaged: 0, version: 2 });
      const movements = await owner.stockMovement.findMany({
        where: { lotId: id },
      });
      expect(movements).toHaveLength(1);
      expect(movements[0]!.quantity).toBe(-2);
      expect(movements[0]!.reason).toBe("sale.create");
      expect(
        await owner.alert.count({
          where: {
            storeId: store,
            productId: product,
            kind: "discrepancy",
            active: true,
          },
        }),
      ).toBe(1);
      const expiredId = lotIdentity(
        store,
        product,
        "EXPIRED-DECLARATION",
        "2020-01-31",
      );
      const expired = await service.submit(
        seller,
        op({
          ...command,
          saleId: randomUUID(),
          batchDeclarations: [
            {
              lotId: expiredId,
              productId: product,
              batch: "EXPIRED-DECLARATION",
              expiry: "2020-01",
            },
          ],
          lines: [
            {
              ...command.lines[0]!,
              allocations: [{ lotId: expiredId, quantity: 2 }],
            },
          ],
        }),
      );
      expect(expired.code).toBe("LOT_EXPIRED");
      expect(
        await owner.inventoryLot.findUnique({ where: { id: expiredId } }),
      ).toBeNull();
      const spoofed = randomUUID();
      const spoof = await service.submit(
        seller,
        op({
          ...command,
          saleId: randomUUID(),
          batchDeclarations: [
            {
              lotId: spoofed,
              productId: product,
              batch: "SPOOF",
              expiry: "2029-12",
            },
          ],
          lines: [
            {
              ...command.lines[0]!,
              allocations: [{ lotId: spoofed, quantity: 2 }],
            },
          ],
        }),
      );
      expect(spoof.code).toBe("INVALID_LOT_IDENTITY");
      expect(
        await owner.inventoryLot.findUnique({ where: { id: spoofed } }),
      ).toBeNull();
    });
    it("rechecks current session and permissions in the optimized access read", async () => {
      const user = await owner.user.create({
        data: {
          email: `${randomUUID()}@example.test`,
          name: "Access probe",
          passwordHash: "no-login",
        },
      });
      const membership = await owner.organizationMembership.create({
        data: {
          organizationId: org,
          userId: user.id,
        },
      });
      const token = randomUUID() + randomUUID();
      const session = await owner.session.create({
        data: {
          userId: user.id,
          tokenHash: tokenHash(token),
          expiresAt: new Date(Date.now() + 60000),
        },
      });
      const identity = new IdentityService(db);
      const authenticated = await identity.authenticate(token);
      expect(authenticated.sessionId).toBe(session.id);
      expect(
        await db.scoped(
          authenticated,
          org,
          store,
          async (_tx, scope) => scope.permissions,
        ),
      ).toContain("manage");
      await owner.organizationMembership.update({
        where: { id: membership.id },
        data: { active: false },
      });
      await expect(
        db.scoped(
          { ...authenticated, platformAdmin: true },
          org,
          store,
          async () => true,
        ),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
      await owner.user.update({
        where: { id: user.id },
        data: { disabled: true },
      });
      await expect(identity.authenticate(token)).rejects.toMatchObject({
        code: "ACCESS_DISABLED",
      });
      await expect(
        db.scoped(authenticated, org, store, async () => true),
      ).rejects.toMatchObject({ code: "ACCESS_DISABLED" });
      await owner.session.update({
        where: { id: session.id },
        data: { expiresAt: new Date(Date.now() - 1000) },
      });
      await expect(identity.authenticate(token)).rejects.toMatchObject({
        code: "SESSION_EXPIRED",
      });
      await expect(
        db.scoped(authenticated, org, store, async () => true),
      ).rejects.toMatchObject({ code: "SESSION_EXPIRED" });
      await expect(
        identity.authenticate(randomUUID() + randomUUID()),
      ).rejects.toMatchObject({ code: "SESSION_EXPIRED" });
    });
    it("paginates optimized sale reads without crossing seller or store scope", async () => {
      const seller: Actor = {
        id: randomUUID(),
        name: "Read seller",
        email: `read-seller-${randomUUID()}@example.test`,
        platformAdmin: false,
      };
      await owner.user.create({
        data: { ...seller, passwordHash: "test-only-not-a-login" },
      });
      const readStore = await owner.store.create({
        data: {
          organizationId: org,
          name: "Read projection fixture",
          address: "Test address",
          city: "Tunis",
        },
      });
      for (const userId of [actor.id, seller.id])
        await owner.membership.create({
          data: {
            organizationId: org,
            storeId: readStore.id,
            userId,
            permissions: userId === actor.id ? ["manage"] : ["sell"],
          },
        });
      const otherProduct = await owner.product.create({
        data: { reference: randomUUID(), name: "Read pagination product" },
      });
      const rows = Array.from({ length: 201 }, (_, i) => ({
        id: randomUUID(),
        organizationId: org,
        storeId: readStore.id,
        sellerId: i % 2 ? actor.id : seller.id,
        occurredAt: new Date("2026-09-21T10:00:00Z"),
        totalMillimes: 12345n,
        earnedPoints: 0n,
        lines: [
          {
            id: randomUUID(),
            productId: i < 50 ? product : otherProduct.id,
            quantity: 1,
            unitPriceMillimes: "12345",
            allocations: [],
          },
        ],
      }));
      await owner.sale.createMany({ data: rows });
      const found: string[] = [];
      let before: string | undefined;
      do {
        const page = await workspace.history(
          actor,
          org,
          readStore.id,
          "sales",
          undefined,
          before,
        );
        found.push(...page.items.map((row) => row.id));
        before = page.nextCursor ?? undefined;
      } while (before);
      expect(new Set(found).size).toBe(201);
      expect(found).toEqual(
        rows
          .map((row) => row.id)
          .sort()
          .reverse(),
      );
      const own = await workspace.history(seller, org, readStore.id, "sales");
      expect(own.items.every((row) => row.sellerId === seller.id)).toBe(true);
      expect(own.items[0].totalMillimes).toBe(12345n);
      expect(own.items[0].occurredAt).toEqual(new Date("2026-09-21T10:00:00Z"));
      const filtered = await workspace.history(
        actor,
        org,
        readStore.id,
        "sales",
        product,
      );
      expect(filtered.items).toHaveLength(50);
      const exactBalance = 9007199254740993n;
      await owner.pointsAccount.create({
        data: {
          organizationId: org,
          storeId: readStore.id,
          userId: seller.id,
          balance: exactBalance,
          reserved: 2n,
        },
      });
      const delta = await workspace.snapshot(
        seller,
        org,
        readStore.id,
        { cursor: "0", catalogRevision: "invalid" },
        3,
      );
      expect(delta.sales.every((row) => row.sellerId === seller.id)).toBe(true);
      expect(delta.points.balance).toBe(exactBalance);
      expect(delta.points.reserved).toBe(2n);
    });
    it("rejects editing append-only histories at database level", async () => {
      const movement = await owner.stockMovement.findFirstOrThrow({
        where: { storeId: store },
      });
      await expect(
        owner.stockMovement.update({
          where: { id: movement.id },
          data: { quantity: 100 },
        }),
      ).rejects.toThrow();
    });
  },
);
