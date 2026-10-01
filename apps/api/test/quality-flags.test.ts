import { ticketCode } from "../src/shared/domain/delivery-ticket";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { assertTestDatabases } from "./test-database.cjs";
import { Database } from "../src/shared/infrastructure/database";
import {
  PrismaUnitOfWork,
  lotIdentity,
} from "../src/modules/operations/infrastructure/prisma-ledger";
import { OperationsService } from "../src/modules/operations/application/operations.service";
import {
  Actor,
  Command,
  Operation,
} from "../src/modules/operations/domain/contracts";
import { PricingService } from "../src/modules/pricing/pricing.service";
import { QualityService } from "../src/modules/operations/http/quality.controller";

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
  pricing = new PricingService(db),
  quality = new QualityService(db);
const person = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin" : "Person",
  platformAdmin: admin,
});
const admin = person(true),
  manager = person(),
  seller = person(),
  stranger = person();
const product = randomUUID();
let org = "",
  store = "",
  otherOrg = "";

const op = (command: Command, version?: number): Operation => ({
  operationId: randomUUID(),
  organizationId: org,
  storeId: store,
  payloadVersion: 2,
  command,
  expectedVersion: version,
});
const accepted = async (actor: Actor, operation: Operation) => {
  const result = await service.submit(actor, operation);
  expect(result, JSON.stringify(result)).toMatchObject({ status: "accepted" });
  return result;
};
const lot = (batch: string, expiry: string) =>
  lotIdentity(store, product, batch, expiry);
const row = (id: string) =>
  owner.inventoryLot.findUniqueOrThrow({ where: { id } });
const flagRow = (id: string) =>
  owner.qualityFlag.findUniqueOrThrow({ where: { id } });
async function receive(batch: string, expiry: string, quantity: number) {
  // Tests seed several lots; the opening declaration is otherwise one-time.
  await owner.store.update({
    where: { id: store },
    data: { openingClosedAt: null },
  });
  await accepted(
    manager,
    op({
      type: "stock.receive",
      reason: "opening",
      lines: [{ productId: product, batch, expiry, quantity }],
    }),
  );
  return lot(batch, expiry);
}
const flag = async (
  lotId: string,
  quantity: number,
  kind: "damaged" | "expired",
  note?: string,
  flagId = randomUUID(),
) => ({
  ...(await service.submit(
    manager,
    op(
      { type: "quality.flag", flagId, lotId, quantity, kind, note },
      (await row(lotId)).version,
    ),
  )),
  flagId,
});
const resolve = (
  actor: Actor,
  flagId: string,
  decision: "confirm" | "reject",
  note = "Inspection faite",
) =>
  service.submit(
    actor,
    op({ type: "quality.resolve", flagId, decision, note }, 1),
  );

beforeAll(async () => {
  for (const a of [admin, manager, seller, stranger])
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
  store = randomUUID();
  otherOrg = randomUUID();
  await owner.organization.create({ data: { id: org, name: "Groupe" } });
  await owner.organization.create({ data: { id: otherOrg, name: "Autre" } });
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: manager.id },
  });
  await owner.organizationMembership.create({
    data: { organizationId: otherOrg, userId: stranger.id },
  });
  await owner.store.create({
    data: {
      id: store,
      organizationId: org,
      name: "Pharmacie",
      nature: "pharmacie",
      address: "Adresse",
      city: "Tunis",
    },
  });
  await owner.membership.create({
    data: {
      organizationId: org,
      storeId: store,
      userId: seller.id,
      permissions: ["sell"],
    },
  });
  await owner.product.create({
    data: { id: product, reference: product, name: "Sérum" },
  });
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("flagging damaged or expired goods", () => {
  it("holds the units out of sale at once and records the lot as flagged", async () => {
    const id = await receive("D1", "2031-06-30", 10);
    const result = await flag(id, 3, "damaged", "Flacon fissuré");
    expect(result).toMatchObject({ status: "accepted" });
    expect(await row(id)).toMatchObject({ sellable: 7, damaged: 3 });
    expect(await flagRow(result.flagId)).toMatchObject({
      status: "open",
      batch: "D1",
      quantity: 3,
      kind: "damaged",
      note: "Flacon fissuré",
      flaggedBy: manager.id,
    });
    // BioBalance is told; the flag is not a silent stock edit.
    expect(
      await owner.notification.count({
        where: { storeId: store, title: "Produit non conforme à inspecter" },
      }),
    ).toBeGreaterThan(0);
  });

  it("checks what is flagged", async () => {
    const id = await receive("D2", "2031-06-30", 5);
    expect((await flag(id, 2, "damaged")).code).toBe("MISSING_NOTE");
    expect((await flag(id, 6, "damaged", "Écrasés")).code).toBe(
      "INSUFFICIENT_STOCK",
    );
    expect((await flag(id, 1, "expired")).code).toBe("NOT_EXPIRED");
    expect(await row(id)).toMatchObject({ sellable: 5, damaged: 0 });
    // A seller cannot flag.
    expect(
      (
        await service.submit(
          seller,
          op(
            {
              type: "quality.flag",
              flagId: randomUUID(),
              lotId: id,
              quantity: 1,
              kind: "damaged",
              note: "Abîmé",
            },
            (await row(id)).version,
          ),
        )
      ).code,
    ).toBe("FORBIDDEN");
    // A retry of the same flag changes nothing twice.
    const operation = op(
      {
        type: "quality.flag",
        flagId: randomUUID(),
        lotId: id,
        quantity: 2,
        kind: "damaged",
        note: "Écrasés",
      },
      (await row(id)).version,
    );
    await accepted(manager, operation);
    await accepted(manager, operation);
    expect(await row(id)).toMatchObject({ sellable: 3, damaged: 2 });
  });

  it("lets BioBalance confirm a loss, valued at the price on the delivery", async () => {
    await pricing.set(admin, {
      operationId: randomUUID(),
      level: "store_supply",
      productId: product,
      priceMillimes: "40000",
    });
    const orderId = randomUUID(),
      deliveryId = randomUUID();
    await accepted(
      manager,
      op({
        type: "order.create",
        orderId,
        lines: [{ productId: product, quantity: 6 }],
      }),
    );
    await accepted(admin, op({ type: "order.prepare", orderId }, 1));
    await accepted(
      admin,
      op(
        {
          type: "delivery.dispatch",
          orderId,
          deliveryId,
          lines: [
            {
              productId: product,
              quantity: 6,
              allocations: [{ batch: "Q1", expiry: "2031-06-30", quantity: 6 }],
            },
          ],
        },
        2,
      ),
    );
    await accepted(
      manager,
      op(
        {
          type: "delivery.receive",
          deliveryId,
          note: "",
          ticketCode: ticketCode(deliveryId, 1),
          lines: [],
        },
        1,
      ),
    );
    const id = lot("Q1", "2031-06-30");
    const { flagId } = await flag(id, 2, "damaged", "Humidité");
    const ticket = (
      await owner.delivery.findUniqueOrThrow({ where: { id: deliveryId } })
    ).ticketNumber;
    expect(await flagRow(flagId)).toMatchObject({
      sourceDeliveryId: deliveryId,
      sourceTicket: ticket,
    });
    // The responsable, who flagged it, cannot decide.
    expect((await resolve(manager, flagId, "confirm")).code).toBe("FORBIDDEN");
    await accepted(
      admin,
      op(
        {
          type: "quality.resolve",
          flagId,
          decision: "confirm",
          note: "Retiré du stock",
        },
        1,
      ),
    );
    expect(await row(id)).toMatchObject({ sellable: 4, damaged: 0 });
    // A later price change never alters the recorded loss.
    await pricing.set(admin, {
      operationId: randomUUID(),
      level: "store_supply",
      productId: product,
      priceMillimes: "99000",
    });
    expect(await flagRow(flagId)).toMatchObject({
      status: "confirmed",
      valueMillimes: 80000n,
      decidedBy: admin.id,
      decisionNote: "Retiré du stock",
      version: 2,
    });
    // A decision is final, in the service and in the database.
    expect(
      (
        await service.submit(
          admin,
          op(
            {
              type: "quality.resolve",
              flagId,
              decision: "reject",
              note: "Erreur",
            },
            2,
          ),
        )
      ).code,
    ).toBe("FLAG_DECIDED");
    await expect(
      owner.$executeRaw`UPDATE "QualityFlag" SET "decisionNote"='Changé' WHERE id=${flagId}::uuid`,
    ).rejects.toThrow();
    await expect(
      owner.$executeRaw`DELETE FROM "QualityFlag" WHERE id=${flagId}::uuid`,
    ).rejects.toThrow();
  });

  it("puts a wrongly flagged product back on sale, but never an expired one", async () => {
    const id = await receive("R1", "2031-06-30", 8);
    const { flagId } = await flag(id, 4, "damaged", "Étiquette abîmée");
    expect(await row(id)).toMatchObject({ sellable: 4, damaged: 4 });
    await accepted(
      admin,
      op(
        {
          type: "quality.resolve",
          flagId,
          decision: "reject",
          note: "Produit conforme",
        },
        1,
      ),
    );
    expect(await row(id)).toMatchObject({ sellable: 8, damaged: 0 });
    expect((await flagRow(flagId)).status).toBe("rejected");
    const old = await receive("E1", "2024-01-31", 5);
    const expired = await flag(old, 5, "expired");
    expect(expired).toMatchObject({ status: "accepted" });
    expect(await row(old)).toMatchObject({ sellable: 0, damaged: 5 });
    expect((await resolve(admin, expired.flagId, "reject")).code).toBe(
      "EXPIRED_NOT_RELEASABLE",
    );
    await accepted(
      admin,
      op(
        {
          type: "quality.resolve",
          flagId: expired.flagId,
          decision: "confirm",
          note: "Détruits",
        },
        1,
      ),
    );
    expect(await row(old)).toMatchObject({ sellable: 0, damaged: 0 });
  });

  it("keeps a legacy damage report as a flag BioBalance can decide", async () => {
    const id = await receive("L1", "2031-06-30", 4);
    const operation = op(
      {
        type: "stock.damage",
        lotId: id,
        quantity: 1,
        reason: "Choc pendant le transport",
      },
      (await row(id)).version,
    );
    await accepted(manager, operation);
    expect(await flagRow(operation.operationId)).toMatchObject({
      kind: "damaged",
      status: "open",
      note: "Choc pendant le transport",
    });
  });
});

describe("who sees the flags", () => {
  it("shows them to the store's manager and to BioBalance, nobody else", async () => {
    const mine = await quality.list(manager, {
      organizationId: org,
      storeId: store,
      status: "all",
    });
    expect(mine.items.length).toBeGreaterThan(3);
    expect(mine.items.every((f) => f.storeId === store)).toBe(true);
    const group = await quality.list(manager, { organizationId: org });
    expect(group.items.every((f) => f.status === "open")).toBe(true);
    const confirmed = mine.items.find(
      (f) => f.status === "confirmed" && f.sourceTicket,
    );
    expect(confirmed?.valueMillimes).toBe(80000n);
    expect(confirmed?.deciderName).toBe("Admin");
    expect(confirmed?.sourceTicket).toMatch(/^BL-/);
    const network = await quality.list(admin, { status: "all" });
    expect(network.items.length).toBeGreaterThanOrEqual(mine.items.length);
    await expect(quality.list(manager, {})).rejects.toThrow("BioBalance");
    await expect(
      quality.list(seller, { organizationId: org, storeId: store }),
    ).rejects.toThrow();
    await expect(
      quality.list(stranger, { organizationId: org, storeId: store }),
    ).rejects.toThrow();
    await expect(
      quality.list(stranger, { organizationId: org }),
    ).rejects.toThrow();
    expect(otherOrg).toBeTruthy();
  });
});
