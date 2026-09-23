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

type Serialized<T> = {
  [K in keyof T]: T[K] extends Date | bigint ? string : T[K];
};
const timestamp = (value: string) => new Date(`${value}Z`);

/** Bounded read projections retain the caller's transaction and RLS context. */
export class StoreReadQueries {
  constructor(
    private readonly tx: Prisma.TransactionClient,
    private readonly scope: Scope,
  ) {}

  async snapshotCollections() {
    // One round trip for independent bounded projections on the same connection.
    const [row] = await this.tx.$queryRaw<
      {
        points: Serialized<PointsAccount> | null;
        rewards: Reward[];
        claims: Serialized<RewardClaim>[];
        orders: Serialized<ReplenishmentOrder>[];
        deliveries: Serialized<Delivery>[];
      }[]
    >(Prisma.sql`SELECT
      (SELECT to_jsonb(p)||jsonb_build_object('balance',p.balance::text,'reserved',p.reserved::text)
        FROM "PointsAccount" p WHERE p."storeId"=${this.scope.storeId}::uuid AND p."userId"=${this.scope.actor.id}::uuid) AS points,
      COALESCE((SELECT jsonb_agg(r ORDER BY r.id) FROM (${this.operationalQuery("rewards")}) r),'[]'::jsonb) AS rewards,
      COALESCE((SELECT jsonb_agg(c ORDER BY c.id) FROM (${this.operationalQuery("claims")}) c),'[]'::jsonb) AS claims,
      COALESCE((SELECT jsonb_agg(o ORDER BY o.id) FROM (${this.operationalQuery("orders")}) o),'[]'::jsonb) AS orders,
      COALESCE((SELECT jsonb_agg(d ORDER BY d.id) FROM (${this.operationalQuery("deliveries")}) d),'[]'::jsonb) AS deliveries`);
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
        createdAt: timestamp(c.createdAt),
        resolvedAt: c.resolvedAt ? timestamp(String(c.resolvedAt)) : null,
      })),
      orders: row!.orders.map((o) => ({
        ...o,
        createdAt: timestamp(o.createdAt),
      })),
      deliveries: row!.deliveries.map((d) => ({
        ...d,
        dispatchedAt: timestamp(d.dispatchedAt),
        receivedAt: d.receivedAt ? timestamp(String(d.receivedAt)) : null,
      })),
    };
  }

  /** All unresolved work plus a recent resolved tail, in stable bounded pages. */
  operationalPage(
    resource: "rewards" | "claims" | "orders" | "deliveries",
    after?: string,
  ): Promise<(Reward | RewardClaim | ReplenishmentOrder | Delivery)[]> {
    return this.tx.$queryRaw(this.operationalQuery(resource, after));
  }
  private operationalQuery(
    resource: "rewards" | "claims" | "orders" | "deliveries",
    after?: string,
  ) {
    const store = this.scope.storeId,
      user = this.scope.actor.id;
    const manage =
      this.scope.actor.platformAdmin ||
      this.scope.permissions.includes("manage");
    const boundary = after ? Prisma.sql`AND id>${after}::uuid` : Prisma.empty;
    if (resource === "rewards")
      return Prisma.sql`SELECT * FROM "Reward"
      WHERE "storeId"=${store}::uuid AND (${manage} OR active) ${boundary} ORDER BY id LIMIT 200`;
    if (resource === "claims")
      return Prisma.sql`SELECT * FROM "RewardClaim"
      WHERE "storeId"=${store}::uuid AND (${manage} OR "userId"=${user}::uuid)
      AND (status='requested' OR id IN (SELECT id FROM "RewardClaim" WHERE "storeId"=${store}::uuid
        AND (${manage} OR "userId"=${user}::uuid) ORDER BY "createdAt" DESC,id DESC LIMIT 100))
      ${boundary} ORDER BY id LIMIT 200`;
    if (resource === "orders")
      return Prisma.sql`SELECT * FROM "ReplenishmentOrder"
      WHERE ${manage} AND "storeId"=${store}::uuid AND (status NOT IN ('received','cancelled','closed_partial') OR id IN (SELECT id FROM "ReplenishmentOrder"
        WHERE "storeId"=${store}::uuid ORDER BY "createdAt" DESC,id DESC LIMIT 100))
      ${boundary} ORDER BY id LIMIT 200`;
    return Prisma.sql`SELECT * FROM "Delivery" WHERE ${manage} AND "storeId"=${store}::uuid AND status='dispatched'
      ${boundary} ORDER BY id LIMIT 200`;
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
