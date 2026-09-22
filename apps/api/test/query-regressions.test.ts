import { assertTestDatabases } from "./test-database.cjs";
import { afterAll, describe, expect, it, vi } from "vitest";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw Error("ISOLATED_TEST_DATABASE_REQUIRED");
assertTestDatabases(process.env.DATABASE_URL, process.env.TEST_OWNER_DATABASE_URL ??
  'postgresql://biobalance:local-development-only@localhost:54329/biobalance_test');
const owner = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.TEST_OWNER_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
  }),
});
const db = new Database();
afterAll(async () => {
  vi.useRealTimers();
  await db.$disconnect();
  await owner.$disconnect();
});

async function fixture(timezone = "Africa/Tunis") {
  const actor = await owner.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Query regression",
      passwordHash: "test-only-not-a-login",
    },
  });
  const org = await owner.organization.create({ data: { name: "Query test" } });
  const store = await owner.store.create({
    data: {
      organizationId: org.id,
      name: "Query test",
      address: "Test address",
      city: "Test city",
      timezone,
    },
  });
  await owner.membership.create({
    data: {
      organizationId: org.id,
      storeId: store.id,
      userId: actor.id,
      permissions: ["manage", "sell"],
    },
  });
  return { actor, org, store };
}

describe.sequential(
  "indexed store reads retain their security and calendar rules",
  () => {
    it("keeps read snapshots consistent, rechecks access, and retains serializable commands", async () => {
      const f = await fixture();
      const sale = await owner.sale.create({
        data: {
          id: randomUUID(),
          organizationId: f.org.id,
          storeId: f.store.id,
          sellerId: f.actor.id,
          occurredAt: new Date(),
          lines: [],
          totalMillimes: 1000n,
          earnedPoints: 0n,
        },
      });
      await db.scopedSnapshot(f.actor, f.org.id, f.store.id, async (tx) => {
        const mode = await tx.$queryRaw<
          { transaction_isolation: string }[]
        >`SHOW transaction_isolation`;
        expect(mode[0]!.transaction_isolation).toBe("repeatable read");
        const before = await tx.sale.findUniqueOrThrow({
          where: { id: sale.id },
        });
        await owner.sale.update({
          where: { id: sale.id },
          data: { totalMillimes: 2000n },
        });
        expect(
          (await tx.sale.findUniqueOrThrow({ where: { id: sale.id } }))
            .totalMillimes,
        ).toBe(before.totalMillimes);
      });
      await db.scoped(f.actor, f.org.id, f.store.id, async (tx) => {
        const mode = await tx.$queryRaw<
          { transaction_isolation: string }[]
        >`SHOW transaction_isolation`;
        expect(mode[0]!.transaction_isolation).toBe("serializable");
        expect(
          (await tx.sale.findUniqueOrThrow({ where: { id: sale.id } }))
            .totalMillimes,
        ).toBe(2000n);
      });
      await owner.membership.updateMany({
        where: { storeId: f.store.id },
        data: { active: false },
      });
      await expect(
        db.scopedSnapshot(f.actor, f.org.id, f.store.id, async () => true),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
    });
    it("rechecks sale scope on reused connections and keeps admin reads read-only", async () => {
      const a = await fixture(),
        b = await fixture();
      const sales = [];
      for (const f of [a, b]) {
        sales.push(
          await owner.sale.create({
            data: {
              id: randomUUID(),
              organizationId: f.org.id,
              storeId: f.store.id,
              sellerId: f.actor.id,
              occurredAt: new Date(),
              lines: [],
              totalMillimes: 1000n,
              earnedPoints: 0n,
            },
          }),
        );
      }
      const ids = sales.map((s) => s.id);
      for (const f of [a, b, a]) {
        const visible = await db.scoped(f.actor, f.org.id, f.store.id, (tx) =>
          tx.sale.findMany({ where: { id: { in: ids } } }),
        );
        expect(visible.map((s) => s.storeId)).toEqual([f.store.id]);
      }
      expect(await db.sale.findMany({ where: { id: { in: ids } } })).toEqual(
        [],
      );
      await expect(
        db.scoped(a.actor, a.org.id, b.store.id, (tx) => tx.sale.findMany()),
      ).rejects.toMatchObject({ code: "STORE_ACCESS_REVOKED" });
      await db.$transaction(async (tx) => {
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
        expect(await tx.sale.count({ where: { id: { in: ids } } })).toBe(2);
        expect(
          (
            await tx.sale.updateMany({
              where: { id: { in: ids } },
              data: { totalMillimes: 9999n },
            })
          ).count,
        ).toBe(0);
      });
      expect(await db.sale.count({ where: { id: { in: ids } } })).toBe(0);
      await expect(
        db.scoped(a.actor, a.org.id, a.store.id, (tx) =>
          tx.sale.create({
            data: {
              ...sales[0]!,
              id: randomUUID(),
              organizationId: b.org.id,
              storeId: b.store.id,
            },
          }),
        ),
      ).rejects.toThrow();
      expect(
        (await owner.sale.findMany({ where: { id: { in: ids } } })).every(
          (s) => s.totalMillimes === 1000n,
        ),
      ).toBe(true);
    });

    it.each([
      ["Africa/Tunis", "2026-02-28T23:00:00.000Z", "2026-03-31T23:00:00.000Z"],
      [
        "America/New_York",
        "2026-03-01T05:00:00.000Z",
        "2026-04-01T04:00:00.000Z",
      ],
    ])(
      "ranks only net earned points inside the local month in %s",
      async (zone, start, end) => {
        const f = await fixture(zone);
        const lower = new Date(start).getTime(),
          upper = new Date(end).getTime();
        for (const [at, amount, kind] of [
          [lower - 1, 1000, "earned"],
          [lower, 10, "earned"],
          [lower + 1000, -5, "earned"],
          [lower + 2000, -20, "spent"],
          [upper - 1, 40, "earned"],
          [upper, 2000, "earned"],
        ] as const) {
          await owner.pointsEntry.create({
            data: {
              organizationId: f.org.id,
              storeId: f.store.id,
              userId: f.actor.id,
              amount,
              kind,
              sourceId: randomUUID(),
              operationId: randomUUID(),
              createdAt: new Date(at),
            },
          });
        }
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date("2026-03-15T12:00:00Z"));
        try {
          const result = await new WorkspaceService(db).ranking(
            f.actor,
            f.org.id,
            f.store.id,
          );
          expect(result.month).toBe("2026-03");
          expect(result.scores).toEqual([
            { userId: f.actor.id, name: f.actor.name, score: 45n, rank: 1n },
          ]);
        } finally {
          vi.useRealTimers();
        }
      },
    );
  },
);
