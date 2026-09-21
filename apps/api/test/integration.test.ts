import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import { PrismaUnitOfWork } from "../src/modules/operations/infrastructure/prisma-ledger";
import { OperationsService } from "../src/modules/operations/application/operations.service";
import {
  UnitOfWork,
  Ledger,
} from "../src/modules/operations/application/ports";
import {
  Actor,
  Command,
  Operation,
} from "../src/modules/operations/domain/contracts";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
const owner = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.TEST_OWNER_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
  }),
});
const db = new Database(),
  uow = new PrismaUnitOfWork(db),
  service = new OperationsService(uow),
  workspace = new WorkspaceService(db);
const actor: Actor = {
  id: randomUUID(),
  name: "Test manager",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const seller: Actor = {
  id: randomUUID(),
  name: "Test seller",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const foreign: Actor = {
  id: randomUUID(),
  name: "Other organization",
  email: `test-${randomUUID()}@example.test`,
  platformAdmin: false,
};
const admin: Actor = {...actor, id:randomUUID(), email:`admin-${randomUUID()}@example.test`, platformAdmin:true};
const org = randomUUID(),
  store = randomUUID(),
  otherStore = randomUUID(),
  product = randomUUID(),
  saleId = randomUUID(),
  lineId = randomUUID();
let lotId = "";
const op = (command: Command, expectedVersion?: number): Operation => ({
  operationId: randomUUID(),
  storeId: store,
  organizationId: org,
  payloadVersion: 1,
  command,
  expectedVersion,
});
beforeAll(async () => {
  for (const a of [actor, seller, foreign, admin])
    await owner.user.create({
      data: {
        id: a.id,
        email: a.email,
        name: a.name,
        passwordHash: "test-only-not-a-login",
        platformAdmin:a.platformAdmin,
      },
    });
  await owner.organization.create({
    data: { id: org, name: "Integration test" },
  });
  for (const id of [store, otherStore])
    await owner.store.create({
      data: {
        id,
        organizationId: org,
        name: "Test store",
        address: "Test address",
        city: "Tunis",
      },
    });
  for (const [userId, permissions] of [
    [actor.id, ["manage", "sell", "receive"]],
    [seller.id, ["sell", "receive"]],
  ] as const)
    await owner.membership.create({
      data: {
        organizationId: org,
        storeId: store,
        userId,
        permissions: [...permissions],
      },
    });
  await owner.product.create({
    data: { id: product, reference: product, name: "Test serum" },
  });
  await workspace.configureProduct(actor, org, store, product, {
    priceMillimes: "49900",
    threshold: 5,
    pointsPerUnit: 10,
  });
}, 30000);
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
});
describe.sequential(
  "PostgreSQL transactions with a restricted application role",
  () => {
    it("denies missing RLS context and cross-store/organization requests", async () => {
      expect(await db.inventoryLot.findMany()).toEqual([]);
      expect(
        (
          await service.submit(
            foreign,
            op({
              type: "stock.receive",
              reason: "opening",
              lines: [
                {
                  productId: product,
                  batch: "T1",
                  expiry: "2027-12",
                  quantity: 10,
                },
              ],
            }),
          )
        ).code,
      ).toBe("FORBIDDEN");
      expect(
        (
          await service.submit(seller, {
            ...op({ type: "stock.receive", reason: "opening", lines: [] }),
            storeId: otherStore,
          })
        ).code,
      ).toBe("FORBIDDEN");
    });
    it("receives a batch atomically and deduplicates the operation", async () => {
      const operation = op({
        type: "stock.receive",
        reason: "opening",
        lines: [
          { productId: product, batch: "T1", expiry: "2027-12", quantity: 10 },
        ],
      });
      const first = await service.submit(actor, operation);
      expect(first.status).toBe("accepted");
      expect(await service.submit(actor, operation)).toEqual(first);
      const lots = await owner.inventoryLot.findMany({
        where: { storeId: store },
      });
      expect(lots).toHaveLength(1);
      expect(lots[0]!.sellable).toBe(10);
      lotId = lots[0]!.id;
      const reused = {
        ...operation,
        command: { ...operation.command, reason: "receipt" },
      } as Operation;
      expect((await service.submit(actor, reused)).code).toBe(
        "OPERATION_REUSED",
      );
    });
    it("records sales, adjustments and points together; retries retain their accepted rate", async () => {
      const sale = op({
        type: "sale.create",
        saleId,
        occurredAt: new Date().toISOString(),
        lines: [
          {
            id: lineId,
            productId: product,
            quantity: 2,
            unitPriceMillimes: "49900",
            allocations: [{ lotId, quantity: 2 }],
          },
        ],
      });
      expect((await service.submit(seller, sale)).status).toBe("accepted");
      await workspace.configureProduct(actor, org, store, product, {
        priceMillimes: "49900",
        threshold: 5,
        pointsPerUnit: 99,
        expectedVersion: 1,
      });
      expect((await service.submit(seller, sale)).data?.points).toBe("20");
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(8);
      expect(
        (
          await owner.pointsAccount.findUniqueOrThrow({
            where: { storeId_userId: { storeId: store, userId: seller.id } },
          })
        ).balance,
      ).toBe(20n);
    });
    it("allows only the original seller or a manager to correct; detects concurrent versions", async () => {
      const sale = await owner.sale.findUniqueOrThrow({
        where: { id: saleId },
      });
      const correction = op(
        {
          type: "sale.correct",
          saleId,
          occurredAt: sale.occurredAt.toISOString(),
          reason: "Correction test",
          lines: [
            {
              id: lineId,
              productId: product,
              quantity: 1,
              unitPriceMillimes: "49900",
              allocations: [{ lotId, quantity: 1 }],
            },
          ],
        },
        1,
      );
      const results = await Promise.all([
        service.submit(seller, correction),
        service.submit(actor, { ...correction, operationId: randomUUID() }),
      ]);
      expect(results.filter((r) => r.status === "accepted")).toHaveLength(1);
      expect(results.filter((r) => r.code === "VERSION_CONFLICT")).toHaveLength(
        1,
      );
      expect(
        (
          await owner.pointsAccount.findUniqueOrThrow({
            where: { storeId_userId: { storeId: store, userId: seller.id } },
          })
        ).balance,
      ).toBe(10n);
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(9);
    });
    it("reserves, fulfills a product reward once, and carries a later return into a negative balance", async () => {
      const reward = await workspace.reward(actor, org, store, {
        title: "Test reward",
        description: "",
        cost: 10,
        productId: product,
        quantity: 1,
        active: true,
      });
      const claimId = randomUUID();
      expect(
        (
          await service.submit(
            seller,
            op({ type: "reward.request", claimId, rewardId: reward.id }),
          )
        ).status,
      ).toBe("accepted");
      expect(
        (
          await service.submit(
            seller,
            op({
              type: "reward.request",
              claimId: randomUUID(),
              rewardId: reward.id,
            }),
          )
        ).code,
      ).toBe("INSUFFICIENT_POINTS");
      const fulfill = op(
        { type: "reward.resolve", claimId, decision: "fulfilled" },
        1,
      );
      expect((await service.submit(actor, fulfill)).status).toBe("accepted");
      await service.submit(actor, fulfill);
      expect(
        (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
          .sellable,
      ).toBe(8);
      expect(
        (
          await service.submit(
            seller,
            op(
              {
                type: "sale.return",
                saleId,
                reason: "Retour client",
                lines: [{ lineId, lotId, quantity: 1, sellable: true }],
              },
              2,
            ),
          )
        ).status,
      ).toBe("accepted");
      const account = await owner.pointsAccount.findUniqueOrThrow({
        where: { storeId_userId: { storeId: store, userId: seller.id } },
      });
      expect(account.balance).toBe(-10n);
      expect(account.reserved).toBe(0n);
      expect(
        (
          await service.submit(
            seller,
            op(
              {
                type: "sale.return",
                saleId,
                reason: "Doublon retour",
                lines: [{ lineId, lotId, quantity: 1, sellable: true }],
              },
              3,
            ),
          )
        ).code,
      ).toBe("RETURN_EXCEEDS_SALE");
    });
    it("rolls back mutations after failures in late transactional stages", async () => {
      for (const stage of ["move", "credit", "finish"] as const) {
        const failing: UnitOfWork = {
          run: (a, o, s, work) =>
            uow.run(a, o, s, (ledger) =>
              work(
                new Proxy(ledger, {
                  get(target, key) {
                    const value = Reflect.get(target, key);
                    if (key === stage)
                      return async (...args: unknown[]) => {
                        await value.apply(target, args);
                        throw new Error("Injected failure");
                      };
                    return typeof value === "function"
                      ? value.bind(target)
                      : value;
                  },
                }) as Ledger,
              ),
            ),
        };
        const id = randomUUID(),
          before = await owner.inventoryLot.findUniqueOrThrow({
            where: { id: lotId },
          });
        await expect(
          new OperationsService(failing).submit(
            seller,
            op({
              type: "sale.create",
              saleId: id,
              occurredAt: new Date().toISOString(),
              lines: [
                {
                  id: randomUUID(),
                  productId: product,
                  quantity: 1,
                  unitPriceMillimes: "1000",
                  allocations: [{ lotId, quantity: 1 }],
                },
              ],
            }),
          ),
        ).rejects.toThrow("Injected failure");
        expect(await owner.sale.findUnique({ where: { id } })).toBeNull();
        expect(
          (await owner.inventoryLot.findUniqueOrThrow({ where: { id: lotId } }))
            .sellable,
        ).toBe(before.sellable);
      }
    });
    it("preserves insufficient-stock sales and creates one persistent discrepancy alert", async () => {
      for (let i = 0; i < 2; i++)
        expect(
          (
            await service.submit(
              seller,
              op({
                type: "sale.create",
                saleId: randomUUID(),
                occurredAt: new Date().toISOString(),
                lines: [
                  {
                    id: randomUUID(),
                    productId: product,
                    quantity: 20,
                    unitPriceMillimes: "1000",
                    allocations: [{ lotId, quantity: 20 }],
                  },
                ],
              }),
            )
          ).status,
        ).toBe("accepted");
      expect(
        await owner.alert.count({
          where: { storeId: store, kind: "discrepancy", active: true },
        }),
      ).toBe(1);
      expect(
        (
          await owner.notification.findMany({ where: { storeId: store } })
        ).every((n) => n.userId !== seller.id),
      ).toBe(true);
    });
    it("receives a shared delivery once and leaves shortages available for a follow-up", async () => {
      const orderId=randomUUID(), deliveryId=randomUUID();
      expect((await service.submit(actor,op({type:'order.create',orderId,lines:[{productId:product,quantity:10}]}))).status).toBe('accepted');
      const before=(await owner.inventoryLot.findUniqueOrThrow({where:{id:lotId}})).sellable;
      expect((await service.submit(admin,op({type:'delivery.dispatch',orderId,deliveryId,lines:[{productId:product,quantity:10}]},1))).status).toBe('accepted');
      expect((await owner.inventoryLot.findUniqueOrThrow({where:{id:lotId}})).sellable).toBe(before);
      const receipt=op({type:'delivery.receive',deliveryId,note:'Two missing',lines:[{productId:product,batch:'T1',expiry:'2027-12',quantity:8}]},1);
      const outcomes=await Promise.all([service.submit(seller,receipt),service.submit(actor,{...receipt,operationId:randomUUID()})]);
      expect(outcomes.filter(r=>r.status==='accepted')).toHaveLength(1);
      expect(await owner.deliveryReceipt.count({where:{deliveryId}})).toBe(1);
      expect((await owner.inventoryLot.findUniqueOrThrow({where:{id:lotId}})).sellable).toBe(before+8);
      const order=await owner.replenishmentOrder.findUniqueOrThrow({where:{id:orderId}});
      expect(order.status).toBe('partial');
      const followup=randomUUID();
      expect((await service.submit(admin,op({type:'delivery.dispatch',orderId,deliveryId:followup,lines:[{productId:product,quantity:2}]},order.version))).status).toBe('accepted');
      expect((await service.submit(seller,op({type:'delivery.receive',deliveryId:followup,note:'Complete',lines:[{productId:product,batch:'T1',expiry:'2027-12',quantity:2}]},1))).status).toBe('accepted');
      expect((await owner.replenishmentOrder.findUniqueOrThrow({where:{id:orderId}})).status).toBe('received');
      expect((await owner.inventoryLot.findUniqueOrThrow({where:{id:lotId}})).sellable).toBe(before+10);
    });
    it("rejects another active seller editing the original seller's sale", async () => {
      await owner.membership.create({data:{organizationId:org,storeId:store,userId:foreign.id,permissions:['sell']}});
      const sale=await owner.sale.findUniqueOrThrow({where:{id:saleId}});
      const result=await service.submit(foreign,op({type:'sale.correct',saleId,occurredAt:sale.occurredAt.toISOString(),reason:'Unauthorized',lines:sale.lines as any},sale.version));
      expect(result.code).toBe('FORBIDDEN');
      await owner.membership.update({where:{storeId_userId:{storeId:store,userId:foreign.id}},data:{active:false}});
    });
    it("synchronizes changed lots and invalidates a changed global catalog", async()=>{
      const snapshot=await workspace.snapshot(actor,org,store);
      expect(snapshot.mode).toBe('snapshot');
      await service.submit(actor,op({type:'stock.receive',reason:'receipt',lines:[{productId:product,batch:'DELTA',expiry:'2028-01',quantity:3}]}));
      const delta=await workspace.snapshot(actor,org,store,{cursor:snapshot.cursor,catalogRevision:snapshot.catalogRevision});
      expect(delta.mode).toBe('delta');
      expect(delta.products).toHaveLength(0);
      expect(delta.lots).toHaveLength(1);
      expect(delta.lots[0]!.batch).toBe('DELTA');
      expect(delta.lots[0]!.sellable).toBe(3);
      await owner.product.update({where:{id:product},data:{name:'Changed globally',version:{increment:1}}});
      const refreshed=await workspace.snapshot(actor,org,store,{cursor:delta.cursor,catalogRevision:delta.catalogRevision});
      expect(refreshed.mode).toBe('snapshot');
      expect(refreshed.products.find(p=>p.id===product)?.name).toBe('Changed globally');
    });
    it("removes disabled team access from synchronized data and denies further operations", async()=>{
      const before=await workspace.snapshot(actor,org,store);
      await workspace.setMember(actor,org,store,seller.id,{active:false,permissions:['sell','receive']});
      const delta=await workspace.snapshot(actor,org,store,{cursor:before.cursor,catalogRevision:before.catalogRevision});
      expect(delta.team.find(m=>m.userId===seller.id)?.active).toBe(false);
      await expect(workspace.snapshot(seller,org,store)).rejects.toMatchObject({code:'FORBIDDEN'});
      await workspace.setMember(actor,org,store,seller.id,{active:true,permissions:['sell','receive']});
    });
    it("rejects editing append-only histories at database level", async () => {
      const movement = await owner.stockMovement.findFirstOrThrow({
        where: { storeId: store },
      });
      await expect(
        owner.stockMovement.update({
          where: { id: movement.id },
          data: { quantity: 100 },
        }),
      ).rejects.toThrow();
    });
  },
);
