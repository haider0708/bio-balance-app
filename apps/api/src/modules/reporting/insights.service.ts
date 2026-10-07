import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { addDays, dayToDate, tunisDay } from "../../core/dates";
import { Database, type Tx } from "../../core/database";
import { requireRule } from "../../core/errors";
import { LOW_STOCK } from "./reports.service";

interface Period {
  from: string;
  to: string;
}

const days = (p: Period) =>
  Math.round((Date.parse(p.to) - Date.parse(p.from)) / 86400_000) + 1;

const pct = (now: number, before: number) =>
  before === 0 ? null : Math.round(((now - before) * 100) / before);

/**
 * What the numbers mean: totals against the period before, how sales spread over
 * the week and across families, which stores and sellers carry the sales, which
 * products are about to run out at the current pace — and a few plain sentences
 * (as keys, so each phone says them in its own language).
 */
@Injectable()
export class InsightsService {
  constructor(private readonly db: Database) {}

  report(actor: Actor, f: Period & { regionId?: string }) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    if (actor.role === "RESPONSABLE" && actor.regionId && !f.regionId)
      f = { ...f, regionId: actor.regionId };
    const length = days(f);
    const before: Period = {
      from: addDays(f.from, -length),
      to: addDays(f.from, -1),
    };
    return this.db.run(actor, async (tx) => {
      const region = (alias: string) =>
        f.regionId
          ? Prisma.sql`AND ${Prisma.raw(alias)}."regionId" = ${f.regionId}::uuid`
          : Prisma.empty;
      const [now, prev, daily, stores, allProducts, sellers, health] =
        await Promise.all([
          this.totals(tx, f, region),
          this.totals(tx, before, region),
          this.daily(tx, f, region),
          this.byStore(tx, f, before, region),
          this.byProduct(tx, f, before, region),
          this.bySeller(tx, f, region),
          this.stockHealth(tx, region),
        ]);

      // Families come from the same pass over the sale lines as the products.
      const byFamily = new Map<string, { units: number; before: number }>();
      for (const p of allProducts) {
        const f = byFamily.get(p.family) ?? { units: 0, before: 0 };
        f.units += p.units;
        f.before += p.before;
        byFamily.set(p.family, f);
      }
      const families = [...byFamily]
        .map(([name, v]) => ({
          name,
          units: v.units,
          before: v.before,
          change: pct(v.units, v.before),
        }))
        .sort((a, b) => b.units - a.units)
        .slice(0, 12);
      const products = allProducts.slice(0, 30);

      const weekdays = Array.from({ length: 7 }, (_, d) => ({
        weekday: d, // 0 = Sunday
        units: 0,
      }));
      for (const d of daily) weekdays[d.weekday]!.units += d.units;
      const active = daily.filter((d) => d.units > 0);
      const bestDay = active.reduce<(typeof daily)[number] | null>(
        (m, d) => (!m || d.units > m.units ? d : m),
        null,
      );
      const slowDay = active.reduce<(typeof daily)[number] | null>(
        (m, d) => (!m || d.units < m.units ? d : m),
        null,
      );
      const bestWeekday = weekdays.reduce((m, d) =>
        d.units > m.units ? d : m,
      );

      const insights: { key: string; params: Record<string, unknown> }[] = [];
      const topFamily = families[0];
      if (topFamily && now.units > 0)
        insights.push({
          key: "TOP_FAMILY",
          params: {
            family: topFamily.name,
            share: Math.round((topFamily.units * 100) / now.units),
            change: topFamily.change,
          },
        });
      const falling = stores
        .filter((s) => s.change !== null && s.change <= -20 && s.before >= 10)
        .sort((a, b) => a.change! - b.change!)[0];
      if (falling)
        insights.push({
          key: "STORE_DOWN",
          params: { store: falling.name, change: falling.change },
        });
      const rising = stores
        .filter((s) => s.change !== null && s.change >= 20 && s.before >= 10)
        .sort((a, b) => b.change! - a.change!)[0];
      if (rising)
        insights.push({
          key: "STORE_UP",
          params: { store: rising.name, change: rising.change },
        });
      if (health.runningOut.length)
        insights.push({
          key: "RUNNING_OUT",
          params: { count: health.runningOut.length, days: 7 },
        });
      if (health.dead.count)
        insights.push({
          key: "DEAD_STOCK",
          params: { count: health.dead.count },
        });
      if (bestWeekday.units > 0 && now.units > 0)
        insights.push({
          key: "BEST_WEEKDAY",
          params: {
            weekday: bestWeekday.weekday,
            share: Math.round((bestWeekday.units * 100) / now.units),
          },
        });
      if (sellers[0] && now.units > 0)
        insights.push({
          key: "TOP_SELLER",
          params: { name: sellers[0].name, units: sellers[0].units },
        });
      if (now.units > 0)
        insights.push({
          key: "REWARD_PER_UNIT",
          params: {
            amountMillimes: Math.round(now.rewardMillimes / now.units),
          },
        });

      return {
        period: f,
        previous: before,
        totals: {
          ...now,
          unitsChange: pct(now.units, prev.units),
          salesChange: pct(now.sales, prev.sales),
          rewardChange: pct(now.rewardMillimes, prev.rewardMillimes),
          unitsPerSale: now.sales
            ? Math.round((now.units * 10) / now.sales) / 10
            : 0,
          previousUnits: prev.units,
        },
        weekdays,
        bestDay,
        slowDay,
        families,
        stores,
        products,
        sellers,
        stock: health,
        insights,
      };
    });
  }

  private async totals(tx: Tx, p: Period, region: (a: string) => Prisma.Sql) {
    const [row] = await tx.$queryRaw<
      {
        sales: number;
        units: number;
        reward: bigint;
        stores: number;
        sellers: number;
      }[]
    >`SELECT COUNT(*)::int AS sales, COALESCE(SUM(s.units),0)::int AS units,
        COALESCE(SUM(s."rewardMillimes"),0)::bigint AS reward,
        COUNT(DISTINCT s."pdvId")::int AS stores, COUNT(DISTINCT s."sellerId")::int AS sellers
      FROM "Sale" s WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)} ${region("s")}`;
    return {
      sales: row?.sales ?? 0,
      units: row?.units ?? 0,
      rewardMillimes: Number(row?.reward ?? 0n),
      activeStores: row?.stores ?? 0,
      activeSellers: row?.sellers ?? 0,
    };
  }

  private async daily(tx: Tx, p: Period, region: (a: string) => Prisma.Sql) {
    return tx.$queryRaw<{ day: string; units: number; weekday: number }[]>`
      SELECT to_char(s.day,'YYYY-MM-DD') AS day, SUM(s.units)::int AS units, EXTRACT(DOW FROM s.day)::int AS weekday
      FROM "Sale" s WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)} ${region("s")}
      GROUP BY s.day ORDER BY s.day`;
  }

  private async byStore(
    tx: Tx,
    p: Period,
    q: Period,
    region: (a: string) => Prisma.Sql,
  ) {
    const rows = await tx.$queryRaw<
      {
        id: string;
        name: string;
        city: string;
        units: number;
        before: number;
        reward: bigint;
      }[]
    >`SELECT s."pdvId" AS id, pd.name, pd.city,
        COALESCE(SUM(s.units) FILTER (WHERE s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)}),0)::int AS units,
        COALESCE(SUM(s.units) FILTER (WHERE s.day BETWEEN ${dayToDate(q.from)} AND ${dayToDate(q.to)}),0)::int AS before,
        COALESCE(SUM(s."rewardMillimes") FILTER (WHERE s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)}),0)::bigint AS reward
      FROM "Sale" s JOIN "Pdv" pd ON pd.id = s."pdvId"
      WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(q.from)} AND ${dayToDate(p.to)} ${region("s")}
      GROUP BY s."pdvId", pd.name, pd.city ORDER BY units DESC, pd.name LIMIT 30`;
    const total = rows.reduce((t, r) => t + r.units, 0);
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      city: r.city,
      units: r.units,
      before: r.before,
      rewardMillimes: Number(r.reward),
      share: total ? Math.round((r.units * 100) / total) : 0,
      change: pct(r.units, r.before),
    }));
  }

  private async byProduct(
    tx: Tx,
    p: Period,
    q: Period,
    region: (a: string) => Prisma.Sql,
  ) {
    const rows = await tx.$queryRaw<
      {
        id: string;
        name: string;
        family: string;
        imageId: string | null;
        units: number;
        before: number;
      }[]
    >`SELECT p.id, p.name, p.family, p."imageId",
        COALESCE(SUM(l.quantity) FILTER (WHERE s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)}),0)::int AS units,
        COALESCE(SUM(l.quantity) FILTER (WHERE s.day BETWEEN ${dayToDate(q.from)} AND ${dayToDate(q.to)}),0)::int AS before
      FROM "Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId"
      WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(q.from)} AND ${dayToDate(p.to)} ${region("s")}
      GROUP BY p.id, p.name, p.family, p."imageId"
      HAVING COALESCE(SUM(l.quantity) FILTER (WHERE s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)}),0) > 0
      ORDER BY units DESC, p.name`;
    return rows.map((r) => ({ ...r, change: pct(r.units, r.before) }));
  }

  private async bySeller(tx: Tx, p: Period, region: (a: string) => Prisma.Sql) {
    return tx.$queryRaw<
      {
        id: string;
        name: string;
        store: string;
        units: number;
        sales: number;
      }[]
    >`SELECT s."sellerId" AS id, u.name, pd.name AS store, SUM(s.units)::int AS units, COUNT(*)::int AS sales
      FROM "Sale" s JOIN "User" u ON u.id = s."sellerId" JOIN "Pdv" pd ON pd.id = s."pdvId"
      WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)} ${region("s")}
      GROUP BY s."sellerId", u.name, pd.name ORDER BY units DESC, u.name LIMIT 10`;
  }

  /** Days of stock left at the pace of the last four weeks, and stock that does not move. */
  private async stockHealth(tx: Tx, region: (a: string) => Prisma.Sql) {
    const since = dayToDate(addDays(tunisDay(new Date()), -27));
    const rows = await tx.$queryRaw<
      {
        id: string;
        name: string;
        family: string;
        imageId: string | null;
        stock: number;
        sold: number;
      }[]
    >`SELECT p.id, p.name, p.family, p."imageId",
        COALESCE((SELECT SUM(st.quantity) FROM "Stock" st WHERE st."productId" = p.id AND st."locationKind"='PDV' ${region("st")}),0)::int AS stock,
        COALESCE((SELECT SUM(l.quantity) FROM "SaleLine" l JOIN "Sale" s ON s.id = l."saleId" WHERE l."productId" = p.id AND s.status='ACTIVE' AND s.day >= ${since} ${region("s")}),0)::int AS sold
      FROM "Product" p WHERE p.active`;
    const withPace = rows.map((r) => ({
      ...r,
      perDay: Math.round((r.sold / 28) * 10) / 10,
      days: r.sold > 0 ? Math.floor(r.stock / (r.sold / 28)) : null,
    }));
    const runningOut = withPace
      .filter((r) => r.sold > 0 && r.days !== null && r.days <= 7)
      .sort((a, b) => a.days! - b.days!)
      .slice(0, 10);
    const dead = withPace.filter((r) => r.stock > LOW_STOCK && r.sold === 0);
    return {
      runningOut,
      dead: {
        count: dead.length,
        items: dead.sort((a, b) => b.stock - a.stock).slice(0, 8),
      },
    };
  }
}
