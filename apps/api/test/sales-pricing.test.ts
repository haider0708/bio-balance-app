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
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";

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
  manager = person(),
  seller = person();
const priced = randomUUID(),
  legacy = randomUUID(),
  late = randomUUID();
let org = "",
  store = "";
const day = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * day);

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
async function stock(productId: string, batch: string) {
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
      lines: [{ productId, batch, expiry: "2031-06-30", quantity: 100 }],
    }),
  );
  return lotIdentity(store, productId, batch, "2031-06-30");
}
async function sell(
  productId: string,
  lotId: string,
  at: Date,
  unitPriceMillimes: string,
  quantity = 2,
  by: Actor = manager,
) {
  const saleId = randomUUID();
  await accepted(
    by,
    op({
      type: "sale.create",
      saleId,
      occurredAt: at.toISOString(),
      lines: [
        {
          id: randomUUID(),
          productId,
          quantity,
          unitPriceMillimes,
          allocations: [{ lotId, quantity }],
        },
      ],
    }),
  );
  return owner.sale.findUniqueOrThrow({ where: { id: saleId } });
}
type Line = {
  id: string;
  listPriceMillimes?: string | null;
  unitPriceMillimes: string;
  pointsPerUnit: number;
};
const first = (sale: { lines: unknown }) => (sale.lines as Line[])[0]!;
const retailVersion = (productId: string, priceMillimes: bigint, at: Date) =>
  owner.priceVersion.create({
    data: {
      id: randomUUID(),
      level: "retail",
      productId,
      organizationId: org,
      storeId: store,
      priceMillimes,
      createdAt: at,
    },
  });
const rateVersion = (productId: string, pointsPerUnit: number, at: Date) =>
  owner.pointsRateVersion.create({
    data: {
      id: randomUUID(),
      organizationId: org,
      storeId: store,
      productId,
      pointsPerUnit,
      createdAt: at,
    },
  });

beforeAll(async () => {
  for (const a of [admin, manager, seller])
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
  await owner.organization.create({ data: { id: org, name: "Groupe" } });
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: manager.id },
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
  for (const id of [priced, legacy, late])
    await owner.product.create({
      data: { id, reference: id, name: `Produit ${id.slice(0, 4)}` },
    });
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("the price list beside the price charged", () => {
  it("keeps the retail price of the sale date, and never rewrites it", async () => {
    const lotId = await stock(priced, "P1");
    const config = { priceMillimes: "59900", threshold: 5, pointsPerUnit: 0 };
    const created = await workspace.configureProduct(
      manager,
      org,
      store,
      priced,
      config,
    );
    // The seller gives a discount: both prices are recorded.
    const sale = await sell(priced, lotId, new Date(), "50000");
    expect(first(sale)).toMatchObject({
      unitPriceMillimes: "50000",
      listPriceMillimes: "59900",
    });
    await workspace.configureProduct(manager, org, store, priced, {
      ...config,
      priceMillimes: "62900",
      expectedVersion: created.version,
    });
    // A correction keeps the original list price.
    await accepted(
      manager,
      op(
        {
          type: "sale.correct",
          saleId: sale.id,
          occurredAt: sale.occurredAt.toISOString(),
          reason: "Quantité corrigée",
          lines: [
            {
              id: first(sale).id,
              productId: priced,
              quantity: 3,
              unitPriceMillimes: "50000",
              allocations: [{ lotId, quantity: 3 }],
            },
          ],
        },
        sale.version,
      ),
    );
    const corrected = await owner.sale.findUniqueOrThrow({
      where: { id: sale.id },
    });
    expect(first(corrected).listPriceMillimes).toBe("59900");
    // A later sale sees the new price.
    expect(
      first(await sell(priced, lotId, new Date(), "62900")).listPriceMillimes,
    ).toBe("62900");
  });

  it("uses the price in force on the sale date for a sale that syncs late", async () => {
    const lotId = await stock(legacy, "L1");
    await retailVersion(legacy, 40000n, ago(10));
    await retailVersion(legacy, 45000n, ago(3));
    expect(
      first(await sell(legacy, lotId, ago(5), "40000")).listPriceMillimes,
    ).toBe("40000");
    expect(
      first(await sell(legacy, lotId, ago(1), "45000")).listPriceMillimes,
    ).toBe("45000");
    // Before any price was recorded, the list price is unknown, not invented.
    expect(
      first(await sell(legacy, lotId, ago(20), "30000")).listPriceMillimes,
    ).toBeNull();
  });
});

describe("a seller cannot set the price", () => {
  it("sells at the store price, with a note, and nothing else", async () => {
    const product = randomUUID(),
      unpriced = randomUUID();
    for (const id of [product, unpriced])
      await owner.product.create({
        data: { id, reference: id, name: `Produit ${id.slice(0, 4)}` },
      });
    const lotId = await stock(product, "FIX");
    const created = await workspace.configureProduct(
      manager,
      org,
      store,
      product,
      { priceMillimes: "20000", threshold: 5, pointsPerUnit: 0 },
    );
    const line = (price: string, note?: string) => ({
      id: randomUUID(),
      productId: product,
      quantity: 1,
      unitPriceMillimes: price,
      ...(note ? { note } : {}),
      allocations: [{ lotId, quantity: 1 }],
    });
    const create = (l: ReturnType<typeof line>) =>
      service.submit(
        seller,
        op({
          type: "sale.create",
          saleId: randomUUID(),
          occurredAt: new Date().toISOString(),
          lines: [l],
        }),
      );
    // Neither a discount nor a surcharge is accepted from a seller.
    expect((await create(line("15000"))).code).toBe("PRICE_FIXED");
    expect((await create(line("25000"))).code).toBe("PRICE_FIXED");
    expect(await create(line("20000", "Client fidèle"))).toMatchObject({
      status: "accepted",
    });
    // The responsable may still charge something else.
    expect(
      first(await sell(product, lotId, new Date(), "15000")),
    ).toMatchObject({
      unitPriceMillimes: "15000",
    });
    // No price set, no sale by a seller.
    const other = await stock(unpriced, "NOP");
    const refused = await service.submit(
      seller,
      op({
        type: "sale.create",
        saleId: randomUUID(),
        occurredAt: new Date().toISOString(),
        lines: [
          {
            id: randomUUID(),
            productId: unpriced,
            quantity: 1,
            unitPriceMillimes: "1000",
            allocations: [{ lotId: other, quantity: 1 }],
          },
        ],
      }),
    );
    expect(refused.code).toBe("PRICE_NOT_SET");
    expect(created.version).toBeGreaterThan(0);
  });
});

describe("points follow the rate of the sale date", () => {
  it("uses the rate in force on the day, for a sale within 3 days", async () => {
    const lotId = await stock(legacy, "L2");
    await rateVersion(legacy, 5, ago(10));
    await rateVersion(legacy, 8, ago(2));
    const earlier = await sell(legacy, lotId, ago(2.5), "40000", 2);
    expect(first(earlier).pointsPerUnit).toBe(5);
    expect(earlier.earnedPoints).toBe(10n);
    const later = await sell(legacy, lotId, ago(1), "40000", 2);
    expect(first(later).pointsPerUnit).toBe(8);
    expect(later.earnedPoints).toBe(16n);
  });

  it("never rewrites earlier sales when the rate changes", async () => {
    const lotId = await stock(priced, "P2");
    const before0 = await owner.storeProduct.findUniqueOrThrow({
      where: { storeId_productId: { storeId: store, productId: priced } },
    });
    await workspace.configureProduct(admin, org, store, priced, {
      priceMillimes: "62900",
      threshold: 5,
      pointsPerUnit: 4,
      expectedVersion: before0.version,
    });
    const before = await sell(priced, lotId, new Date(), "62900", 1);
    expect(before.earnedPoints).toBe(4n);
    const current = await owner.storeProduct.findUniqueOrThrow({
      where: { storeId_productId: { storeId: store, productId: priced } },
    });
    await workspace.configureProduct(admin, org, store, priced, {
      priceMillimes: "62900",
      threshold: 5,
      pointsPerUnit: 9,
      reason: "Nouveau barème",
      expectedVersion: current.version,
    });
    expect(
      (await owner.sale.findUniqueOrThrow({ where: { id: before.id } }))
        .earnedPoints,
    ).toBe(4n);
    expect(
      (await sell(priced, lotId, new Date(), "62900", 1)).earnedPoints,
    ).toBe(9n);
  });

  it("rates a sale older than 3 days as of three days before it arrived", async () => {
    const lotId = await stock(late, "T1");
    await rateVersion(late, 2, ago(40));
    await rateVersion(late, 6, ago(1));
    await owner.storeProduct.create({
      data: {
        organizationId: org,
        storeId: store,
        productId: late,
        priceMillimes: 1000n,
        pointsPerUnit: 6,
        pointsConfigured: true,
      },
    });
    const old = await sell(late, lotId, ago(30), "1000", 1);
    // A phone clock set back cannot buy the rate of 30 days ago.
    expect(first(old).pointsPerUnit).toBe(2);
  });

  it("never goes further back than 3 days, and uses the current rate when none was ever recorded", async () => {
    const lotId = await stock(legacy, "L3");
    const before = await sell(legacy, lotId, ago(12), "40000", 1);
    // 12 days ago there was no rate, but the sale is rated as of 3 days ago.
    expect(first(before).pointsPerUnit).toBe(5);
    const fresh = randomUUID();
    await owner.product.create({
      data: { id: fresh, reference: fresh, name: "Produit sans barème" },
    });
    const freshLot = await stock(fresh, "N1");
    await owner.storeProduct.create({
      data: {
        organizationId: org,
        storeId: store,
        productId: fresh,
        priceMillimes: 1000n,
        pointsPerUnit: 7,
        pointsConfigured: true,
      },
    });
    expect(
      first(await sell(fresh, freshLot, ago(2), "1000", 1)).pointsPerUnit,
    ).toBe(7);
  });
});
