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
    // The old QR stops working, but the delivery keeps its version: a receiver
    // whose phone has not synced can still confirm the parcel with the new QR.
    expect(
      (
        await service.submit(
          manager,
          receive(deliveryId, 1, { ticketCode: code }),
        )
      ).code,
    ).toBe("TICKET_INVALID");
    const fresh = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    expect(fresh).not.toBe(code);
    await accepted(manager, receive(deliveryId, 1, { ticketCode: fresh }));
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
          retail({ type: "delivery.reissue", deliveryId }, 2),
        )
      ).code,
    ).toBe("DELIVERY_CLOSED");
  });

  it("books exactly what the ticket lists when the QR is scanned", async () => {
    const { deliveryId } = await shipment(5, { batch: "TRUTH" });
    const code = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    // The receiver cannot change the lots or quantities of a scanned parcel.
    await accepted(
      manager,
      receive(deliveryId, 1, { ticketCode: code }, "OTHER", 9),
    );
    const lot = (batch: string) =>
      owner.inventoryLot.findUnique({
        where: { id: lotIdentity(store, product, batch, "2031-06-30") },
      });
    expect((await lot("TRUTH"))?.sellable).toBe(5);
    expect(await lot("OTHER")).toBeNull();
  });

  it("lets the store report damaged and refused units even with the QR", async () => {
    const { deliveryId } = await shipment(10, { batch: "STATE" });
    const code = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    const flags = [
      { productId: product, batch: "STATE", damaged: 2, refused: 1 },
    ];
    // The report needs an explanation, and cannot exceed the lot.
    expect(
      (
        await service.submit(
          manager,
          receive(deliveryId, 1, { ticketCode: code, flags }),
        )
      ).code,
    ).toBe("NOTE_REQUIRED");
    expect(
      (
        await service.submit(
          manager,
          receive(deliveryId, 1, {
            ticketCode: code,
            note: "Trop",
            flags: [{ ...flags[0], damaged: 10 }],
          }),
        )
      ).code,
    ).toBe("VALIDATION");
    await accepted(
      manager,
      receive(deliveryId, 1, { ticketCode: code, note: "Colis écrasé", flags }),
    );
    const lot = await owner.inventoryLot.findUniqueOrThrow({
      where: { id: lotIdentity(store, product, "STATE", "2031-06-30") },
    });
    // Quantities come from the ticket: 7 sellable, 2 damaged, 1 refused (not stocked).
    expect(lot.sellable).toBe(7);
    expect(lot.damaged).toBe(2);
  });

  it("closes the opening stock once a store has been supplied", async () => {
    const { deliveryId } = await shipment(3, { batch: "SUPPLIED" });
    const code = codeOf((await tickets.ticket(admin, deliveryId, {})).qr);
    await accepted(manager, receive(deliveryId, 1, { ticketCode: code }));
    expect(
      (
        await service.submit(manager, {
          ...retail({
            type: "stock.receive",
            reason: "opening",
            lines: [
              {
                productId: product,
                batch: "LATE",
                expiry: "2031-06-30",
                quantity: 5,
              },
            ],
          }),
        })
      ).code,
    ).toBe("OPENING_CLOSED");
  });

  it("moves nothing without the QR until BioBalance validates", async () => {
    const { deliveryId } = await shipment(5, { batch: "CLAIM" });
    const lot = (batch: string) =>
      owner.inventoryLot.findUnique({
        where: { id: lotIdentity(store, product, batch, "2031-06-30") },
      });
    // Not scanning needs a reason.
    expect(
      (await service.submit(manager, receive(deliveryId, 1, {}, "CLAIM", 7)))
        .code,
    ).toBe("MANUAL_REASON_REQUIRED");
    await accepted(
      manager,
      receive(deliveryId, 1, { manualReason: "Étiquette abîmée" }, "CLAIM", 7),
    );
    const waiting = await delivery(deliveryId);
    expect(waiting.status).toBe("pending_review");
    expect(waiting.claim).toMatchObject({ manualReason: "Étiquette abîmée" });
    expect(await lot("CLAIM")).toBeNull();
    expect(await owner.deliveryReceipt.count({ where: { deliveryId } })).toBe(
      0,
    );
    expect(
      (
        await owner.notification.findFirst({
          where: { storeId: store, title: "Réception à valider" },
        })
      )?.body,
    ).toContain(waiting.ticketNumber);
    // The goods stay on the road for the order until it is validated.
    const row = await order(waiting.orderId);
    expect(row.status).toBe("dispatched");
    // Neither the store nor a second claim can settle it.
    const validate = (lines: number) =>
      retail(
        {
          type: "delivery.validate",
          deliveryId,
          note: "Comparé au bon",
          shortfall: "returned",
          lines: [
            {
              productId: product,
              batch: "CLAIM",
              expiry: "2031-06-30",
              quantity: lines,
            },
          ],
        },
        waiting.version,
      );
    expect((await service.submit(manager, validate(5))).code).toBe("FORBIDDEN");
    expect(
      (await service.submit(manager, receive(deliveryId, waiting.version)))
        .code,
    ).toBe("DELIVERY_ALREADY_RECEIVED");
    await accepted(admin, validate(5));
    expect((await lot("CLAIM"))?.sellable).toBe(5);
    expect((await delivery(deliveryId)).status).toBe("received");
    expect(
      (await owner.deliveryReceipt.findFirstOrThrow({ where: { deliveryId } }))
        .scanned,
    ).toBe(false);
    expect((await service.submit(admin, validate(5))).code).toBeDefined();
  });

  it("settles a correction between the depot and the store", async () => {
    const depotLot = async () =>
      (
        await owner.inventoryLot.findUniqueOrThrow({
          where: { id: lotIdentity(depot, product, "D1", "2031-06-30") },
        })
      ).sellable;
    const claim = async (quantity: number, shipped = 10) => {
      const { deliveryId } = await shipment(shipped, { supplier: true });
      await accepted(
        manager,
        receive(
          deliveryId,
          1,
          { manualReason: "Pas de caméra" },
          "D1",
          quantity,
        ),
      );
      return { deliveryId, version: (await delivery(deliveryId)).version };
    };
    const validate = (
      d: { deliveryId: string; version: number },
      quantity: number,
      shortfall: "returned" | "lost",
    ) =>
      retail(
        {
          type: "delivery.validate",
          deliveryId: d.deliveryId,
          note: "Vérifié avec les deux parties",
          shortfall,
          lines: [
            {
              productId: product,
              batch: "D1",
              expiry: "2031-06-30",
              quantity,
            },
          ],
        },
        d.version,
      );
    const storeLot = async () =>
      (
        await owner.inventoryLot.findUnique({
          where: { id: lotIdentity(store, product, "D1", "2031-06-30") },
        })
      )?.sellable ?? 0;
    // The grossiste lied: 6 reached the store, 4 go back to the depot.
    const short = await claim(6);
    const depotBefore = await depotLot(),
      storeBefore = await storeLot();
    await accepted(admin, validate(short, 6, "returned"));
    expect(await depotLot()).toBe(depotBefore + 4);
    expect(await storeLot()).toBe(storeBefore + 6);
    // The store lied: BioBalance corrects it up to what was shipped, nothing moves back.
    const lied = await claim(2);
    const beforeLie = [await depotLot(), await storeLot()];
    await accepted(admin, validate(lied, 10, "returned"));
    expect(await depotLot()).toBe(beforeLie[0]);
    expect(await storeLot()).toBe(beforeLie[1]! + 10);
    // Written off: the missing units do not return to the depot.
    const lost = await claim(7);
    const beforeLost = await depotLot();
    await accepted(admin, validate(lost, 7, "lost"));
    expect(await depotLot()).toBe(beforeLost);
    // Extra units come out of the depot, and only if it has them.
    const extra = await claim(12);
    const beforeExtra = [await depotLot(), await storeLot()];
    await accepted(admin, validate(extra, 12, "returned"));
    expect(await depotLot()).toBe(beforeExtra[0]! - 2);
    expect(await storeLot()).toBe(beforeExtra[1]! + 12);
    const huge = await claim(5);
    const rejected = await service.submit(
      admin,
      validate(huge, 100_000, "returned"),
    );
    expect(rejected.code).toBe("INSUFFICIENT_STOCK");
    expect((await delivery(huge.deliveryId)).status).toBe("pending_review");
  }, 60000);

  it("sends refused units back to the depot, since they stay with the carrier", async () => {
    const { deliveryId } = await shipment(10, { supplier: true });
    const depotLot = async () =>
      (
        await owner.inventoryLot.findUniqueOrThrow({
          where: { id: lotIdentity(depot, product, "D1", "2031-06-30") },
        })
      ).sellable;
    await accepted(
      manager,
      receive(deliveryId, 1, { manualReason: "Pas de caméra" }, "D1", 8),
    );
    const before = await depotLot();
    await accepted(
      admin,
      retail(
        {
          type: "delivery.validate",
          deliveryId,
          note: "Deux colis refusés",
          shortfall: "returned",
          lines: [
            {
              productId: product,
              batch: "D1",
              expiry: "2031-06-30",
              quantity: 8,
            },
            {
              productId: product,
              batch: "D1",
              expiry: "2031-06-30",
              quantity: 2,
              condition: "refused",
            },
          ],
        },
        (await delivery(deliveryId)).version,
      ),
    );
    expect(await depotLot()).toBe(before + 2);
  }, 30000);

  it("lists a lot the ticket does not carry in the validated receipt", async () => {
    const { deliveryId } = await shipment(5);
    await accepted(
      manager,
      receive(deliveryId, 1, { manualReason: "Colis ouvert" }, "OTHER"),
    );
    await accepted(
      admin,
      retail(
        {
          type: "delivery.validate",
          deliveryId,
          note: "Lot différent confirmé",
          shortfall: "returned",
          lines: [
            {
              productId: product,
              batch: "OTHER",
              expiry: "2031-06-30",
              quantity: 5,
            },
          ],
        },
        (await delivery(deliveryId)).version,
      ),
    );
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
