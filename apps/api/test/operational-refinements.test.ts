import { beforeAll, afterAll, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { assertTestDatabases } from "./test-database.cjs";
import { Database } from "../src/shared/infrastructure/database";
import { OperationsService } from "../src/modules/operations/application/operations.service";
import { PrismaUnitOfWork } from "../src/modules/operations/infrastructure/prisma-ledger";
import {
  Actor,
  Command,
  Operation,
} from "../src/modules/operations/domain/contracts";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { WorkspaceLifecycle } from "../src/modules/tenancy/lifecycle";
import { NotificationsService } from "../src/modules/notifications/notifications.service";
import { DashboardService } from "../src/modules/reporting/dashboard.service";
import { invitationIsAuthorized } from "../src/modules/identity/invitation-policy";
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
  ops = new OperationsService(new PrismaUnitOfWork(db)),
  lifecycle = new WorkspaceLifecycle(db),
  notifications = new NotificationsService(db, workspace),
  reports = new DashboardService(db);
const actor = (admin = false): Actor => ({
  id: randomUUID(),
  name: "Test",
  email: `${randomUUID()}@example.test`,
  platformAdmin: admin,
});
const admin = actor(true),
  manager = actor(),
  seller = actor();
let org: string, store: string, product: string;
const op = (command: Command, expectedVersion?: number): Operation => ({
  operationId: randomUUID(),
  organizationId: org,
  storeId: store,
  payloadVersion: 2,
  command,
  expectedVersion,
});
async function shipment(quantity = 10) {
  const orderId = randomUUID(),
    deliveryId = randomUUID();
  expect(
    (
      await ops.submit(
        manager,
        op({
          type: "order.create",
          orderId,
          lines: [{ productId: product, quantity }],
        }),
      )
    ).status,
  ).toBe("accepted");
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "delivery.dispatch",
            orderId,
            deliveryId,
            lines: [{ productId: product, quantity }],
          },
          1,
        ),
      )
    ).status,
  ).toBe("accepted");
  return { orderId, deliveryId };
}
beforeAll(async () => {
  for (const a of [admin, manager, seller])
    await owner.user.create({ data: { ...a, passwordHash: "not-a-login" } });
  org = (
    await owner.organization.create({
      data: { name: "Operational refinement fixtures" },
    })
  ).id;
  store = (
    await owner.store.create({
      data: {
        organizationId: org,
        name: "Test store",
        address: "Fixture",
        city: "Tunis",
      },
    })
  ).id;
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: manager.id },
  });
  await owner.membership.create({
    data: {
      organizationId: org,
      storeId: store,
      userId: seller.id,
      permissions: ["sell", "receive"],
    },
  });
  product = (
    await owner.product.create({
      data: { reference: randomUUID(), name: "Fixture serum" },
    })
  ).id;
});
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});
it("denies every seller stock/reception route even with a legacy receive grant", async () => {
  const { deliveryId, orderId } = await shipment();
  const commands: Command[] = [
    {
      type: "delivery.receive",
      deliveryId,
      lines: [
        { productId: product, batch: "S", expiry: "2028-12", quantity: 1 },
      ],
      note: "",
    },
    { type: "delivery.report", deliveryId, reason: "Colis absent" },
    { type: "order.cancel", orderId, reason: "Pas autorisé" },
    {
      type: "stock.receive",
      reason: "receipt",
      lines: [
        { productId: product, batch: "S", expiry: "2028-12", quantity: 1 },
      ],
    },
  ];
  for (const command of commands)
    expect((await ops.submit(seller, op(command, 1))).code).toBe("FORBIDDEN");
  expect((await workspace.stores(seller))[0]!.permissions).toEqual(["sell"]);
  await expect(reports.order(seller, org, store, orderId)).rejects.toThrow();
  expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(0);
});
it("retains one physical reception after a delayed parcel is reported and then arrives", async () => {
  const { deliveryId } = await shipment(4);
  const report = op(
    { type: "delivery.report", deliveryId, reason: "Colis pas encore arrivé" },
    1,
  );
  const result = await ops.submit(manager, report);
  expect(result.status).toBe("accepted");
  expect(await ops.submit(manager, report)).toEqual(result);
  expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(0);
  expect(
    await owner.stockMovement.count({
      where: { operationId: report.operationId },
    }),
  ).toBe(0);
  const receipt = op(
    {
      type: "delivery.receive",
      deliveryId,
      lines: [
        { productId: product, batch: "LATE", expiry: "2028-12", quantity: 4 },
      ],
      note: "",
    },
    2,
  );
  const outcomes = await Promise.all([
    ops.submit(manager, receipt),
    ops.submit(manager, { ...receipt, operationId: randomUUID() }),
  ]);
  expect(outcomes.filter((r) => r.status === "accepted")).toHaveLength(1);
  expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(1);
  expect(
    (await owner.deliveryIssue.findUniqueOrThrow({ where: { deliveryId } }))
      .status,
  ).toBe("resolved");
});
it("does not accept a lost original after its replacement was dispatched", async () => {
  const { orderId, deliveryId } = await shipment(3);
  await ops.submit(
    manager,
    op({ type: "delivery.report", deliveryId, reason: "Non reçue" }, 1),
  );
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "delivery.resolve",
            deliveryId,
            decision: "lost",
            reason: "Transporteur confirme perte",
          },
          2,
        ),
      )
    ).status,
  ).toBe("accepted");
  const order = await owner.replenishmentOrder.findUniqueOrThrow({
    where: { id: orderId },
  });
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "delivery.dispatch",
            orderId,
            deliveryId: randomUUID(),
            lines: [{ productId: product, quantity: 3 }],
          },
          order.version,
        ),
      )
    ).status,
  ).toBe("accepted");
  const rejected = await ops.submit(
    manager,
    op(
      {
        type: "delivery.receive",
        deliveryId,
        lines: [
          { productId: product, batch: "DUP", expiry: "2028-12", quantity: 3 },
        ],
        note: "",
      },
      3,
    ),
  );
  expect(rejected.status).toBe("conflict");
  expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(0);
});
it("preserves original quantities, forbids reducing commitments, and closes only an available remainder", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 20 }],
    }),
  );
  const amend = op(
    {
      type: "order.amend",
      orderId,
      lines: [{ productId: product, quantity: 15 }],
      reason: "Accord responsable",
    },
    1,
  );
  expect((await ops.submit(admin, amend)).status).toBe("accepted");
  expect(
    (
      await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      })
    ).requestedLines,
  ).toEqual([{ productId: product, quantity: 20 }]);
  await ops.submit(
    admin,
    op(
      {
        type: "delivery.dispatch",
        orderId,
        deliveryId: randomUUID(),
        lines: [{ productId: product, quantity: 10 }],
      },
      2,
    ),
  );
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "order.amend",
            orderId,
            lines: [{ productId: product, quantity: 9 }],
            reason: "Impossible",
          },
          3,
        ),
      )
    ).code,
  ).toBe("ORDER_COMMITTED");
  expect(
    (
      await ops.submit(
        admin,
        op({ type: "order.cancel", orderId, reason: "Annule le reste" }, 3),
      )
    ).status,
  ).toBe("accepted");
  const fulfillment = await workspace.fulfillment(manager, org, store, orderId);
  expect(fulfillment.lines[0]).toMatchObject({
    ordered: 15,
    cancelled: 5,
    inTransit: 10,
    remainingToDispatch: 0,
  });
  const cancelled = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId: cancelled,
      lines: [{ productId: product, quantity: 2 }],
    }),
  );
  await ops.submit(
    admin,
    op(
      { type: "order.cancel", orderId: cancelled, reason: "Demande retirée" },
      1,
    ),
  );
  expect(
    (
      await ops.submit(
        admin,
        op({ type: "order.prepare", orderId: cancelled }, 2),
      )
    ).code,
  ).toBe("ORDER_COMPLETE");
});
it("suspends inherited access atomically, retains queues, and does not revive a disabled member", async () => {
  const invite = await owner.accessToken.create({
    data: {
      email: "fixture@example.test",
      tokenHash: randomUUID(),
      purpose: "invite",
      organizationId: org,
      storeIds: [store],
      permissions: ["sell"],
      kind: "salesperson",
      createdBy: manager.id,
      expiresAt: new Date(Date.now() + 60000),
    },
  });
  const command = op({
    type: "order.create",
    orderId: randomUUID(),
    lines: [{ productId: product, quantity: 1 }],
  });
  const request = {
    operationId: randomUUID(),
    expectedVersion: 1,
    status: "suspended" as const,
    reason: "Test de suspension",
  };
  await lifecycle.change(admin, org, undefined, request);
  await expect(
    lifecycle.change(admin, org, undefined, request),
  ).resolves.toEqual({ ok: true });
  expect((await ops.submit(manager, command)).code).toBe(
    "STORE_ACCESS_REVOKED",
  );
  expect(await workspace.stores(manager)).toEqual([]);
  expect(await invitationIsAuthorized(owner as never, invite)).toBe(false);
  await owner.membership.updateMany({
    where: { userId: seller.id },
    data: { active: false },
  });
  await lifecycle.change(admin, org, undefined, {
    ...request,
    operationId: randomUUID(),
    expectedVersion: 2,
    status: "active",
  });
  expect((await ops.submit(manager, command)).status).toBe("accepted");
  expect(await workspace.stores(seller)).toEqual([]);
  await expect(
    lifecycle.change(admin, org, undefined, {
      ...request,
      operationId: randomUUID(),
      expectedVersion: 3,
      status: "archived",
    }),
  ).rejects.toMatchObject({ code: "OUTSTANDING_WORK" });
  await owner.membership.updateMany({
    where: { userId: seller.id },
    data: { active: true },
  });
});
it("paginates tied notification timestamps without skips and counts only current recipients", async () => {
  const createdAt = new Date("2026-01-01T00:00:00Z");
  await owner.notification.createMany({
    data: Array.from({ length: 120 }, () => ({
      organizationId: org,
      storeId: store,
      userId: seller.id,
      title: "Équipe",
      body: "Test",
      eventKey: randomUUID(),
      kind: "announcement",
      audience: "all",
      createdAt,
    })),
  });
  await owner.notification.create({
    data: {
      organizationId: org,
      storeId: store,
      userId: seller.id,
      title: "Privé",
      body: "Responsables",
      eventKey: randomUUID(),
      kind: "operational",
    },
  });
  let page = await notifications.inbox(seller);
  expect(page.unreadCount).toBe(120);
  const ids = new Set(page.items.map((n) => n.id));
  while (page.nextCursor) {
    const [date, id] = page.nextCursor.split("|");
    page = await notifications.inbox(seller, { date: date!, id: id! });
    for (const n of page.items) {
      expect(ids.has(n.id)).toBe(false);
      ids.add(n.id);
    }
  }
  expect(ids.size).toBe(120);
  const id = [...ids][0]!;
  await notifications.read(seller, id);
  await notifications.read(seller, id);
  expect((await notifications.inbox(seller)).unreadCount).toBe(119);
  await owner.membership.updateMany({
    where: { userId: seller.id },
    data: { active: false },
  });
  expect((await notifications.inbox(seller)).unreadCount).toBe(0);
  await expect(notifications.get(seller, id)).rejects.toThrow();
});
it("tracks damaged/refused/surplus receipts without counting them as approved supply", async () => {
  const { orderId, deliveryId } = await shipment(10);
  const receipt = op(
    {
      type: "delivery.receive",
      deliveryId,
      note: "Deux abîmés, deux refusés",
      lines: [
        { productId: product, batch: "MIXED", expiry: "2028-12", quantity: 6 },
        {
          productId: product,
          batch: "MIXED",
          expiry: "2028-12",
          quantity: 2,
          condition: "damaged",
        },
        {
          productId: product,
          batch: "MIXED",
          expiry: "2028-12",
          quantity: 2,
          condition: "refused",
        },
      ],
    },
    1,
  );
  expect((await ops.submit(manager, receipt)).status).toBe("accepted");
  const lot = await owner.inventoryLot.findFirstOrThrow({
    where: { storeId: store, productId: product, batch: "MIXED" },
  });
  expect([lot.sellable, lot.damaged, lot.version]).toEqual([6, 2, 3]);
  const detail = await reports.order(admin, org, store, orderId);
  expect(detail.fulfillment[0]).toMatchObject({
    received: 6,
    inTransit: 4,
    remainingToDispatch: 0,
  });
  const extra = await shipment(3);
  expect(
    (
      await ops.submit(
        manager,
        op(
          {
            type: "delivery.receive",
            deliveryId: extra.deliveryId,
            note: "Deux unités supplémentaires",
            lines: [
              {
                productId: product,
                batch: "SURPLUS",
                expiry: "2028-12",
                quantity: 5,
              },
            ],
          },
          1,
        ),
      )
    ).status,
  ).toBe("accepted");
  expect(
    (await reports.order(admin, org, store, extra.orderId)).fulfillment[0]!
      .received,
  ).toBe(3);
  expect(
    (
      await owner.inventoryLot.findFirstOrThrow({
        where: { storeId: store, batch: "SURPLUS" },
      })
    ).sellable,
  ).toBe(5);
  expect(
    (
      await owner.deliveryIssue.findUniqueOrThrow({
        where: { deliveryId: extra.deliveryId },
      })
    ).status,
  ).toBe("open");
});
it("keeps partially received orders visible while another shipment is in transit", async () => {
  const { orderId, deliveryId } = await shipment(10);
  await ops.submit(
    manager,
    op(
      {
        type: "delivery.receive",
        deliveryId,
        note: "Partiel",
        lines: [
          {
            productId: product,
            batch: "PARTIAL",
            expiry: "2028-12",
            quantity: 6,
          },
        ],
      },
      1,
    ),
  );
  await ops.submit(
    admin,
    op(
      {
        type: "delivery.resolve",
        deliveryId,
        decision: "settled",
        reason: "Reliquat confirmé",
      },
      2,
    ),
  );
  const order = await owner.replenishmentOrder.findUniqueOrThrow({
    where: { id: orderId },
  });
  await ops.submit(
    admin,
    op(
      {
        type: "delivery.dispatch",
        orderId,
        deliveryId: randomUUID(),
        lines: [{ productId: product, quantity: 4 }],
      },
      order.version,
    ),
  );
  const list = await reports.orders(
    admin,
    {
      scope: "store",
      organizationId: org,
      storeId: store,
      from: "2026-09-01",
      to: "2026-09-30",
    },
    undefined,
    "transit",
  );
  expect(list.items.map((i) => i.id)).toContain(orderId);
});
