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
import { IdentityService } from "../src/modules/identity/identity.service";
import { PasswordHasher } from "../src/modules/identity/password-hasher";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { GroupService } from "../src/modules/tenancy/group.service";
import { WholesaleService } from "../src/modules/wholesale/wholesale.service";
import { ticketCode } from "../src/shared/domain/delivery-ticket";

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
class Passwords extends PasswordHasher {
  override async hash(p: string) {
    return `test:${p}`;
  }
}
const db = new Database(),
  service = new OperationsService(new PrismaUnitOfWork(db)),
  workspace = new WorkspaceService(db),
  groups = new GroupService(db, workspace),
  wholesale = new WholesaleService(db),
  identity = new IdentityService(db, new Passwords());
const account = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin" : "Person",
  platformAdmin: admin,
});
const admin = account(true),
  manager = account(),
  vendeur = account();
const product = randomUUID(),
  second = randomUUID();
let retailOrg = "",
  retailStore = "",
  depotOrg = "",
  depot = "",
  grossiste: Actor = account(),
  otherDepotOrg = "",
  otherDepot = "",
  otherGrossiste: Actor = account();

const envelope = (
  organizationId: string,
  storeId: string,
  command: Command,
  expectedVersion?: number,
  supplierStoreId?: string,
): Operation => ({
  operationId: randomUUID(),
  organizationId,
  storeId,
  payloadVersion: 2,
  command,
  expectedVersion,
  supplierStoreId,
});
const retail = (command: Command, version?: number, supplier?: string) =>
  envelope(retailOrg, retailStore, command, version, supplier);
const atDepot = (command: Command, version?: number) =>
  envelope(depotOrg, depot, command, version);
const lot = (store: string, p: string, batch: string) =>
  lotIdentity(store, p, batch, "2031-06-30");
const stock = async (store: string, id: string) =>
  (await owner.inventoryLot.findUniqueOrThrow({ where: { id } })).sellable;
const accepted = async (actor: Actor, operation: Operation) => {
  const result = await service.submit(actor, operation);
  expect(result, JSON.stringify(result)).toMatchObject({
    status: "accepted",
  });
  return result;
};
async function createWholesaler(name: string, email: string) {
  const created = await wholesale.create(admin, {
    operationId: randomUUID(),
    name,
    email,
    address: "1 rue du Dépôt",
    city: "Sfax",
  });
  const invitation = await owner.accessToken.findFirstOrThrow({
    where: { email },
  });
  const job = await owner.job.findFirstOrThrow({
    where: { key: `invite:${invitation.id}` },
  });
  const token = (job.payload as { token: string }).token;
  await identity.activate(token, name, "correct horse battery", randomUUID());
  const user = await owner.user.findUniqueOrThrow({ where: { email } });
  return { created, actor: { ...account(), id: user.id, email } as Actor };
}

beforeAll(async () => {
  for (const a of [admin, manager, vendeur])
    await owner.user.create({
      data: {
        id: a.id,
        email: a.email,
        name: a.name,
        passwordHash: "test-only-not-a-login",
        platformAdmin: a.platformAdmin,
      },
    });
  retailOrg = randomUUID();
  retailStore = randomUUID();
  await owner.organization.create({
    data: { id: retailOrg, name: "Groupe détail" },
  });
  await owner.organizationMembership.create({
    data: { organizationId: retailOrg, userId: manager.id },
  });
  await owner.store.create({
    data: {
      id: retailStore,
      organizationId: retailOrg,
      name: "Pharmacie test",
      nature: "pharmacie",
      address: "Adresse",
      city: "Tunis",
    },
  });
  await owner.membership.create({
    data: {
      organizationId: retailOrg,
      storeId: retailStore,
      userId: vendeur.id,
      permissions: ["sell"],
    },
  });
  for (const id of [product, second])
    await owner.product.create({
      data: { id, reference: id, name: `Produit ${id.slice(0, 4)}` },
    });
  const first = await createWholesaler(
    "Grossiste Nord",
    `${randomUUID()}@example.test`,
  );
  grossiste = first.actor;
  depotOrg = first.created.id;
  depot = first.created.storeId;
  const other = await createWholesaler(
    "Grossiste Sud",
    `${randomUUID()}@example.test`,
  );
  otherGrossiste = other.actor;
  otherDepotOrg = other.created.id;
  otherDepot = other.created.storeId;
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("grossiste foundation", () => {
  it("creates a depot and invites its single responsible account", async () => {
    const organization = await owner.organization.findUniqueOrThrow({
      where: { id: depotOrg },
    });
    expect(organization.kind).toBe("wholesale");
    const listed = (await wholesale.list(admin)).find((w) => w.id === depotOrg);
    expect(listed).toMatchObject({
      storeId: depot,
      activated: true,
      contactName: "Grossiste Nord",
    });
    await expect(wholesale.list(manager)).rejects.toThrow("BioBalance");
    const before = await owner.organization.count({
      where: { kind: "wholesale" },
    });
    const operationId = randomUUID();
    const input = {
      operationId,
      name: "Grossiste Est",
      email: `${randomUUID()}@example.test`,
      address: "Zone industrielle",
      city: "Sousse",
    };
    const once = await wholesale.create(admin, input);
    const twice = await wholesale.create(admin, input);
    expect(twice.id).toBe(once.id);
    expect(once.activated).toBe(false);
    expect(
      await owner.organization.count({ where: { kind: "wholesale" } }),
    ).toBe(before + 1);
    await expect(
      wholesale.create(admin, { ...input, name: "Autre nom" }),
    ).rejects.toThrow("déjà utilisé");
    await expect(wholesale.create(manager, input)).rejects.toThrow();
    // A second form for the same pending address is refused, not duplicated.
    await expect(
      wholesale.create(admin, { ...input, operationId: randomUUID() }),
    ).rejects.toThrow("invitation");
  });

  it("gives a depot no sales, no team and no extra store", async () => {
    const stores = await workspace.stores(grossiste);
    expect(stores).toHaveLength(1);
    expect(stores[0]).toMatchObject({
      id: depot,
      organizationKind: "wholesale",
      permissions: ["manage", "receive"],
    });
    const sale = {
      type: "sale.create",
      saleId: randomUUID(),
      occurredAt: new Date().toISOString(),
      lines: [
        {
          id: randomUUID(),
          productId: product,
          quantity: 1,
          unitPriceMillimes: "1000",
          allocations: [{ lotId: randomUUID(), quantity: 1 }],
        },
      ],
    } as Command;
    expect((await service.submit(grossiste, atDepot(sale))).code).toBe(
      "WHOLESALE_NO_SALES",
    );
    await expect(
      workspace.createStore(admin, {
        organizationId: depotOrg,
        name: "Second dépôt",
        nature: "pharmacie",
        address: "Adresse",
        city: "Tunis",
      }),
    ).rejects.toThrow("dépôt");
    await expect(
      identity.invite(admin, {
        email: `${randomUUID()}@example.test`,
        kind: "salesperson",
        organizationId: depotOrg,
        storeIds: [depot],
        permissions: ["sell"],
      }),
    ).rejects.toThrow("équipe");
    await expect(
      groups.member(admin, depotOrg, vendeur.id, {
        active: true,
        role: "salesperson",
        storeIds: [depot],
      }),
    ).rejects.toThrow("équipe");
    // Neither the retail manager nor a foreign grossiste can open this depot.
    await expect(
      service.submit(
        manager,
        atDepot({ type: "order.prepare", orderId: randomUUID() }),
      ),
    ).resolves.toMatchObject({ status: "rejected" });
  });

  it("lets the grossiste declare the depot's opening stock once", async () => {
    await accepted(
      grossiste,
      atDepot({
        type: "stock.receive",
        reason: "opening",
        lines: [
          {
            productId: product,
            batch: "A",
            expiry: "2031-06-30",
            quantity: 40,
          },
        ],
      }),
    );
    // The declaration is one-time: neither the grossiste nor BioBalance can add more.
    for (const who of [grossiste, admin])
      expect(
        (
          await service.submit(
            who,
            atDepot({
              type: "stock.receive",
              reason: "opening",
              lines: [
                {
                  productId: second,
                  batch: "S",
                  expiry: "2031-06-30",
                  quantity: 5,
                },
              ],
            }),
          )
        ).code,
      ).toBe("OPENING_CLOSED");
    expect(await stock(depot, lot(depot, product, "A"))).toBe(40);
  });
});

describe("grossiste orders from BioBalance", () => {
  it("ships without lots and receives by lot", async () => {
    const orderId = randomUUID(),
      deliveryId = randomUUID();
    await accepted(
      grossiste,
      atDepot({
        type: "order.create",
        orderId,
        lines: [{ productId: product, quantity: 20 }],
      }),
    );
    await accepted(admin, atDepot({ type: "order.prepare", orderId }, 1));
    const withLots = await service.submit(
      admin,
      atDepot(
        {
          type: "delivery.dispatch",
          orderId,
          deliveryId,
          lines: [
            {
              productId: product,
              quantity: 20,
              allocations: [{ lotId: randomUUID(), quantity: 20 }],
            },
          ],
        },
        2,
      ),
    );
    // BioBalance declares batch and expiry; it names no depot lot.
    expect(withLots.code).toBe("ALLOCATION_MISMATCH");
    const dispatchLines = (allocations: unknown[] | undefined) => [
      { productId: product, quantity: 20, allocations },
    ];
    for (const [allocations, code] of [
      [undefined, "ALLOCATION_MISMATCH"],
      [[{ batch: "B", expiry: "2020-01-31", quantity: 20 }], "LOT_EXPIRED"],
    ] as const)
      expect(
        (
          await service.submit(
            admin,
            atDepot(
              {
                type: "delivery.dispatch",
                orderId,
                deliveryId,
                lines: dispatchLines([...(allocations ?? [])]).map((l) =>
                  allocations ? l : { productId: l.productId, quantity: 20 },
                ),
              } as Command,
              2,
            ),
          )
        ).code,
      ).toBe(code);
    await accepted(
      admin,
      atDepot(
        {
          type: "delivery.dispatch",
          orderId,
          deliveryId,
          lines: dispatchLines([
            { batch: "B", expiry: "2031-06-30", quantity: 20 },
          ]),
        } as Command,
        2,
      ),
    );
    expect(await stock(depot, lot(depot, product, "A"))).toBe(40);
    await accepted(
      grossiste,
      atDepot(
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
    expect(await stock(depot, lot(depot, product, "B"))).toBe(20);
  });
});

describe("store orders handled by a grossiste", () => {
  let orderId = "";
  const dispatch = (deliveryId: string, quantity: number, batch = "A") => ({
    type: "delivery.dispatch" as const,
    orderId,
    deliveryId,
    lines: [
      {
        productId: product,
        quantity,
        allocations: [{ lotId: lot(depot, product, batch), quantity }],
      },
    ],
  });
  const version = async () =>
    (
      await owner.replenishmentOrder.findUniqueOrThrow({
        where: { id: orderId },
      })
    ).version;

  it("is assigned by BioBalance only, before any delivery", async () => {
    orderId = randomUUID();
    await accepted(
      manager,
      retail({
        type: "order.create",
        orderId,
        lines: [{ productId: product, quantity: 12 }],
      }),
    );
    const assign = (supplierStoreId: string | null) =>
      retail({ type: "order.assign", orderId, supplierStoreId }, undefined);
    const op = async (supplier: string | null, actor = admin) =>
      service.submit(actor, {
        ...assign(supplier),
        expectedVersion: await version(),
      });
    expect((await op(depot, manager)).code).toBe("FORBIDDEN");
    expect((await op(retailStore)).code).toBe("SUPPLIER_UNAVAILABLE");
    expect((await op(depot)).status).toBe("accepted");
    expect(
      (
        await owner.replenishmentOrder.findUniqueOrThrow({
          where: { id: orderId },
        })
      ).supplierStoreId,
    ).toBe(depot);
    // BioBalance may take the order back, and hand it out again.
    expect((await op(null)).status).toBe("accepted");
    expect((await op(depot)).status).toBe("accepted");
    // A depot's own order is never handed to another depot.
    const ownOrder = randomUUID();
    await accepted(
      grossiste,
      atDepot({
        type: "order.create",
        orderId: ownOrder,
        lines: [{ productId: product, quantity: 1 }],
      }),
    );
    const refused = await service.submit(admin, {
      ...atDepot(
        {
          type: "order.assign",
          orderId: ownOrder,
          supplierStoreId: otherDepot,
        },
        1,
      ),
    });
    expect(refused.code).toBe("WHOLESALE_ORDER");
  });

  it("is prepared and shipped from lots by the assigned grossiste alone", async () => {
    const deliveryId = randomUUID();
    const before = await workspace.snapshot(grossiste, depotOrg, depot);
    // BioBalance must take the order back before handling it.
    expect(
      (
        await service.submit(
          admin,
          retail({ type: "order.prepare", orderId }, await version()),
        )
      ).code,
    ).toBe("FORBIDDEN");
    // Another grossiste, and the responsable, cannot act for this depot.
    expect(
      (
        await service.submit(
          otherGrossiste,
          retail(
            { type: "order.prepare", orderId },
            await version(),
            otherDepot,
          ),
        )
      ).code,
    ).toBe("FORBIDDEN");
    await expect(
      service.submit(
        manager,
        retail({ type: "order.prepare", orderId }, await version(), depot),
      ),
    ).resolves.toMatchObject({ status: "rejected" });
    await accepted(
      grossiste,
      retail({ type: "order.prepare", orderId }, await version(), depot),
    );
    expect(
      (
        await service.submit(
          grossiste,
          retail(dispatch(deliveryId, 12), await version(), depot),
        )
      ).status,
    ).toBe("accepted");
    // Nothing else may be done through a supplier session.
    expect(
      (
        await service.submit(
          grossiste,
          retail(
            { type: "order.cancel", orderId, reason: "Annulation" },
            await version(),
            depot,
          ),
        )
      ).code,
    ).toBe("FORBIDDEN");
    // The depot's phone learns the new stock from its own synchronization feed.
    const delta = await workspace.snapshot(
      grossiste,
      depotOrg,
      depot,
      { cursor: before.cursor, catalogRevision: before.catalogRevision },
      3,
    );
    expect(delta.mode).toBe("delta");
    expect(
      delta.lots.find((l) => l.id === lot(depot, product, "A"))?.sellable,
    ).toBe(28);
    const delivery = await owner.delivery.findUniqueOrThrow({
      where: { id: deliveryId },
    });
    expect(delivery.sourceStoreId).toBe(depot);
    expect(delivery.lines).toEqual([
      {
        productId: product,
        quantity: 12,
        unitPriceMillimes: null,
        allocations: [
          {
            lotId: lot(depot, product, "A"),
            batch: "A",
            expiry: "2031-06-30",
            quantity: 12,
          },
        ],
      },
    ]);
    // The depot's stock left at dispatch; the store has received nothing yet.
    expect(await stock(depot, lot(depot, product, "A"))).toBe(28);
    expect(
      await owner.inventoryLot.count({ where: { storeId: retailStore } }),
    ).toBe(0);
    const moves = await owner.stockMovement.findMany({
      where: { storeId: depot, reason: "delivery.dispatch" },
    });
    expect(moves.map((m) => m.quantity)).toEqual([-12]);
    expect(
      await owner.change.count({
        where: {
          storeId: depot,
          entity: "delivery.dispatch",
          entityId: deliveryId,
        },
      }),
    ).toBe(1);
  });

  it("refuses shipments that the depot cannot cover", async () => {
    const second = randomUUID();
    const replacement = randomUUID();
    orderId = replacement;
    await accepted(
      manager,
      retail({
        type: "order.create",
        orderId,
        lines: [{ productId: product, quantity: 500 }],
      }),
    );
    await accepted(admin, {
      ...retail({ type: "order.assign", orderId, supplierStoreId: depot }, 1),
    });
    await accepted(
      grossiste,
      retail({ type: "order.prepare", orderId }, await version(), depot),
    );
    const over = await service.submit(
      grossiste,
      retail(dispatch(second, 500), await version(), depot),
    );
    expect(over.code).toBe("INSUFFICIENT_STOCK");
    const mismatch = await service.submit(grossiste, {
      ...retail(
        {
          type: "delivery.dispatch",
          orderId,
          deliveryId: randomUUID(),
          lines: [{ productId: product, quantity: 3 }],
        },
        await version(),
        depot,
      ),
    });
    expect(mismatch.code).toBe("ALLOCATION_MISMATCH");
    expect(await stock(depot, lot(depot, product, "A"))).toBe(28);
  });

  it("credits the grossiste only when the store confirms receipt", async () => {
    const delivery = await owner.delivery.findFirstOrThrow({
      where: { sourceStoreId: depot, status: "dispatched" },
    });
    await workspace.configureProduct(admin, depotOrg, depot, product, {
      priceMillimes: "1000",
      threshold: 5,
      pointsPerUnit: 3,
    });
    await expect(
      workspace.configureProduct(grossiste, depotOrg, depot, product, {
        priceMillimes: "1000",
        threshold: 5,
        pointsPerUnit: 99,
        expectedVersion: 1,
      }),
    ).rejects.toThrow("BioBalance");
    expect(await owner.pointsEntry.count({ where: { storeId: depot } })).toBe(
      0,
    );
    await accepted(
      manager,
      retail(
        {
          type: "delivery.receive",
          deliveryId: delivery.id,
          note: "Deux unités manquantes",
          manualReason: "QR illisible",
          lines: [
            {
              productId: product,
              batch: "A",
              expiry: "2031-06-30",
              quantity: 10,
            },
          ],
        },
        delivery.version,
      ),
    );
    // Without the QR nothing moves and no points are earned until BioBalance validates.
    expect(
      await owner.inventoryLot.count({ where: { storeId: retailStore } }),
    ).toBe(0);
    expect(await owner.pointsEntry.count({ where: { storeId: depot } })).toBe(
      0,
    );
    await accepted(
      admin,
      retail(
        {
          type: "delivery.validate",
          deliveryId: delivery.id,
          note: "Deux unités manquantes confirmées",
          shortfall: "returned",
          lines: [
            {
              productId: product,
              batch: "A",
              expiry: "2031-06-30",
              quantity: 10,
            },
          ],
        },
        (
          await owner.delivery.findUniqueOrThrow({
            where: { id: delivery.id },
          })
        ).version,
      ),
    );
    // Store stock rises by what was physically received.
    expect(await stock(retailStore, lot(retailStore, product, "A"))).toBe(10);
    // Points follow the units confirmed: 10 × 3, separate from any store points.
    const account = await owner.pointsAccount.findFirstOrThrow({
      where: { storeId: depot, userId: grossiste.id },
    });
    expect(account.balance).toBe(30n);
    expect(
      await owner.pointsEntry.count({ where: { storeId: retailStore } }),
    ).toBe(0);
  });

  it("returns goods to the depot's lots, but not goods that were lost", async () => {
    const returnedOrder = randomUUID(),
      returned = randomUUID(),
      lostOrder = randomUUID(),
      lost = randomUUID();
    const run = async (id: string, delivery: string, resolution: string) => {
      orderId = id;
      await accepted(
        manager,
        retail({
          type: "order.create",
          orderId: id,
          lines: [{ productId: product, quantity: 4 }],
        }),
      );
      await accepted(
        admin,
        retail(
          { type: "order.assign", orderId: id, supplierStoreId: depot },
          1,
        ),
      );
      await accepted(
        grossiste,
        retail({ type: "order.prepare", orderId: id }, await version(), depot),
      );
      await accepted(
        grossiste,
        retail(dispatch(delivery, 4), await version(), depot),
      );
      const before = await stock(depot, lot(depot, product, "A"));
      await accepted(
        manager,
        retail(
          {
            type: "delivery.report",
            deliveryId: delivery,
            reason: "Colis absent",
          },
          1,
        ),
      );
      const current = await owner.delivery.findUniqueOrThrow({
        where: { id: delivery },
      });
      // Another grossiste cannot settle it; this depot's grossiste can.
      expect(
        (
          await service.submit(
            otherGrossiste,
            retail(
              {
                type: "delivery.resolve",
                deliveryId: delivery,
                decision: resolution as "lost",
                reason: "Réglé",
              },
              current.version,
              otherDepot,
            ),
          )
        ).code,
      ).toBe("FORBIDDEN");
      const resolve = (actor: Actor, supplier?: string) =>
        retail(
          {
            type: "delivery.resolve",
            deliveryId: delivery,
            decision: resolution as "lost",
            reason: "Réglé",
          },
          current.version,
          supplier,
        );
      // Lost or returned is decided by BioBalance alone, never by the shipper.
      expect(
        (await service.submit(grossiste, resolve(grossiste, depot))).code,
      ).toBe("FORBIDDEN");
      await accepted(admin, resolve(admin));
      return { before, after: await stock(depot, lot(depot, product, "A")) };
    };
    const back = await run(returnedOrder, returned, "returned");
    expect(back.after).toBe(back.before + 4);
    const gone = await run(lostOrder, lost, "lost");
    expect(gone.after).toBe(gone.before);
  }, 30000);

  it("shows a grossiste only the orders assigned to its own depot", async () => {
    const mine = await wholesale.orders(grossiste, {
      organizationId: depotOrg,
      storeId: depot,
      phase: "all",
    });
    expect(mine.items.length).toBeGreaterThan(0);
    expect(
      mine.items.every(
        (o) => o.supplierStoreId === depot && o.storeName === "Pharmacie test",
      ),
    ).toBe(true);
    const theirs = await wholesale.orders(otherGrossiste, {
      organizationId: otherDepotOrg,
      storeId: otherDepot,
      phase: "all",
    });
    expect(theirs.items).toHaveLength(0);
    await expect(
      wholesale.orders(otherGrossiste, {
        organizationId: depotOrg,
        storeId: depot,
        phase: "all",
      }),
    ).rejects.toThrow("inaccessible");
    await expect(
      wholesale.orders(manager, {
        organizationId: depotOrg,
        storeId: depot,
        phase: "all",
      }),
    ).rejects.toThrow("inaccessible");
    const detail = await wholesale.order(grossiste, mine.items[0]!.id, {
      organizationId: depotOrg,
      storeId: depot,
    });
    expect(detail.order.groupName).toBe("Groupe détail");
    await expect(
      wholesale.order(otherGrossiste, mine.items[0]!.id, {
        organizationId: otherDepotOrg,
        storeId: otherDepot,
      }),
    ).rejects.toThrow("introuvable");
  });
});

describe("grossiste rewards", () => {
  it("are run by BioBalance and kept apart from the stores' points", async () => {
    const values = {
      title: "Cadeau grossiste",
      description: "",
      cost: 10,
      quantity: 1,
      active: true,
    };
    await expect(
      workspace.reward(grossiste, depotOrg, depot, values),
    ).rejects.toThrow("BioBalance");
    const reward = await workspace.reward(admin, depotOrg, depot, values);
    const claimId = randomUUID();
    await accepted(
      grossiste,
      atDepot({ type: "reward.request", claimId, rewardId: reward.id }),
    );
    expect(
      (
        await service.submit(
          grossiste,
          atDepot(
            { type: "reward.resolve", claimId, decision: "fulfilled" },
            1,
          ),
        )
      ).code,
    ).toBe("FORBIDDEN");
    await accepted(
      admin,
      atDepot({ type: "reward.resolve", claimId, decision: "fulfilled" }, 1),
    );
    const points = await owner.pointsAccount.findFirstOrThrow({
      where: { storeId: depot, userId: grossiste.id },
    });
    expect(points.balance).toBe(20n);
    expect(
      await owner.pointsAccount.count({ where: { storeId: retailStore } }),
    ).toBe(0);
  });
});

describe("a suspended grossiste", () => {
  it("cannot ship, is still answerable for goods on the road, and never blocks a store's confirmation", async () => {
    const orderId = randomUUID(),
      deliveryId = randomUUID();
    const version = async () =>
      (
        await owner.replenishmentOrder.findUniqueOrThrow({
          where: { id: orderId },
        })
      ).version;
    await accepted(
      manager,
      retail({
        type: "order.create",
        orderId,
        lines: [{ productId: product, quantity: 2 }],
      }),
    );
    await accepted(
      admin,
      retail({ type: "order.assign", orderId, supplierStoreId: depot }, 1),
    );
    await accepted(
      grossiste,
      retail({ type: "order.prepare", orderId }, await version(), depot),
    );
    await accepted(
      grossiste,
      retail(
        {
          type: "delivery.dispatch",
          orderId,
          deliveryId,
          lines: [
            {
              productId: product,
              quantity: 2,
              allocations: [{ lotId: lot(depot, product, "A"), quantity: 2 }],
            },
          ],
        },
        await version(),
        depot,
      ),
    );
    const organization = await owner.organization.findUniqueOrThrow({
      where: { id: depotOrg },
    });
    await groups.lifecycle(admin, depotOrg, undefined, {
      operationId: randomUUID(),
      expectedVersion: organization.version,
      status: "suspended",
      reason: "Contrôle",
    });
    // A delivery on the road, and assigned orders, keep the depot from closing.
    expect(
      (await groups.lifecycleImpact(admin, depotOrg)).deliveries,
    ).toBeGreaterThan(0);
    expect(
      (
        await service.submit(
          grossiste,
          retail({ type: "order.prepare", orderId }, await version(), depot),
        )
      ).code,
    ).toBe("STORE_ACCESS_REVOKED");
    const points = async () =>
      (
        await owner.pointsAccount.findFirstOrThrow({
          where: { storeId: depot, userId: grossiste.id },
        })
      ).balance;
    const before = await points();
    await accepted(
      manager,
      retail(
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
    expect((await points()) - before).toBe(6n);
    const current = await owner.organization.findUniqueOrThrow({
      where: { id: depotOrg },
    });
    await groups.lifecycle(admin, depotOrg, undefined, {
      operationId: randomUUID(),
      expectedVersion: current.version,
      status: "active",
      reason: "Contrôle terminé",
    });
  });
});
