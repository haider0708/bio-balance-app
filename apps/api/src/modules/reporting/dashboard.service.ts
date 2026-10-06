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

  forActor(actor: Actor, filter: { regionId?: string }) {
    switch (actor.role) {
      case "ADMIN":
      case "RESPONSABLE":
        return this.management(actor, filter.regionId);
      case "GROSSISTE":
        return this.grossiste(actor);
      default:
        return this.vendeur(actor);
    }
  }

  private async management(actor: Actor, regionId?: string) {
    const today = tunisDay(new Date());
    const scope = actor.role === "ADMIN" ? regionId : undefined;
    const sale = scope
      ? Prisma.sql`AND s."regionId" = ${scope}::uuid`
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
      ] = await Promise.all([
        window(tx, addDays(today, -6), today, sale),
        window(tx, addDays(today, -29), today, sale),
        this.trend(tx, addDays(today, -13), today, sale),
        tx.$queryRaw<
          { productId: string; name: string; family: string; units: number }[]
        >`
          SELECT l."productId", p.name, p.family, SUM(l.quantity)::int AS units
          FROM "Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId"
          WHERE s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -29))} ${sale}
          GROUP BY l."productId", p.name, p.family ORDER BY units DESC LIMIT 5`,
        tx.$queryRaw<
          {
            pdvId: string;
            name: string;
            units: number;
            rewardMillimes: bigint;
          }[]
        >`
          SELECT s."pdvId", pd.name, SUM(s.units)::int AS units, SUM(s."rewardMillimes")::bigint AS "rewardMillimes"
          FROM "Sale" s JOIN "Pdv" pd ON pd.id = s."pdvId"
          WHERE s.status='ACTIVE' AND s.day >= ${dayToDate(addDays(today, -29))} ${sale}
          GROUP BY s."pdvId", pd.name ORDER BY units DESC LIMIT 5`,
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
        attention: {
          negativeStock: attention[0]?.negative ?? 0,
          lowStock: attention[0]?.low ?? 0,
        },
        restocks: Object.fromEntries(
          restocks.map((r) => [r.status, r._count._all]),
        ),
        pdvs: { active: pdvs[0]?.active ?? 0, pending: pdvs[0]?.pending ?? 0 },
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

  private async grossiste(actor: Actor) {
    return this.db.run(actor, async (tx) => {
      const [toShip, mine, stock, declaration] = await Promise.all([
        tx.restockOrder.count({
          where: { status: "ASSIGNED", supplierDepotId: actor.depotId },
        }),
        tx.restockOrder.groupBy({
          by: ["status"],
          where: {
            destId: actor.depotId ?? undefined,
            status: { in: ["REQUESTED", "SHIPPED", "RECEIVED"] },
          },
          _count: { _all: true },
        }),
        tx.stock.aggregate({
          where: { locationId: actor.depotId ?? undefined },
          _sum: { quantity: true },
          _count: { _all: true },
        }),
        tx.stockDeclaration.findFirst({
          where: { locationId: actor.depotId ?? undefined },
          orderBy: { createdAt: "desc" },
          select: { id: true, status: true, kind: true, createdAt: true },
        }),
      ]);
      return {
        role: actor.role,
        toShip,
        myRestocks: Object.fromEntries(
          mine.map((m) => [m.status, m._count._all]),
        ),
        stock: { units: stock._sum.quantity ?? 0, products: stock._count._all },
        lastDeclaration: declaration,
      };
    });
  }

  private async vendeur(actor: Actor) {
    const today = tunisDay(new Date());
    return this.db.run(actor, async (tx) => {
      const [wallet, week, latest] = await Promise.all([
        walletSummary(tx, actor.id),
        window(tx, addDays(today, -6), today, Prisma.empty),
        tx.sale.findMany({
          where: { status: "ACTIVE" },
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
