import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { assertTestDatabases } from "./test-database.cjs";
import { Database } from "../src/shared/infrastructure/database";
import { PrismaUnitOfWork } from "../src/modules/operations/infrastructure/prisma-ledger";
import { OperationsService } from "../src/modules/operations/application/operations.service";
import {
  Actor,
  Command,
  Operation,
  operationSchema,
} from "../src/modules/operations/domain/contracts";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { OperationsController } from "../src/modules/operations/http/operations.controller";

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
  service = new OperationsService(new PrismaUnitOfWork(db)),
  workspace = new WorkspaceService(db);
const person = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin" : "Person",
  platformAdmin: admin,
});
const admin = person(true),
  manager = person();
const product = randomUUID();
let org = "";
const stores = { stocked: "", empty: "" };

const op = (storeId: string, command: Command): Operation => ({
  operationId: randomUUID(),
  organizationId: org,
  storeId,
  payloadVersion: 2,
  command,
});
const opening = (batch: string): Command => ({
  type: "stock.receive",
  reason: "opening",
  lines: [{ productId: product, batch, expiry: "2031-06-30", quantity: 10 }],
});

beforeAll(async () => {
  for (const a of [admin, manager])
    await owner.user.create({
      data: {
        id: a.id,
        email: a.email,
        name: a.name,
        passwordHash: "test-only-not-a-login",
        platformAdmin: a.platformAdmin,
      },
    });
  org = randomUUID();
  await owner.organization.create({ data: { id: org, name: "Groupe" } });
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: manager.id },
  });
  for (const key of ["stocked", "empty"] as const) {
    stores[key] = randomUUID();
    await owner.store.create({
      data: {
        id: stores[key],
        organizationId: org,
        name: key,
        nature: "pharmacie",
        address: "Adresse",
        city: "Tunis",
      },
    });
  }
  await owner.product.create({
    data: { id: product, reference: product, name: "Produit" },
  });
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("the opening stock is declared once", () => {
  it("lets a store declare its stock a single time, whoever enters it", async () => {
    expect(
      (await service.submit(manager, op(stores.stocked, opening("A")))).status,
    ).toBe("accepted");
    for (const who of [manager, admin])
      expect(
        (await service.submit(who, op(stores.stocked, opening("B")))).code,
      ).toBe("OPENING_CLOSED");
    expect(
      await owner.inventoryLot.count({ where: { storeId: stores.stocked } }),
    ).toBe(1);
  });

  it("lets a store say it has no stock, and take it back until stock exists", async () => {
    const store = await owner.store.findUniqueOrThrow({
      where: { id: stores.empty },
    });
    await workspace.onboarding(manager, org, stores.empty, {
      noOpeningStock: true,
      expectedVersion: store.version,
    });
    expect(
      (await service.submit(manager, op(stores.empty, opening("C")))).code,
    ).toBe("OPENING_CLOSED");
    // Until stock exists, the choice can be taken back and stock entered once.
    await workspace.onboarding(manager, org, stores.empty, {
      noOpeningStock: false,
      expectedVersion: (
        await owner.store.findUniqueOrThrow({ where: { id: stores.empty } })
      ).version,
    });
    expect(
      (await service.submit(manager, op(stores.empty, opening("C")))).status,
    ).toBe("accepted");
    // Once a lot exists, "no stock" cannot be ticked back, nor the stock re-declared.
    await expect(
      workspace.onboarding(manager, org, stores.empty, {
        noOpeningStock: true,
        expectedVersion: (
          await owner.store.findUniqueOrThrow({ where: { id: stores.empty } })
        ).version,
      }),
    ).resolves.toBeDefined();
    expect(
      (await service.submit(manager, op(stores.empty, opening("D")))).code,
    ).toBe("OPENING_CLOSED");
    await expect(
      workspace.onboarding(manager, org, stores.empty, {
        noOpeningStock: false,
        expectedVersion: (
          await owner.store.findUniqueOrThrow({ where: { id: stores.empty } })
        ).version,
      }),
    ).rejects.toMatchObject({ code: "OPENING_CLOSED" });
  });

  it("no longer knows a command that changes a count", () => {
    const base = {
      operationId: randomUUID(),
      organizationId: org,
      storeId: stores.stocked,
      payloadVersion: 2,
    };
    expect(
      operationSchema.safeParse({
        ...base,
        command: {
          type: "stock.adjust",
          lotId: randomUUID(),
          quantity: 1,
          reason: "Comptage",
        },
      }).success,
    ).toBe(false);
    expect(
      operationSchema.safeParse({
        ...base,
        command: { ...opening("D"), reason: "receipt" },
      }).success,
    ).toBe(false);
  });

  it("rejects an operation it no longer knows without blocking the others", async () => {
    const controller = new OperationsController(service);
    const known = op(stores.stocked, {
      type: "order.create",
      orderId: randomUUID(),
      lines: [{ productId: product, quantity: 2 }],
    });
    const stale = {
      operationId: randomUUID(),
      organizationId: org,
      storeId: stores.stocked,
      payloadVersion: 2,
      command: {
        type: "stock.adjust",
        lotId: randomUUID(),
        quantity: 1,
        reason: "Comptage",
      },
    };
    const { results } = (await controller.push({ actor: manager } as never, {
      operations: [stale, known],
    })) as {
      results: { operationId: string; status: string; code?: string }[];
    };
    expect(results[0]).toMatchObject({
      operationId: stale.operationId,
      status: "rejected",
      code: "UNSUPPORTED_OPERATION",
    });
    expect(results[1]).toMatchObject({
      operationId: known.operationId,
      status: "accepted",
    });
  });
});
