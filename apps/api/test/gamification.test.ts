import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { assertTestDatabases } from "./test-database.cjs";
import { Database } from "../src/shared/infrastructure/database";
import { Actor } from "../src/modules/operations/domain/contracts";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { GamificationService } from "../src/modules/tenancy/gamification.service";

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
  gamification = new GamificationService(db);
const person = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin" : "Responsable",
  platformAdmin: admin,
});
const admin = person(true),
  manager = person();
const product = randomUUID();
let templateId = "";
let org = "",
  storeA = "",
  storeB = "",
  depotOrg = "",
  depot = "";
const config = (storeId: string) =>
  owner.storeProduct.findUnique({
    where: { storeId_productId: { storeId, productId: product } },
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
  depotOrg = randomUUID();
  await owner.organization.create({ data: { id: org, name: "Groupe" } });
  await owner.organization.create({
    data: { id: depotOrg, name: "Grossiste", kind: "wholesale" },
  });
  await owner.organizationMembership.create({
    data: { organizationId: org, userId: manager.id },
  });
  for (const [id, organizationId] of [
    [(storeA = randomUUID()), org],
    [(storeB = randomUUID()), org],
    [(depot = randomUUID()), depotOrg],
  ] as const)
    await owner.store.create({
      data: {
        id,
        organizationId,
        name: id.slice(0, 6),
        address: "Adresse",
        city: "Tunis",
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

describe("default points and rewards, with exceptions per place", () => {
  it("applies a default rate to every store, not to the depots", async () => {
    await expect(
      gamification.setPointsDefault(manager, {
        audience: "retail",
        productId: product,
        pointsPerUnit: 5,
      }),
    ).rejects.toThrow();
    await gamification.setPointsDefault(admin, {
      audience: "retail",
      productId: product,
      pointsPerUnit: 5,
    });
    expect(await config(storeA)).toMatchObject({
      pointsPerUnit: 5,
      pointsException: false,
    });
    expect((await config(storeB))?.pointsPerUnit).toBe(5);
    expect(await config(depot)).toBeNull();
    // Sales read the rate history of the place: it was recorded there.
    expect(
      await owner.pointsRateVersion.count({
        where: { storeId: storeA, productId: product },
      }),
    ).toBe(1);
  });

  it("keeps a store's own rate when the default changes, until it is reset", async () => {
    await gamification.setStorePoints(admin, org, storeA, {
      productId: product,
      pointsPerUnit: 9,
    });
    await gamification.setPointsDefault(admin, {
      audience: "retail",
      productId: product,
      pointsPerUnit: 7,
    });
    expect(await config(storeA)).toMatchObject({
      pointsPerUnit: 9,
      pointsException: true,
    });
    expect((await config(storeB))?.pointsPerUnit).toBe(7);
    const list = await gamification.storePoints(admin, org, storeA);
    expect(list.items.find((i) => i.productId === product)).toMatchObject({
      pointsPerUnit: 9,
      defaultPointsPerUnit: 7,
      exception: true,
    });
    await gamification.setStorePoints(admin, org, storeA, {
      productId: product,
      reset: true,
    });
    expect(await config(storeA)).toMatchObject({
      pointsPerUnit: 7,
      pointsException: false,
    });
  });

  it("offers a default reward everywhere, kept in step, and not editable per store", async () => {
    const template = await gamification.saveRewardTemplate(admin, {
      audience: "retail",
      title: "Coffret",
      description: "Coffret soins",
      cost: 300,
      quantity: 1,
      active: true,
    });
    templateId = template.id;
    const copies = () =>
      owner.reward.findMany({
        where: {
          templateId: template.id,
          storeId: { in: [storeA, storeB, depot] },
        },
      });
    expect((await copies()).map((c) => c.storeId).sort()).toEqual(
      [storeA, storeB].sort(),
    );
    await gamification.saveRewardTemplate(admin, {
      id: template.id,
      expectedVersion: 1,
      audience: "retail",
      title: "Coffret",
      description: "Coffret soins",
      cost: 250,
      quantity: 1,
      active: true,
    });
    expect((await copies()).every((c) => c.cost === 250)).toBe(true);
    const copy = (await copies()).find((c) => c.storeId === storeA)!;
    await expect(
      workspace.reward(admin, org, storeA, {
        id: copy.id,
        expectedVersion: copy.version,
        title: "Autre",
        description: "",
        cost: 10,
        quantity: 1,
        active: true,
      }),
    ).rejects.toThrow("par défaut");
  });

  it("starts a new store with the defaults", async () => {
    const created = await workspace.createStore(manager, {
      organizationId: org,
      name: "Nouveau",
      nature: "pharmacie",
      address: "Adresse",
      city: "Sousse",
    });
    expect((await config(created.id))?.pointsPerUnit).toBe(7);
    expect(
      await owner.reward.count({
        where: { storeId: created.id, templateId },
      }),
    ).toBe(1);
  });
});
