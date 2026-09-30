import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { assertTestDatabases } from "./test-database.cjs";
import { Database } from "../src/shared/infrastructure/database";
import { Actor } from "../src/modules/operations/domain/contracts";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { CatalogService } from "../src/modules/catalog/catalog.service";
import { PricingService } from "../src/modules/pricing/pricing.service";

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
  pricing = new PricingService(db),
  workspace = new WorkspaceService(db),
  catalog = new CatalogService(db);
const person = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin BioBalance" : "Person",
  platformAdmin: admin,
});
const admin = person(true),
  responsable = person(),
  vendeur = person(),
  grossiste = person(),
  otherGrossiste = person(),
  outsider = person();
const product = randomUUID();
let org = "",
  store = "",
  otherStore = "",
  depotOrg = "",
  depot = "",
  otherDepotOrg = "";

const mine = (view: { items: { productId: string }[] }) =>
  view.items.find((i) => i.productId === product)!;
const set = (
  actor: Actor,
  input: {
    level: "wholesale" | "store_supply";
    organizationId?: string;
    storeId?: string;
    priceMillimes: string;
    reason?: string;
    operationId?: string;
  },
) =>
  pricing.set(actor, {
    operationId: randomUUID(),
    productId: product,
    ...input,
  });

beforeAll(async () => {
  for (const a of [
    admin,
    responsable,
    vendeur,
    grossiste,
    otherGrossiste,
    outsider,
  ])
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
  otherStore = randomUUID();
  await owner.organization.create({ data: { id: org, name: "Groupe détail" } });
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: responsable.id },
  });
  for (const id of [store, otherStore])
    await owner.store.create({
      data: {
        id,
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
      userId: vendeur.id,
      permissions: ["sell"],
    },
  });
  for (const [who, name] of [
    [grossiste, "Nord"],
    [otherGrossiste, "Sud"],
  ] as const) {
    const id = randomUUID(),
      storeId = randomUUID();
    await owner.organization.create({
      data: { id, name: `Grossiste ${name}`, kind: "wholesale" },
    });
    await owner.store.create({
      data: {
        id: storeId,
        organizationId: id,
        name: `Dépôt ${name}`,
        address: "Zone",
        city: "Sfax",
      },
    });
    await owner.organizationMembership.create({
      data: { organizationId: id, userId: who.id },
    });
    if (name === "Nord") {
      depotOrg = id;
      depot = storeId;
    } else otherDepotOrg = id;
  }
  await owner.product.create({
    data: {
      id: product,
      reference: product,
      name: "Sérum",
      referencePriceMillimes: 55000n,
      priceStatus: "verified",
    },
  });
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("price book", () => {
  it("is set by BioBalance alone, with a reason, and never rewritten", async () => {
    await expect(
      set(responsable, { level: "store_supply", priceMillimes: "40000" }),
    ).rejects.toThrow("BioBalance");
    await expect(
      set(grossiste, { level: "wholesale", priceMillimes: "30000" }),
    ).rejects.toThrow("BioBalance");
    const operationId = randomUUID();
    const first = await set(admin, {
      level: "store_supply",
      priceMillimes: "40000",
      reason: "Tarif 2026",
      operationId,
    });
    // A retry of the same form returns the same entry.
    expect(
      (
        await set(admin, {
          level: "store_supply",
          priceMillimes: "40000",
          reason: "Tarif 2026",
          operationId,
        })
      ).id,
    ).toBe(first.id);
    await expect(
      set(admin, {
        level: "store_supply",
        priceMillimes: "41000",
        operationId,
      }),
    ).rejects.toThrow("déjà utilisé");
    await expect(
      set(admin, { level: "store_supply", priceMillimes: "40000" }),
    ).rejects.toThrow("déjà en vigueur");
    await set(admin, { level: "store_supply", priceMillimes: "42000" });
    await set(admin, { level: "wholesale", priceMillimes: "30000" });
    await set(admin, {
      level: "wholesale",
      organizationId: depotOrg,
      priceMillimes: "28000",
      reason: "Remise grossiste Nord",
    });
    await set(admin, {
      level: "store_supply",
      organizationId: org,
      storeId: otherStore,
      priceMillimes: "39000",
    });
    // Scope rules.
    await expect(
      set(admin, { level: "wholesale", storeId: store, priceMillimes: "1" }),
    ).rejects.toThrow();
    await expect(
      set(admin, {
        level: "store_supply",
        organizationId: org,
        priceMillimes: "1",
      }),
    ).rejects.toThrow("magasin");
    await expect(
      set(admin, {
        level: "store_supply",
        organizationId: depotOrg,
        storeId: depot,
        priceMillimes: "1",
      }),
    ).rejects.toThrow("dépôt");
    await expect(
      set(admin, {
        level: "wholesale",
        organizationId: org,
        priceMillimes: "1",
      }),
    ).rejects.toThrow("grossiste");
    // History is append-only at the database level.
    await expect(
      owner.$executeRaw`UPDATE "PriceVersion" SET "priceMillimes"=1 WHERE id=${first.id}::uuid`,
    ).rejects.toThrow();
    await expect(
      owner.$executeRaw`DELETE FROM "PriceVersion" WHERE id=${first.id}::uuid`,
    ).rejects.toThrow();
  });

  it("keeps a specific price above the default, whatever its age", async () => {
    const view = await pricing.current(admin, {
      organizationId: org,
      storeId: otherStore,
    });
    expect(mine(view)).toMatchObject({ supplyMillimes: 39000n });
    // A newer default does not erase an explicit exception.
    await set(admin, { level: "store_supply", priceMillimes: "43000" });
    expect(
      mine(
        await pricing.current(admin, {
          organizationId: org,
          storeId: otherStore,
        }),
      ).supplyMillimes,
    ).toBe(39000n);
    expect(
      mine(
        await pricing.current(admin, { organizationId: org, storeId: store }),
      ).supplyMillimes,
    ).toBe(43000n);
  });

  it("records every retail price and points rate change, and leaves the rest alone", async () => {
    const config = {
      priceMillimes: "59900",
      threshold: 5,
      pointsPerUnit: 0,
      reason: "Prix de lancement",
    };
    const created = await workspace.configureProduct(
      responsable,
      org,
      store,
      product,
      config,
    );
    // Same price again: no new version.
    await workspace.configureProduct(responsable, org, store, product, {
      ...config,
      threshold: 7,
      expectedVersion: created.version,
    });
    const next = await workspace.configureProduct(
      responsable,
      org,
      store,
      product,
      {
        ...config,
        priceMillimes: "62900",
        reason: "Hausse fournisseur",
        expectedVersion: created.version + 1,
      },
    );
    const retail = await owner.priceVersion.findMany({
      where: { storeId: store, level: "retail" },
      orderBy: { createdAt: "asc" },
    });
    expect(retail.map((r) => r.priceMillimes)).toEqual([59900n, 62900n]);
    expect(retail[1]!.createdBy).toBe(responsable.id);
    expect(retail[1]!.reason).toBe("Hausse fournisseur");
    // A responsable never sets points; BioBalance's change is recorded.
    expect(
      await owner.pointsRateVersion.count({ where: { storeId: store } }),
    ).toBe(0);
    await workspace.configureProduct(admin, org, store, product, {
      ...config,
      priceMillimes: "62900",
      pointsPerUnit: 5,
      reason: "Barème 2026",
      expectedVersion: next.version,
    });
    const rates = await owner.pointsRateVersion.findMany({
      where: { storeId: store },
    });
    expect(rates.map((r) => [r.pointsPerUnit, r.reason])).toEqual([
      [5, "Barème 2026"],
    ]);
    await expect(
      owner.$executeRaw`UPDATE "PointsRateVersion" SET "pointsPerUnit"=9`,
    ).rejects.toThrow();
  });
});

describe("who sees which price", () => {
  const scope = () => ({ organizationId: org, storeId: store });
  it("shows BioBalance every level of a store", async () => {
    const row = mine(await pricing.current(admin, scope()));
    expect(row).toMatchObject({
      retailMillimes: 62900n,
      supplyMillimes: 43000n,
      wholesaleMillimes: null,
    });
    const history = await pricing.history(admin, { productId: product });
    expect(new Set(history.items.map((h) => h.level))).toEqual(
      new Set(["wholesale", "store_supply", "retail"]),
    );
    expect(history.items.some((h) => h.author === "Admin BioBalance")).toBe(
      true,
    );
  });

  it("shows a responsable only what he pays and what he charges", async () => {
    const row = mine(await pricing.current(responsable, scope()));
    expect(row).toMatchObject({
      retailMillimes: 62900n,
      supplyMillimes: 43000n,
      wholesaleMillimes: null,
    });
    const history = await pricing.history(responsable, {
      productId: product,
      ...scope(),
    });
    expect(new Set(history.items.map((h) => h.level))).toEqual(
      new Set(["store_supply", "retail"]),
    );
    // Neither another store's exception nor who decided is revealed.
    expect(history.items.some((h) => h.storeId === otherStore)).toBe(false);
    expect(history.items.every((h) => h.author === null)).toBe(true);
    await expect(
      pricing.history(responsable, { productId: product }),
    ).rejects.toThrow();
    await expect(
      pricing.current(responsable, {
        organizationId: depotOrg,
        storeId: depot,
      }),
    ).rejects.toThrow("inaccessible");
  });

  it("shows a seller his store's retail price only", async () => {
    const row = mine(await pricing.current(vendeur, scope()));
    expect(row).toMatchObject({
      retailMillimes: 62900n,
      supplyMillimes: null,
      wholesaleMillimes: null,
    });
    await expect(
      pricing.history(vendeur, { productId: product, ...scope() }),
    ).rejects.toThrow("responsable");
    await expect(pricing.current(outsider, scope())).rejects.toThrow();
  });

  it("shows a grossiste what it pays and what stores pay, never a store's retail price", async () => {
    const view = await pricing.current(grossiste, {
      organizationId: depotOrg,
      storeId: depot,
    });
    expect(mine(view)).toMatchObject({
      wholesaleMillimes: 28000n,
      supplyMillimes: 43000n,
      retailMillimes: null,
    });
    // Another grossiste gets the default wholesale price, not this exception.
    const other = await pricing.current(otherGrossiste, {
      organizationId: otherDepotOrg,
      storeId: (
        await owner.store.findFirstOrThrow({
          where: { organizationId: otherDepotOrg },
        })
      ).id,
    });
    expect(mine(other).wholesaleMillimes).toBe(30000n);
    await expect(
      pricing.current(otherGrossiste, {
        organizationId: depotOrg,
        storeId: depot,
      }),
    ).rejects.toThrow("inaccessible");
    const history = await pricing.history(grossiste, {
      productId: product,
      organizationId: depotOrg,
      storeId: depot,
    });
    // Three default supply prices and two wholesale prices, nothing else.
    expect(history.items.map((h) => h.level).sort()).toEqual([
      "store_supply",
      "store_supply",
      "store_supply",
      "wholesale",
      "wholesale",
    ]);
    expect(history.items.some((h) => h.level === "retail")).toBe(false);
    expect(history.items.some((h) => h.storeId === otherStore)).toBe(false);
  });

  it("keeps supply and wholesale prices out of reach of a plain database session", async () => {
    // Without the pricing use case's access window the application role sees none.
    expect(
      await db.$queryRaw<
        { n: bigint }[]
      >`SELECT COUNT(*)::bigint AS n FROM "PriceVersion" WHERE level<>'retail'`,
    ).toEqual([{ n: 0n }]);
  });

  it("hides the catalogue's reference price from everyone but BioBalance", async () => {
    expect(
      (await catalog.list(admin)).items.find((p) => p.id === product)!
        .referencePriceMillimes,
    ).toBe(55000n);
    const seen = (await catalog.list(responsable)).items.find(
      (p) => p.id === product,
    )!;
    expect(seen.referencePriceMillimes).toBeNull();
    expect(seen.priceStatus).toBe("missing");
    const snapshot = await workspace.snapshot(responsable, org, store);
    expect(
      snapshot.products.every((p) => p.referencePriceMillimes === null),
    ).toBe(true);
  });
});
