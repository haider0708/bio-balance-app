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
it("lets a responsible cancel an unprepared request once without moving stock", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 7 }],
    }),
  );
  const cancel = op(
    { type: "order.cancel", orderId, reason: "Demande devenue inutile" },
    1,
  );
  const accepted = await ops.submit(manager, cancel);
  expect(accepted.status).toBe("accepted");
  expect(await ops.submit(manager, cancel)).toEqual(accepted);
  expect(
    (
      await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      })
    ).status,
  ).toBe("cancelled");
  expect(
    await owner.stockMovement.count({
      where: { operationId: cancel.operationId },
    }),
  ).toBe(0);
});
it("closes responsible cancellation at preparation and retains admin remainder controls", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 7 }],
    }),
  );
  expect(
    (await ops.submit(admin, op({ type: "order.prepare", orderId }, 1))).status,
  ).toBe("accepted");
  const rejected = await ops.submit(
    manager,
    op({ type: "order.cancel", orderId, reason: "Trop tard" }, 2),
  );
  expect(rejected.code).toBe("ORDER_CANCELLATION_CLOSED");
  expect(
    (
      await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      })
    ).status,
  ).toBe("preparing");
  expect(
    (
      await ops.submit(
        admin,
        op({ type: "order.cancel", orderId, reason: "Accord avec magasin" }, 2),
      )
    ).status,
  ).toBe("accepted");
});
it("serializes cancellation racing with preparation without changing inventory", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 3 }],
    }),
  );
  const prepare = op({ type: "order.prepare", orderId }, 1);
  const cancel = op(
    { type: "order.cancel", orderId, reason: "Annulation magasin" },
    1,
  );
  const results = await Promise.all([
    ops.submit(admin, prepare),
    ops.submit(manager, cancel),
  ]);
  expect(results.filter((r) => r.status === "accepted")).toHaveLength(1);
  expect(results.filter((r) => r.status === "conflict")).toHaveLength(1);
  const saved = await owner.replenishmentOrder.findUniqueOrThrow({
    where: { id: orderId },
  });
  expect(["preparing", "cancelled"]).toContain(saved.status);
  expect(saved.version).toBe(2);
  expect(
    await owner.stockMovement.count({
      where: { operationId: { in: [prepare.operationId, cancel.operationId] } },
    }),
  ).toBe(0);
});
it("keeps an amended request cancellable before preparation and never moves a shipment backwards", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 8 }],
    }),
  );
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "order.amend",
            orderId,
            lines: [{ productId: product, quantity: 6 }],
            reason: "Quantité convenue",
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
  ).toBe("requested");
  expect(
    (
      await ops.submit(
        manager,
        op(
          {
            type: "order.cancel",
            orderId,
            reason: "Annulation avant préparation",
          },
          2,
        ),
      )
    ).status,
  ).toBe("accepted");
  const sent = await shipment(3);
  expect(
    (
      await ops.submit(
        admin,
        op({ type: "order.prepare", orderId: sent.orderId }, 2),
      )
    ).code,
  ).toBe("ORDER_PREPARATION_UNAVAILABLE");
  expect(
    (
      await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: sent.orderId },
      })
    ).status,
  ).toBe("dispatched");
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
it("tracks order concerns before shipment without stock effects, with protected resolution and replay", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 4 }],
    }),
  );
  await owner.membership.updateMany({
    where: { storeId: store, userId: seller.id },
    data: { active: true },
  });
  const report = op(
    { type: "order.report", orderId, reason: "Livrer uniquement mardi matin" },
    1,
  );
  const before = await owner.stockMovement.count({ where: { storeId: store } });
  const accepted = await ops.submit(manager, report);
  expect(accepted.status).toBe("accepted");
  expect(await ops.submit(manager, report)).toEqual(accepted);
  const detail = await reports.order(manager, org, store, orderId);
  expect(detail.order).toMatchObject({ status: "requested", version: 2 });
  expect(detail.problem).toMatchObject({
    active: true,
    message: "Livrer uniquement mardi matin",
  });
  expect(
    (await reports.alert(admin, org, store, detail.problem!.id)).orderId,
  ).toBe(orderId);
  const page = await reports.orders(
    admin,
    {
      scope: "group",
      organizationId: org,
      from: "2026-09-01",
      to: "2026-09-30",
    },
    undefined,
    "issues",
  );
  expect(page.items.map((i) => i.id)).toContain(orderId);
  expect(
    (
      await ops.submit(
        manager,
        op(
          { type: "order.resolve", orderId, reason: "Je le ferme moi-même" },
          2,
        ),
      )
    ).code,
  ).toBe("FORBIDDEN");
  expect(
    (
      await ops.submit(
        seller,
        op({ type: "order.report", orderId, reason: "Autre problème" }, 2),
      )
    ).code,
  ).toBe("FORBIDDEN");
  expect(
    (
      await ops.submit(
        manager,
        op({ type: "order.report", orderId, reason: "Une seconde fois" }, 2),
      )
    ).code,
  ).toBe("ISSUE_EXISTS");
  expect(
    (
      await ops.submit(
        admin,
        op(
          {
            type: "order.resolve",
            orderId,
            reason: "Livraison mardi confirmée",
          },
          2,
        ),
      )
    ).status,
  ).toBe("accepted");
  const resolved = await reports.order(admin, org, store, orderId);
  expect(resolved.problem?.active).toBe(false);
  expect(resolved.history.map((h) => h.action)).toEqual([
    "order.create",
    "order.report",
    "order.resolve",
  ]);
  expect(await owner.stockMovement.count({ where: { storeId: store } })).toBe(
    before,
  );
  expect(
    (
      await ops.submit(
        manager,
        op(
          {
            type: "order.cancel",
            orderId,
            reason: "Finalement plus nécessaire",
          },
          3,
        ),
      )
    ).status,
  ).toBe("accepted");
  const notices = await owner.notification.findMany({
    where: { storeId: store, targetId: orderId },
  });
  expect(notices.some((n) => n.userId === admin.id)).toBe(true);
  expect(notices.some((n) => n.userId === manager.id)).toBe(true);
  expect(notices.some((n) => n.userId === seller.id)).toBe(false);
});
it("keeps order problems visible even when the first alert page is full", async () => {
  const orderId = randomUUID();
  await ops.submit(
    manager,
    op({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity: 1 }],
    }),
  );
  await ops.submit(
    manager,
    op({ type: "order.report", orderId, reason: "Demande à vérifier" }, 1),
  );
  await owner.alert.updateMany({
    where: { storeId: store, key: `order:${orderId}` },
    data: { createdAt: new Date("2020-01-01") },
  });
  await owner.alert.createMany({
    data: Array.from({ length: 201 }, () => ({
      organizationId: org,
      storeId: store,
      kind: "test",
      key: randomUUID(),
      message: "Isolated alert fixture",
    })),
  });
  const snapshot = await workspace.snapshot(manager, org, store);
  expect(snapshot.alerts.some((a) => a.key === `order:${orderId}`)).toBe(false);
  expect(
    snapshot.orders.find((order) => order.id === orderId)?.openIssues,
  ).toBe(1);
});
