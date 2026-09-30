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
import { TicketService } from "../src/modules/operations/http/ticket.controller";

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
  tickets = new TicketService(db);
const person = (admin = false): Actor => ({
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
  name: admin ? "Admin" : "Person",
  platformAdmin: admin,
});
const admin = person(true),
  manager = person(),
  grossiste = person(),
  otherGrossiste = person();
const product = randomUUID(),
  second = randomUUID();
let org = "",
  store = "",
  depotOrg = "",
  depot = "",
  otherDepotOrg = "",
  otherDepot = "";

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
  envelope(org, store, command, version, supplier);
const accepted = async (actor: Actor, operation: Operation) => {
  const result = await service.submit(actor, operation);
  expect(result, JSON.stringify(result)).toMatchObject({ status: "accepted" });
  return result;
};
const setPrice = (
  level: "wholesale" | "store_supply",
  productId: string,
  priceMillimes: string,
) =>
  pricing.set(admin, {
    operationId: randomUUID(),
    level,
    productId,
    priceMillimes,
  });
const order = (id: string) =>
  owner.replenishmentOrder.findUniqueOrThrow({ where: { id } });
const delivery = (id: string) =>
  owner.delivery.findUniqueOrThrow({ where: { id } });
const codeOf = (qr: string) => qr.split(".")[2]!;

async function shipment(
  quantity: number,
  options: { supplier?: boolean; batch?: string } = {},
) {
  const orderId = randomUUID(),
    deliveryId = randomUUID(),
    batch = options.batch ?? "SHIP";
  await accepted(
    manager,
    retail({
      type: "order.create",
      orderId,
      lines: [{ productId: product, quantity }],
    }),
  );
  let supplier: string | undefined;
  if (options.supplier) {
    await accepted(
      admin,
      retail({ type: "order.assign", orderId, supplierStoreId: depot }, 1),
    );
    supplier = depot;
  }
  const actor = options.supplier ? grossiste : admin;
  await accepted(
    actor,
    retail(
      { type: "order.prepare", orderId },
      (await order(orderId)).version,
      supplier,
    ),
  );
  await accepted(
    actor,
    retail(
      {
        type: "delivery.dispatch",
        orderId,
        deliveryId,
        lines: [
          {
            productId: product,
            quantity,
            allocations: options.supplier
              ? [
                  {
                    lotId: lotIdentity(depot, product, "D1", "2031-06-30"),
                    quantity,
                  },
                ]
              : [{ batch, expiry: "2031-06-30", quantity }],
          },
        ],
      },
      (await order(orderId)).version,
      supplier,
    ),
  );
  return { orderId, deliveryId, batch };
}
const receive = (
  deliveryId: string,
  version: number,
  extra: Record<string, unknown> = {},
  batch = "SHIP",
  quantity?: number,
) =>
  retail(
    {
      type: "delivery.receive",
      deliveryId,
      note: "",
      lines: [
        {
          productId: product,
          batch,
          expiry: "2031-06-30",
          quantity: quantity ?? 5,
        },
      ],
      ...extra,
    } as Command,
    version,
  );

beforeAll(async () => {
  for (const a of [admin, manager, grossiste, otherGrossiste])
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
  await owner.organization.create({ data: { id: org, name: "Groupe détail" } });
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
    } else {
      otherDepotOrg = id;
      otherDepot = storeId;
    }
  }
  for (const id of [product, second])
    await owner.product.create({
      data: { id, reference: id, name: `Produit ${id.slice(0, 4)}` },
    });
  // Opening stock of the grossiste's depot.
  await accepted(
    grossiste,
    envelope(depotOrg, depot, {
      type: "stock.receive",
      reason: "opening",
      lines: [
        {
          productId: product,
          batch: "D1",
          expiry: "2031-06-30",
          quantity: 100,
        },
      ],
    }),
  );
}, 60000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});

describe("order prices", () => {
  it("fixes the supply price on each line and never rewrites it", async () => {
    await setPrice("store_supply", product, "40000");
    await setPrice("wholesale", product, "28000");
    const first = randomUUID();
    await accepted(
      manager,
      retail({
        type: "order.create",
        orderId: first,
        lines: [{ productId: product, quantity: 3 }],
      }),
    );
    expect((await order(first)).lines).toEqual([
      { productId: product, quantity: 3, unitPriceMillimes: "40000" },
    ]);
    // A price change applies to later orders only.
    await setPrice("store_supply", product, "45000");
    await setPrice("store_supply", second, "10000");
    const next = randomUUID();
    await accepted(
      manager,
      retail({
        type: "order.create",
        orderId: next,
        lines: [{ productId: product, quantity: 1 }],
      }),
    );
    expect((await order(next)).lines).toEqual([
      { productId: product, quantity: 1, unitPriceMillimes: "45000" },
    ]);
    expect((await order(first)).lines).toEqual([
      { productId: product, quantity: 3, unitPriceMillimes: "40000" },
    ]);
    // An amendment keeps existing prices and prices the new product today.
    await accepted(
      admin,
      retail(
        {
          type: "order.amend",
          orderId: first,
          reason: "Ajout d’un produit",
          lines: [
            { productId: product, quantity: 4 },
            { productId: second, quantity: 2 },
          ],
        },
        (await order(first)).version,
      ),
    );
    expect((await order(first)).lines).toEqual([
      { productId: product, quantity: 4, unitPriceMillimes: "40000" },
      { productId: second, quantity: 2, unitPriceMillimes: "10000" },
    ]);
    // A grossiste's own order is priced at wholesale, never at the store price.
    const depotOrder = randomUUID();
    await accepted(
      grossiste,
      envelope(depotOrg, depot, {
        type: "order.create",
        orderId: depotOrder,
        lines: [{ productId: product, quantity: 10 }],
      }),
    );
    expect((await order(depotOrder)).lines).toEqual([
      { productId: product, quantity: 10, unitPriceMillimes: "28000" },
    ]);
  });
});

describe("delivery tickets", () => {
  it("numbers each shipment and carries its lots and price", async () => {
    const a = await shipment(5),
      b = await shipment(5);
    const [first, second_] = [
      await delivery(a.deliveryId),
      await delivery(b.deliveryId),
    ];
    expect(first.ticketNumber).toMatch(/^BL-\d{4}-\d{6}$/);
    expect(second_.ticketNumber).not.toBe(first.ticketNumber);
    expect(first.lines).toEqual([
      {
        productId: product,
        quantity: 5,
        unitPriceMillimes: "45000",
        allocations: [{ batch: "SHIP", expiry: "2031-06-30", quantity: 5 }],
      },
    ]);
    const ticket = await tickets.ticket(admin, a.deliveryId, {});
    expect(ticket).toMatchObject({
      number: first.ticketNumber,
      storeName: "Pharmacie",
      totalMillimes: 225000n,
    });
    expect(ticket.qr).toMatch(
      new RegExp(`^BB1\\.${a.deliveryId}\\.[A-Za-z0-9_-]{22}$`),
    );
  });

  it("shows the QR to the shipper alone", async () => {
    const plain = await shipment(2);
    await expect(tickets.ticket(manager, plain.deliveryId, {})).rejects.toThrow(
      "expéditeur",
    );
    await expect(
      tickets.ticket(grossiste, plain.deliveryId, {
        organizationId: depotOrg,
        supplierStoreId: depot,
      }),
    ).rejects.toThrow("introuvable");
    const shipped = await shipment(2, { supplier: true });
    const own = await tickets.ticket(grossiste, shipped.deliveryId, {
      organizationId: depotOrg,
      supplierStoreId: depot,
    });
    expect(own.supplierName).toBe("Dépôt Nord");
    expect(own.lines[0]!.allocations).toEqual([
      { batch: "D1", expiry: "2031-06-30", quantity: 2 },
    ]);
    await expect(
      tickets.ticket(otherGrossiste, shipped.deliveryId, {
        organizationId: otherDepotOrg,
        supplierStoreId: otherDepot,
      }),
    ).rejects.toThrow("introuvable");
    await expect(
      tickets.ticket(otherGrossiste, shipped.deliveryId, {
        organizationId: depotOrg,
        supplierStoreId: depot,
      }),
    ).rejects.toThrow("expéditeur");
  });

  it("adds stock only on a valid scan, and renews a lost QR", async () => {
    const { deliveryId } = await shipment(5);
    const code = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    // A wrong code proves nothing and records nothing.
    const wrong = await service.submit(
      manager,
      receive(deliveryId, 1, { ticketCode: "A".repeat(22) }),
    );
    expect(wrong.code).toBe("TICKET_INVALID");
    expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(
      0,
    );
    // The receiver cannot renew it; the shipper can, which voids the old QR.
    expect(
      (
        await service.submit(
          manager,
          retail({ type: "delivery.reissue", deliveryId }, 1),
        )
      ).code,
    ).toBe("FORBIDDEN");
    await accepted(admin, retail({ type: "delivery.reissue", deliveryId }, 1));
    expect(
      (
        await service.submit(
          manager,
          receive(deliveryId, 2, { ticketCode: code }),
        )
      ).code,
    ).toBe("TICKET_INVALID");
    const fresh = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    expect(fresh).not.toBe(code);
    await accepted(manager, receive(deliveryId, 2, { ticketCode: fresh }));
    const receipt = await owner.deliveryReceipt.findFirstOrThrow({
      where: { deliveryId },
    });
    expect(receipt).toMatchObject({ scanned: true, manualReason: null });
    const lotId = lotIdentity(store, product, "SHIP", "2031-06-30");
    expect(
      (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
        .sellable,
    ).toBeGreaterThanOrEqual(5);
    // A closed ticket cannot be renewed.
    expect(
      (
        await service.submit(
          admin,
          retail({ type: "delivery.reissue", deliveryId }, 3),
        )
      ).code,
    ).toBe("DELIVERY_CLOSED");
  });

  it("flags a reception without scan, and can require a reason", async () => {
    const { deliveryId } = await shipment(5);
    await accepted(manager, receive(deliveryId, 1));
    const receipt = await owner.deliveryReceipt.findFirstOrThrow({
      where: { deliveryId },
    });
    expect(receipt.scanned).toBe(false);
    const flagged = await owner.notification.findFirst({
      where: { storeId: store, title: "Réception sans scan" },
    });
    expect(flagged?.body).toContain((await delivery(deliveryId)).ticketNumber);
    process.env.TICKET_SCAN_REQUIRED = "true";
    try {
      const strict = await shipment(5);
      expect(
        (await service.submit(manager, receive(strict.deliveryId, 1))).code,
      ).toBe("TICKET_SCAN_REQUIRED");
      await accepted(
        manager,
        receive(strict.deliveryId, 1, { manualReason: "Étiquette abîmée" }),
      );
      expect(
        (
          await owner.deliveryReceipt.findFirstOrThrow({
            where: { deliveryId: strict.deliveryId },
          })
        ).manualReason,
      ).toBe("Étiquette abîmée");
    } finally {
      delete process.env.TICKET_SCAN_REQUIRED;
    }
  });

  it("reports a lot the ticket does not list", async () => {
    const { deliveryId } = await shipment(5);
    await accepted(manager, receive(deliveryId, 1, {}, "OTHER"));
    const receipt = await owner.deliveryReceipt.findFirstOrThrow({
      where: { deliveryId },
    });
    expect(
      (receipt.differences as { outsideTicket: unknown[] }).outsideTicket,
    ).toEqual([{ productId: product, batch: "OTHER", expiry: "2031-06-30" }]);
  });

  it("lets the assigned grossiste renew its own QR only", async () => {
    const { deliveryId } = await shipment(2, { supplier: true });
    const version = (await delivery(deliveryId)).version;
    expect(
      (
        await service.submit(
          otherGrossiste,
          retail({ type: "delivery.reissue", deliveryId }, version, otherDepot),
        )
      ).code,
    ).toBe("FORBIDDEN");
    await accepted(
      grossiste,
      retail({ type: "delivery.reissue", deliveryId }, version, depot),
    );
    expect((await delivery(deliveryId)).ticketVersion).toBe(2);
  });
});
