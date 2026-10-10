import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { addDays, dayToDate, tunisDay } from "../../core/dates";
import { Database, type Tx } from "../../core/database";
import { countPending } from "./approvals.service";
import { LOW_STOCK } from "./reports.service";
import { walletSummary } from "../rewards/wallet.queries";

interface Window {
  sales: number;
  units: number;
  rewardMillimes: bigint;
}

/** One screen of numbers per role. Row-level security already limits what each person can count. */
@Injectable()
export class DashboardService {
  constructor(private readonly db: Database) {}

  /**
   * The management dashboard is a dozen aggregate queries. Many phones asking at the same
   * moment (the morning rush) share one answer for a few seconds instead of each running
   * them; a pull to refresh a moment later is always fresh.
   */
  private readonly recent = new Map<
    string,
    { at: number; value: Promise<unknown> }
  >();

  private shared<T>(key: string, compute: () => Promise<T>): Promise<T> {
    if (process.env.NODE_ENV === "test") return compute();
    const now = Date.now();
    const hit = this.recent.get(key);
    if (hit && now - hit.at < 3000) return hit.value as Promise<T>;
    for (const [k, v] of this.recent)
      if (now - v.at > 10_000) this.recent.delete(k);
    const value = compute().catch((error) => {
      this.recent.delete(key);
      throw error;
    });
    this.recent.set(key, { at: now, value });
    return value;
  }

  forActor(actor: Actor, filter: { regionId?: string }) {
    switch (actor.role) {
      case "ADMIN":
      case "RESPONSABLE":
        return this.shared(`${actor.id}:${filter.regionId ?? ""}`, () =>
          this.management(actor, filter.regionId),
        );
      default:
        return this.vendeur(actor);
    }
  }

  private async management(actor: Actor, regionId?: string) {
    const today = tunisDay(new Date());
    const scope = actor.role === "ADMIN" ? regionId : undefined;
    // Row-level security already limits a responsable to their region; saying so in the
    // query as well lets the database use its indexes instead of reading every sale.
    const saleRegion = scope ?? actor.regionId ?? undefined;
    const sale = saleRegion
      ? Prisma.sql`AND s."regionId" = ${saleRegion}::uuid`
      : Prisma.empty;
    return this.db.run(actor, async (tx) => {
      const [
        week,
        month,
        trend,
        topProducts,
        topPdvs,
        attention,
        restocks,
        regions,
        pdvs,
        payouts,
        topGroups,
        lowByPlace,
        region,
        grossistes,
        toShip,
      ] = await Promise.all([
        window(tx, addDays(today, -6), today, sale),
        window(tx, addDays(today, -29), today, sale),
        this.trend(tx, addDays(today, -13), today, sale),
        tx.$queryRaw<
          {
            productId: string;
            name: string;
            family: string;
            imageId: string | null;
            units: number;
          }[]
        >`
          SELECT l."productId", p.name, p.family, p."imageId", SUM(l.quantity)::int AS units
          FROM "Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId"
          WHERE s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -29))} ${sale}
          GROUP BY l."productId", p.name, p.family, p."imageId" ORDER BY units DESC LIMIT 30`,
        tx.$queryRaw<
          {
            pdvId: string;
            name: string;
            city: string;
            units: number;
            rewardMillimes: bigint;
          }[]
        >`
          SELECT s."pdvId", pd.name, pd.city, SUM(s.units)::int AS units, SUM(s."rewardMillimes")::bigint AS "rewardMillimes"
          FROM "Sale" s JOIN "Pdv" pd ON pd.id = s."pdvId"
          WHERE s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -29))} ${sale}
          GROUP BY s."pdvId", pd.name, pd.city ORDER BY units DESC LIMIT 10`,
        tx.$queryRaw<{ negative: number; low: number }[]>`
          SELECT COUNT(*) FILTER (WHERE quantity < 0)::int AS negative,
                 COUNT(*) FILTER (WHERE quantity >= 0 AND quantity <= ${LOW_STOCK})::int AS low
          FROM "Stock" WHERE "locationKind" = 'PDV' ${scope ? Prisma.sql`AND "regionId" = ${scope}::uuid` : Prisma.empty}`,
        tx.restockOrder.groupBy({
          by: ["status"],
          where: {
            status: { in: ["REQUESTED", "ASSIGNED", "SHIPPED", "RECEIVED"] },
            ...(scope && { regionId: scope }),
          },
          _count: { _all: true },
        }),
        actor.role === "ADMIN" ? this.regions(tx, today) : Promise.resolve([]),
        tx.$queryRaw<{ active: number; pending: number }[]>`
          SELECT COUNT(*) FILTER (WHERE status='ACTIVE')::int AS active, COUNT(*) FILTER (WHERE status='PENDING')::int AS pending
          FROM "Pdv" ${scope ? Prisma.sql`WHERE "regionId" = ${scope}::uuid` : Prisma.empty}`,
        actor.role === "ADMIN"
          ? tx.payoutRequest.aggregate({
              where: { status: "PENDING", ...(scope && { regionId: scope }) },
              _sum: { amountMillimes: true },
              _count: { _all: true },
            })
          : null,
        tx.$queryRaw<{ groupId: string; name: string; units: number }[]>`
          SELECT g.id AS "groupId", g.name, SUM(s.units)::int AS units
          FROM "Sale" s JOIN "Pdv" pd ON pd.id = s."pdvId" JOIN "Group" g ON g.id = pd."groupId"
          WHERE s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -29))} ${sale}
          GROUP BY g.id, g.name ORDER BY units DESC LIMIT 3`,
        // The stores with products running out, one line per store.
        tx.$queryRaw<
          { pdvId: string; place: string; low: number; out: number }[]
        >`
          SELECT st."locationId" AS "pdvId", pd.name AS place,
                 COUNT(*) FILTER (WHERE st.quantity <= ${LOW_STOCK})::int AS low,
                 COUNT(*) FILTER (WHERE st.quantity <= 0)::int AS out
          FROM "Stock" st JOIN "Pdv" pd ON pd.id = st."locationId" JOIN "Product" p ON p.id = st."productId"
          WHERE st."locationKind" = 'PDV' AND pd.status = 'ACTIVE' AND p.active
            ${scope ? Prisma.sql`AND st."regionId" = ${scope}::uuid` : Prisma.empty}
          GROUP BY st."locationId", pd.name
          HAVING COUNT(*) FILTER (WHERE st.quantity <= ${LOW_STOCK}) > 0
          ORDER BY out DESC, low DESC, pd.name LIMIT 8`,
        scope ? this.regionCard(tx, scope) : Promise.resolve(null),
        // Grossistes: how many are active, and how many still wait for their first stock.
        tx.$queryRaw<{ active: number; uncounted: number }[]>`
          SELECT COUNT(*)::int AS active,
                 COUNT(*) FILTER (WHERE NOT EXISTS (
                   SELECT 1 FROM "StockDeclaration" x WHERE x."locationId" = d.id AND x.status = 'APPROVED'))::int AS uncounted
          FROM "Depot" d WHERE d.status = 'ACTIVE' ${scope ? Prisma.sql`AND d."regionId" = ${scope}::uuid` : Prisma.empty}`,
        // Orders waiting to leave a grossiste of the caller's region.
        actor.role === "RESPONSABLE" && actor.regionId
          ? tx.restockOrder.count({
              where: { status: "ASSIGNED", supplierRegionId: actor.regionId },
            })
          : Promise.resolve(0),
      ]);
      const day = trend.at(-1);
      return {
        role: actor.role,
        approvals: await countPending(tx, scope),
        sales: {
          today: day
            ? {
                sales: day.sales,
                units: day.units,
                rewardMillimes: day.rewardMillimes,
              }
            : empty(),
          week,
          month,
        },
        trend,
        topProducts,
        topPdvs,
        topGroups,
        lowByPlace,
        region,
        attention: {
          negativeStock: attention[0]?.negative ?? 0,
          lowStock: attention[0]?.low ?? 0,
        },
        restocks: Object.fromEntries(
          restocks.map((r) => [r.status, r._count._all]),
        ),
        pdvs: { active: pdvs[0]?.active ?? 0, pending: pdvs[0]?.pending ?? 0 },
        toShip,
        grossistes: {
          active: grossistes[0]?.active ?? 0,
          uncounted: grossistes[0]?.uncounted ?? 0,
        },
        regions,
        payouts: payouts
          ? {
              pending: payouts._count._all,
              amountMillimes: payouts._sum.amountMillimes ?? 0n,
            }
          : null,
      };
    });
  }

  /** Who runs a region and what it holds, for the admin's page about one region. */
  private async regionCard(tx: Tx, regionId: string) {
    const [region, responsable, counts, depots] = await Promise.all([
      tx.region.findUnique({ where: { id: regionId } }),
      tx.user.findFirst({
        where: { role: "RESPONSABLE", regionId, status: "ACTIVE" },
        select: { id: true, name: true, phone: true, email: true },
      }),
      tx.$queryRaw<{ groups: number; pdvs: number; members: number }[]>`
        SELECT (SELECT COUNT(*) FROM "Group" WHERE "regionId"=${regionId}::uuid AND status='ACTIVE')::int AS groups,
               (SELECT COUNT(*) FROM "Pdv" WHERE "regionId"=${regionId}::uuid AND status='ACTIVE')::int AS pdvs,
               (SELECT COUNT(*) FROM "User" WHERE "regionId"=${regionId}::uuid AND role='VENDEUR' AND status='ACTIVE')::int AS members`,
      tx.depot.count({ where: { regionId, status: "ACTIVE" } }),
    ]);
    return region
      ? {
          id: region.id,
          name: region.name,
          responsable,
          groups: counts[0]?.groups ?? 0,
          pdvs: counts[0]?.pdvs ?? 0,
          members: counts[0]?.members ?? 0,
          grossistes: depots,
        }
      : null;
  }

  /** The admin's view across the three regions, side by side. */
  private async regions(tx: Tx, today: string) {
    const rows = await tx.$queryRaw<
      {
        id: string;
        code: string;
        name: string;
        pdvs: number;
        members: number;
        sales: number;
        units: number;
        rewardMillimes: bigint;
        pending: number;
      }[]
    >`SELECT r.id, r.code, r.name,
        (SELECT COUNT(*) FROM "Pdv" p WHERE p."regionId"=r.id AND p.status='ACTIVE')::int AS pdvs,
        (SELECT COUNT(*) FROM "User" u WHERE u."regionId"=r.id AND u.role='VENDEUR' AND u.status='ACTIVE')::int AS members,
        COALESCE((SELECT COUNT(*) FROM "Sale" s WHERE s."regionId"=r.id AND s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -6))}),0)::int AS sales,
        COALESCE((SELECT SUM(s.units) FROM "Sale" s WHERE s."regionId"=r.id AND s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -6))}),0)::int AS units,
        COALESCE((SELECT SUM(s."rewardMillimes") FROM "Sale" s WHERE s."regionId"=r.id AND s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -6))}),0)::bigint AS "rewardMillimes",
        ((SELECT COUNT(*) FROM "Pdv" p WHERE p."regionId"=r.id AND p.status='PENDING')
          + (SELECT COUNT(*) FROM "Group" g WHERE g."regionId"=r.id AND g.status='PENDING')
          + (SELECT COUNT(*) FROM "User" u WHERE u."regionId"=r.id AND u.status='PENDING')
          + (SELECT COUNT(*) FROM "StockDeclaration" d WHERE d."regionId"=r.id AND d.status='PENDING')
          + (SELECT COUNT(*) FROM "RestockOrder" o WHERE o."regionId"=r.id AND o.status IN ('REQUESTED','RECEIVED')))::int AS pending
      FROM "Region" r ORDER BY r.name`;
    return rows;
  }

  private async vendeur(actor: Actor) {
    const today = tunisDay(new Date());
    return this.db.run(actor, async (tx) => {
      const [wallet, week, latest] = await Promise.all([
        walletSummary(tx, actor.id),
        window(
          tx,
          addDays(today, -6),
          today,
          Prisma.sql`AND s."sellerId" = ${actor.id}::uuid`,
        ),
        tx.sale.findMany({
          where: { status: "ACTIVE", sellerId: actor.id },
          orderBy: [{ createdAt: "desc" }],
          take: 5,
          select: {
            id: true,
            occurredAt: true,
            units: true,
            rewardMillimes: true,
          },
        }),
      ]);
      const pdv = actor.pdvId
        ? await tx.pdv.findUnique({
            where: { id: actor.pdvId },
            select: { id: true, name: true, status: true },
          })
        : null;
      return { role: actor.role, pdv, wallet, week, latest };
    });
  }

  /** Daily totals for the last days, with zero-filled gaps. */
  private async trend(tx: Tx, from: string, to: string, scope: Prisma.Sql) {
    const rows = await tx.$queryRaw<
      { day: string; sales: number; units: number; rewardMillimes: bigint }[]
    >`
      SELECT to_char(s.day,'YYYY-MM-DD') AS day, COUNT(*)::int AS sales, SUM(s.units)::int AS units, SUM(s."rewardMillimes")::bigint AS "rewardMillimes"
      FROM "Sale" s WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(from)} AND ${dayToDate(to)} ${scope} GROUP BY 1`;
    const byDay = new Map(rows.map((r) => [r.day, r]));
    const days: {
      day: string;
      sales: number;
      units: number;
      rewardMillimes: bigint;
    }[] = [];
    for (let d = from; d <= to; d = addDays(d, 1))
      days.push(
        byDay.get(d) ?? { day: d, sales: 0, units: 0, rewardMillimes: 0n },
      );
    return days;
  }
}

const empty = (): Window => ({ sales: 0, units: 0, rewardMillimes: 0n });

async function window(
  tx: Tx,
  from: string,
  to: string,
  scope: Prisma.Sql,
): Promise<Window> {
  const [row] = await tx.$queryRaw<Window[]>`
    SELECT COUNT(*)::int AS sales, COALESCE(SUM(s.units),0)::int AS units, COALESCE(SUM(s."rewardMillimes"),0)::bigint AS "rewardMillimes"
    FROM "Sale" s WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(from)} AND ${dayToDate(to)} ${scope}`;
  return row ?? empty();
}
