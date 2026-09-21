import {
  InventoryLot,
  Prisma,
  Sale,
  Reward,
  RewardClaim,
  ReplenishmentOrder,
  Delivery,
  PointsAccount,
} from "@prisma/client";
import { Scope } from "../../operations/domain/contracts";

type JsonScalar<T> = T extends Date | bigint ? string : T;
type DatabaseJson<T> = { [K in keyof T]: JsonScalar<T[K]> };
const utcTimestamp = (value: string) => new Date(`${value}Z`);

/** Bounded read projections retain the caller's transaction and RLS context. */
export class StoreReadQueries {
  constructor(
    private readonly tx: Prisma.TransactionClient,
    private readonly scope: Scope,
  ) {}

  async snapshotCollections() {
    const store = this.scope.storeId,
      user = this.scope.actor.id;
    const manage =
      this.scope.actor.platformAdmin ||
      this.scope.permissions.includes("manage");
    const [row] = await this.tx.$queryRaw<
      {
        points: DatabaseJson<PointsAccount> | null;
        rewards: Reward[];
        claims: DatabaseJson<RewardClaim>[];
        orders: DatabaseJson<ReplenishmentOrder>[];
        deliveries: DatabaseJson<Delivery>[];
      }[]
    >`SELECT
      (SELECT to_jsonb(p)||jsonb_build_object('balance',p.balance::text,'reserved',p.reserved::text)
       FROM "PointsAccount" p WHERE p."storeId"=${store}::uuid AND p."userId"=${user}::uuid) AS points,
      COALESCE((SELECT jsonb_agg(r ORDER BY r.title,r.id) FROM
        (SELECT * FROM "Reward" WHERE "storeId"=${store}::uuid AND (${manage} OR active)
         ORDER BY title,id LIMIT 200) r),'[]'::jsonb) AS rewards,
      COALESCE((SELECT jsonb_agg(c ORDER BY c."createdAt" DESC,c.id DESC) FROM
        (SELECT * FROM "RewardClaim" WHERE "storeId"=${store}::uuid AND (${manage} OR "userId"=${user}::uuid)
         ORDER BY "createdAt" DESC,id DESC LIMIT 100) c),'[]'::jsonb) AS claims,
      COALESCE((SELECT jsonb_agg(o ORDER BY o."createdAt" DESC,o.id DESC) FROM
        (SELECT * FROM "ReplenishmentOrder" WHERE "storeId"=${store}::uuid
         ORDER BY "createdAt" DESC,id DESC LIMIT 100) o),'[]'::jsonb) AS orders,
      COALESCE((SELECT jsonb_agg(d ORDER BY d."dispatchedAt" DESC,d.id DESC) FROM
        (SELECT * FROM "Delivery" WHERE "storeId"=${store}::uuid AND status='dispatched'
         ORDER BY "dispatchedAt" DESC,id DESC LIMIT 100) d),'[]'::jsonb) AS deliveries`;
    // PostgreSQL timestamp columns have UTC semantics; JSON lacks the suffix.
    return {
      points: row!.points
        ? {
            ...row!.points,
            balance: BigInt(row!.points.balance),
            reserved: BigInt(row!.points.reserved),
          }
        : null,
      rewards: row!.rewards,
      claims: row!.claims.map((c) => ({
        ...c,
        createdAt: utcTimestamp(c.createdAt),
        resolvedAt: c.resolvedAt ? utcTimestamp(c.resolvedAt) : null,
      })),
      orders: row!.orders.map((o) => ({
        ...o,
        createdAt: utcTimestamp(o.createdAt),
      })),
      deliveries: row!.deliveries.map((d) => ({
        ...d,
        dispatchedAt: utcTimestamp(d.dispatchedAt),
        receivedAt: d.receivedAt ? utcTimestamp(d.receivedAt) : null,
      })),
    };
  }

  recentSales(
    cursor?: { id: string; date: Date },
    productId?: string,
  ): Promise<Sale[]> {
    const manage =
      this.scope.actor.platformAdmin ||
      this.scope.permissions.includes("manage");
    const filters = [Prisma.sql`"storeId"=${this.scope.storeId}::uuid`];
    if (!manage)
      filters.push(Prisma.sql`"sellerId"=${this.scope.actor.id}::uuid`);
    if (cursor)
      filters.push(
        Prisma.sql`("occurredAt",id)<(${cursor.date}::timestamp,${cursor.id}::uuid)`,
      );
    if (productId)
      filters.push(
        Prisma.sql`lines @> ${JSON.stringify([{ productId }])}::jsonb`,
      );
    return this.tx.$queryRaw<Sale[]>(Prisma.sql`SELECT * FROM "Sale"
      WHERE ${Prisma.join(filters, " AND ")} ORDER BY "occurredAt" DESC,id DESC LIMIT 100`);
  }

  lots(after?: string): Promise<InventoryLot[]> {
    return this.tx.$queryRaw<
      InventoryLot[]
    >(Prisma.sql`SELECT * FROM "InventoryLot"
      WHERE "storeId"=${this.scope.storeId}::uuid
      ${after ? Prisma.sql`AND id>${after}::uuid` : Prisma.empty}
      ORDER BY id ASC LIMIT 200`);
  }
}
