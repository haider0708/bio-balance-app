import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { addDays, dayToDate, tunisDay } from "../../core/dates";
import { Database, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";
import { LOW_STOCK } from "./reports.service";

/**
 * What a question about sales is narrowed to: a period and any of region, group, store,
 * seller, product and family. Every number on the dashboards opens one of these, and every
 * row of an answer opens the next, narrower one.
 */
export interface Lens {
  from: string;
  to: string;
  regionId?: string;
  groupId?: string;
  pdvId?: string;
  sellerId?: string;
  productId?: string;
  family?: string;
  sort: Metric;
}

export type Metric = "units" | "sales" | "reward";

interface Period {
  from: string;
  to: string;
}

type Dimension =
  "regions" | "groups" | "stores" | "sellers" | "products" | "families";

interface Measures {
  units: number;
  sales: number;
  rewardMillimes: bigint;
}

const pct = (now: number, before: number) =>
  before === 0 ? null : Math.round(((now - before) * 100) / before);

const length = (p: Period) =>
  Math.round((Date.parse(p.to) - Date.parse(p.from)) / 86400_000) + 1;

/** The hour of a sale on the Tunis clock (sales are stored in UTC). */
const HOUR = Prisma.sql`EXTRACT(HOUR FROM (s."occurredAt" AT TIME ZONE 'UTC') AT TIME ZONE 'Africa/Tunis')::int`;

/** One sale line joined to its sale and product: every measure is a sum over these. */
const LINES = Prisma.sql`"Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId"`;

/** Days of stock left at the pace of the last four weeks. */
const PACE_DAYS = 28;

/**
 * The analytics engine behind the dashboards' numbers: for any lens, the totals against the
 * period before, the curve, when people buy, and who, where and what makes the numbers — down
 * to the stock it leaves and the money it owes. Row-level security keeps a responsable to
 * their region whatever they ask.
 */
@Injectable()
export class AnalyticsService {
  constructor(private readonly db: Database) {}

  overview(actor: Actor, input: Lens) {
    const f = this.scoped(actor, input);
    const previous: Period = {
      from: addDays(f.from, -length(f)),
      to: addDays(f.from, -1),
    };
    const granularity =
      f.from === f.to ? "hour" : length(f) <= 62 ? "day" : "week";
    return this.db.run(actor, async (tx) => {
      const subject = await this.subject(tx, f);
      const dims = this.dimensions(actor, f);
      const [now, before, series, hours, weekdays, quality, silent, ...rest] =
        await Promise.all([
          this.totals(tx, f, f),
          this.totals(tx, f, previous),
          granularity === "hour"
            ? Promise.resolve(null)
            : this.series(tx, f, granularity),
          this.hours(tx, f),
          this.weekdays(tx, f),
          this.quality(tx, f),
          this.silentStores(tx, f),
          ...dims.map((d) => this.breakdown(tx, d, f, previous)),
        ]);
      const breakdowns = Object.fromEntries(
        dims.map((d, i) => [d, rest[i]]),
      ) as Partial<
        Record<Dimension, Awaited<ReturnType<typeof this.breakdown>>>
      >;
      const [stock, money] = await Promise.all([
        this.stock(tx, f),
        actor.role === "ADMIN" ? this.money(tx, f) : Promise.resolve(null),
      ]);
      const insights = this.sentences(
        f,
        now,
        breakdowns,
        hours,
        weekdays,
        stock,
        silent,
      );
      return {
        period: { from: f.from, to: f.to },
        previous,
        today: tunisDay(new Date()),
        granularity,
        sort: f.sort,
        subject,
        totals: {
          ...now,
          unitsPerSale: now.sales
            ? Math.round((now.units * 10) / now.sales) / 10
            : 0,
          silentStores: silent,
          ...quality,
        },
        previousTotals: before,
        change: {
          units: pct(now.units, before.units),
          sales: pct(now.sales, before.sales),
          reward: pct(
            Number(now.rewardMillimes),
            Number(before.rewardMillimes),
          ),
        },
        series:
          series ??
          hours.map((h) => ({
            key: String(h.hour).padStart(2, "0"),
            units: h.units,
            sales: h.sales,
            rewardMillimes: h.rewardMillimes,
          })),
        hours,
        weekdays,
        breakdowns,
        stock,
        money,
        insights,
      };
    });
  }

  /** Every store of the scope, selling or not: the board behind "active points of sale". */
  stores(
    actor: Actor,
    input: { from: string; to: string; regionId?: string; groupId?: string },
  ) {
    const f = this.scoped(actor, { ...input, sort: "units" });
    const previous: Period = {
      from: addDays(f.from, -length(f)),
      to: addDays(f.from, -1),
    };
    return this.db.run(actor, async (tx) => {
      const rows = await tx.$queryRaw<
        {
          id: string;
          name: string;
          city: string;
          status: string;
          regionId: string;
          region: string;
          groupId: string | null;
          group: string | null;
          members: number;
          units: number;
          sales: number;
          rewardMillimes: bigint;
          beforeUnits: number;
          sellers: number;
          lastSaleAt: Date | null;
          low: number;
          out: number;
        }[]
      >`SELECT pd.id, pd.name, pd.city, pd.status::text AS status, r.id AS "regionId", r.name AS region,
          g.id AS "groupId", g.name AS "group",
          (SELECT COUNT(*) FROM "User" u WHERE u."pdvId" = pd.id AND u.role = 'VENDEUR' AND u.status = 'ACTIVE')::int AS members,
          COALESCE(x.units, 0)::int AS units, COALESCE(x.sales, 0)::int AS sales,
          COALESCE(x.reward, 0)::bigint AS "rewardMillimes", COALESCE(x.before, 0)::int AS "beforeUnits",
          COALESCE(x.sellers, 0)::int AS sellers,
          (SELECT MAX(s2."occurredAt") FROM "Sale" s2 WHERE s2."pdvId" = pd.id AND s2.status = 'ACTIVE') AS "lastSaleAt",
          (SELECT COUNT(*) FROM "Stock" st JOIN "Product" p ON p.id = st."productId"
            WHERE st."locationId" = pd.id AND p.active AND st.quantity > 0 AND st.quantity <= ${LOW_STOCK})::int AS low,
          (SELECT COUNT(*) FROM "Stock" st JOIN "Product" p ON p.id = st."productId"
            WHERE st."locationId" = pd.id AND p.active AND st.quantity <= 0)::int AS out
        FROM "Pdv" pd JOIN "Region" r ON r.id = pd."regionId" LEFT JOIN "Group" g ON g.id = pd."groupId"
        LEFT JOIN (
          SELECT s."pdvId",
            SUM(s.units) FILTER (WHERE s.day >= ${dayToDate(f.from)}) AS units,
            COUNT(*) FILTER (WHERE s.day >= ${dayToDate(f.from)}) AS sales,
            SUM(s."rewardMillimes") FILTER (WHERE s.day >= ${dayToDate(f.from)}) AS reward,
            SUM(s.units) FILTER (WHERE s.day < ${dayToDate(f.from)}) AS before,
            COUNT(DISTINCT s."sellerId") FILTER (WHERE s.day >= ${dayToDate(f.from)}) AS sellers
          FROM "Sale" s
          WHERE s.status = 'ACTIVE' AND s.day BETWEEN ${dayToDate(previous.from)} AND ${dayToDate(f.to)}
            ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
          GROUP BY s."pdvId"
        ) x ON x."pdvId" = pd.id
        WHERE pd.status IN ('ACTIVE', 'PENDING', 'SUSPENDED')
          ${f.regionId ? Prisma.sql`AND pd."regionId" = ${f.regionId}::uuid` : Prisma.empty}
          ${f.groupId ? Prisma.sql`AND pd."groupId" = ${f.groupId}::uuid` : Prisma.empty}
        ORDER BY units DESC, pd.name`;
      const active = rows.filter((r) => r.status === "ACTIVE");
      return {
        period: { from: f.from, to: f.to },
        previous,
        today: tunisDay(new Date()),
        summary: {
          total: rows.length,
          active: active.length,
          pending: rows.filter((r) => r.status === "PENDING").length,
          suspended: rows.filter((r) => r.status === "SUSPENDED").length,
          selling: active.filter((r) => r.units > 0).length,
          silent: active.filter((r) => r.units === 0).length,
          lowStock: active.filter((r) => r.low + r.out > 0).length,
        },
        rows: rows.map((r) => ({ ...r, change: pct(r.units, r.beforeUnits) })),
      };
    });
  }

  // ───────────────────────── Scope ─────────────────────────

  /** A responsable always looks at their own region, whatever the request names. */
  private scoped<T extends { regionId?: string }>(actor: Actor, f: T): T {
    requireRule(
      actor.role === "ADMIN" || actor.role === "RESPONSABLE",
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return actor.role === "RESPONSABLE"
      ? { ...f, regionId: actor.regionId ?? undefined }
      : f;
  }

  /** The breakdowns worth showing: never one the lens already fixes to a single row. */
  private dimensions(actor: Actor, f: Lens): Dimension[] {
    const place = !!(f.pdvId || f.sellerId);
    return [
      ...(actor.role === "ADMIN" && !f.regionId && !f.groupId && !place
        ? (["regions"] as const)
        : []),
      ...(!f.groupId && !place ? (["groups"] as const) : []),
      ...(!place ? (["stores"] as const) : []),
      ...(!f.sellerId ? (["sellers"] as const) : []),
      ...(!f.productId ? (["products"] as const) : []),
      ...(!f.productId && !f.family ? (["families"] as const) : []),
    ];
  }

  /** The conditions of a lens over a period, on sales `s`, lines `l` and products `p`. */
  private where(f: Lens, p: Period) {
    return Prisma.sql`s.status = 'ACTIVE' AND s.day BETWEEN ${dayToDate(p.from)} AND ${dayToDate(p.to)}
      ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
      ${f.pdvId ? Prisma.sql`AND s."pdvId" = ${f.pdvId}::uuid` : Prisma.empty}
      ${f.sellerId ? Prisma.sql`AND s."sellerId" = ${f.sellerId}::uuid` : Prisma.empty}
      ${f.groupId ? Prisma.sql`AND s."pdvId" IN (SELECT id FROM "Pdv" WHERE "groupId" = ${f.groupId}::uuid)` : Prisma.empty}
      ${f.productId ? Prisma.sql`AND l."productId" = ${f.productId}::uuid` : Prisma.empty}
      ${f.family ? Prisma.sql`AND p.family = ${f.family}` : Prisma.empty}`;
  }

  /** The names behind the lens's ids, with what is useful to know about each. */
  private async subject(tx: Tx, f: Lens) {
    const [region, group, pdv, seller, product] = await Promise.all([
      f.regionId
        ? tx.region.findUnique({
            where: { id: f.regionId },
            select: { id: true, name: true },
          })
        : null,
      f.groupId
        ? tx.$queryRaw<
            {
              id: string;
              name: string;
              status: string;
              regionId: string;
              region: string;
              stores: number;
            }[]
          >`SELECT g.id, g.name, g.status::text AS status, r.id AS "regionId", r.name AS region,
              (SELECT COUNT(*) FROM "Pdv" pd WHERE pd."groupId" = g.id AND pd.status = 'ACTIVE')::int AS stores
            FROM "Group" g JOIN "Region" r ON r.id = g."regionId" WHERE g.id = ${f.groupId}::uuid`.then(
            (r) => r[0] ?? null,
          )
        : null,
      f.pdvId
        ? tx.$queryRaw<
            {
              id: string;
              name: string;
              city: string;
              address: string;
              phone: string | null;
              status: string;
              createdAt: Date;
              regionId: string;
              region: string;
              groupId: string | null;
              group: string | null;
              members: number;
            }[]
          >`SELECT pd.id, pd.name, pd.city, pd.address, pd.phone, pd.status::text AS status, pd."createdAt",
              r.id AS "regionId", r.name AS region, g.id AS "groupId", g.name AS "group",
              (SELECT COUNT(*) FROM "User" u WHERE u."pdvId" = pd.id AND u.role = 'VENDEUR' AND u.status = 'ACTIVE')::int AS members
            FROM "Pdv" pd JOIN "Region" r ON r.id = pd."regionId" LEFT JOIN "Group" g ON g.id = pd."groupId"
            WHERE pd.id = ${f.pdvId}::uuid`.then((r) => r[0] ?? null)
        : null,
      f.sellerId
        ? tx.$queryRaw<
            {
              id: string;
              name: string;
              phone: string | null;
              email: string;
              status: string;
              createdAt: Date;
              pdvId: string | null;
              pdv: string | null;
              region: string | null;
            }[]
          >`SELECT u.id, u.name, u.phone, u.email, u.status::text AS status, u."createdAt",
              pd.id AS "pdvId", pd.name AS pdv, r.name AS region
            FROM "User" u LEFT JOIN "Pdv" pd ON pd.id = u."pdvId" LEFT JOIN "Region" r ON r.id = u."regionId"
            WHERE u.id = ${f.sellerId}::uuid AND u.role = 'VENDEUR'`.then(
            (r) => r[0] ?? null,
          )
        : null,
      f.productId
        ? tx.product.findUnique({
            where: { id: f.productId },
            select: {
              id: true,
              name: true,
              reference: true,
              family: true,
              range: true,
              packageSize: true,
              imageId: true,
              active: true,
            },
          })
        : null,
    ]);
    // A name that does not resolve is a place the caller cannot see (or that does not exist).
    if (f.regionId && !region) throw notFound("Region");
    if (f.groupId && !group) throw notFound("Group");
    if (f.pdvId && !pdv) throw notFound("Pdv");
    if (f.sellerId && !seller) throw notFound("User");
    if (f.productId && !product) throw notFound("Product");
    return {
      region,
      group,
      pdv,
      seller,
      product,
      family: f.family ?? null,
    };
  }

  // ───────────────────────── Measures ─────────────────────────

  private async totals(tx: Tx, f: Lens, p: Period) {
    const [row] = await tx.$queryRaw<
      (Measures & { stores: number; sellers: number; products: number })[]
    >`SELECT COUNT(DISTINCT s.id)::int AS sales, COALESCE(SUM(l.quantity), 0)::int AS units,
        COALESCE(SUM(l.quantity * l."unitRewardMillimes"), 0)::bigint AS "rewardMillimes",
        COUNT(DISTINCT s."pdvId")::int AS stores, COUNT(DISTINCT s."sellerId")::int AS sellers,
        COUNT(DISTINCT l."productId")::int AS products
      FROM ${LINES} WHERE ${this.where(f, p)}`;
    return {
      sales: row?.sales ?? 0,
      units: row?.units ?? 0,
      rewardMillimes: row?.rewardMillimes ?? 0n,
      stores: row?.stores ?? 0,
      sellers: row?.sellers ?? 0,
      products: row?.products ?? 0,
    };
  }

  /** The curve: one point per day, or per week over a long period, zero-filled. */
  private async series(tx: Tx, f: Lens, granularity: "day" | "week") {
    const key =
      granularity === "day"
        ? Prisma.sql`to_char(s.day, 'YYYY-MM-DD')`
        : Prisma.sql`to_char(date_trunc('week', s.day), 'YYYY-MM-DD')`;
    const rows = await tx.$queryRaw<(Measures & { key: string })[]>`
      SELECT ${key} AS key, COUNT(DISTINCT s.id)::int AS sales, SUM(l.quantity)::int AS units,
        SUM(l.quantity * l."unitRewardMillimes")::bigint AS "rewardMillimes"
      FROM ${LINES} WHERE ${this.where(f, f)} GROUP BY 1`;
    const byKey = new Map(rows.map((r) => [r.key, r]));
    const points: (Measures & { key: string })[] = [];
    // Weeks start on Monday, like date_trunc('week').
    let start = f.from;
    if (granularity === "week") {
      const dow = new Date(`${f.from}T00:00:00Z`).getUTCDay();
      start = addDays(f.from, -((dow + 6) % 7));
    }
    const step = granularity === "day" ? 1 : 7;
    for (let d = start; d <= f.to; d = addDays(d, step))
      points.push(
        byKey.get(d) ?? { key: d, units: 0, sales: 0, rewardMillimes: 0n },
      );
    return points;
  }

  /** When in the day people buy, on the Tunis clock. */
  private async hours(tx: Tx, f: Lens) {
    const rows = await tx.$queryRaw<(Measures & { hour: number })[]>`
      SELECT ${HOUR} AS hour, COUNT(DISTINCT s.id)::int AS sales, SUM(l.quantity)::int AS units,
        SUM(l.quantity * l."unitRewardMillimes")::bigint AS "rewardMillimes"
      FROM ${LINES} WHERE ${this.where(f, f)} GROUP BY 1`;
    const byHour = new Map(rows.map((r) => [r.hour, r]));
    return Array.from(
      { length: 24 },
      (_, hour) =>
        byHour.get(hour) ?? { hour, units: 0, sales: 0, rewardMillimes: 0n },
    );
  }

  /** Which days of the week sell: 0 is Sunday. */
  private async weekdays(tx: Tx, f: Lens) {
    const rows = await tx.$queryRaw<{ weekday: number; units: number }[]>`
      SELECT EXTRACT(DOW FROM s.day)::int AS weekday, SUM(l.quantity)::int AS units
      FROM ${LINES} WHERE ${this.where(f, f)} GROUP BY 1`;
    const byDay = new Map(rows.map((r) => [r.weekday, r.units]));
    return Array.from({ length: 7 }, (_, weekday) => ({
      weekday,
      units: byDay.get(weekday) ?? 0,
    }));
  }

  /**
   * What happened to the sales after the fact: voided, corrected, or recorded offline and sent
   * later. Counted on whole sales, so a product or family lens leaves them out.
   */
  private async quality(tx: Tx, f: Lens) {
    if (f.productId || f.family)
      return { voided: null, corrected: null, late: null };
    const [row] = await tx.$queryRaw<
      { voided: number; corrected: number; late: number }[]
    >`SELECT COUNT(*) FILTER (WHERE s.status = 'VOIDED')::int AS voided,
        COUNT(*) FILTER (WHERE s.status = 'ACTIVE' AND s.version > 1)::int AS corrected,
        COUNT(*) FILTER (WHERE s."createdAt" - s."occurredAt" > interval '1 hour')::int AS late
      FROM "Sale" s
      WHERE s.day BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)}
        ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
        ${f.pdvId ? Prisma.sql`AND s."pdvId" = ${f.pdvId}::uuid` : Prisma.empty}
        ${f.sellerId ? Prisma.sql`AND s."sellerId" = ${f.sellerId}::uuid` : Prisma.empty}
        ${f.groupId ? Prisma.sql`AND s."pdvId" IN (SELECT id FROM "Pdv" WHERE "groupId" = ${f.groupId}::uuid)` : Prisma.empty}`;
    return {
      voided: row?.voided ?? 0,
      corrected: row?.corrected ?? 0,
      late: row?.late ?? 0,
    };
  }

  /** Active stores of the scope that sold nothing in the period (none for a store, seller or product lens). */
  private async silentStores(tx: Tx, f: Lens) {
    if (f.pdvId || f.sellerId || f.productId || f.family) return null;
    const [row] = await tx.$queryRaw<{ count: number }[]>`
      SELECT COUNT(*)::int AS count FROM "Pdv" pd
      WHERE pd.status = 'ACTIVE'
        ${f.regionId ? Prisma.sql`AND pd."regionId" = ${f.regionId}::uuid` : Prisma.empty}
        ${f.groupId ? Prisma.sql`AND pd."groupId" = ${f.groupId}::uuid` : Prisma.empty}
        AND NOT EXISTS (SELECT 1 FROM "Sale" s WHERE s."pdvId" = pd.id AND s.status = 'ACTIVE'
          AND s.day BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)})`;
    return row?.count ?? 0;
  }

  /**
   * One ranking: the rows of a dimension with their three measures now and in the period before,
   * ordered by the measure the person looks at.
   */
  private async breakdown(tx: Tx, dim: Dimension, f: Lens, previous: Period) {
    const d = {
      regions: {
        key: Prisma.sql`s."regionId"::text`,
        name: Prisma.sql`r.name`,
        sub: Prisma.sql`NULL::text`,
        image: Prisma.sql`NULL::text`,
        joins: Prisma.sql`JOIN "Region" r ON r.id = s."regionId"`,
        group: [Prisma.sql`s."regionId"`, Prisma.sql`r.name`],
      },
      groups: {
        key: Prisma.sql`g.id::text`,
        name: Prisma.sql`g.name`,
        sub: Prisma.sql`gr.name`,
        image: Prisma.sql`NULL::text`,
        joins: Prisma.sql`JOIN "Pdv" pd ON pd.id = s."pdvId" JOIN "Group" g ON g.id = pd."groupId" JOIN "Region" gr ON gr.id = g."regionId"`,
        group: [Prisma.sql`g.id`, Prisma.sql`g.name`, Prisma.sql`gr.name`],
      },
      stores: {
        key: Prisma.sql`s."pdvId"::text`,
        name: Prisma.sql`pd.name`,
        sub: Prisma.sql`pd.city`,
        image: Prisma.sql`NULL::text`,
        joins: Prisma.sql`JOIN "Pdv" pd ON pd.id = s."pdvId"`,
        group: [
          Prisma.sql`s."pdvId"`,
          Prisma.sql`pd.name`,
          Prisma.sql`pd.city`,
        ],
      },
      sellers: {
        key: Prisma.sql`s."sellerId"::text`,
        name: Prisma.sql`u.name`,
        sub: Prisma.sql`up.name`,
        image: Prisma.sql`NULL::text`,
        joins: Prisma.sql`JOIN "User" u ON u.id = s."sellerId" LEFT JOIN "Pdv" up ON up.id = u."pdvId"`,
        group: [
          Prisma.sql`s."sellerId"`,
          Prisma.sql`u.name`,
          Prisma.sql`up.name`,
        ],
      },
      products: {
        key: Prisma.sql`l."productId"::text`,
        name: Prisma.sql`p.name`,
        sub: Prisma.sql`p.family`,
        image: Prisma.sql`p."imageId"::text`,
        joins: Prisma.empty,
        group: [
          Prisma.sql`l."productId"`,
          Prisma.sql`p.name`,
          Prisma.sql`p.family`,
          Prisma.sql`p."imageId"`,
        ],
      },
      families: {
        key: Prisma.sql`p.family`,
        name: Prisma.sql`p.family`,
        sub: Prisma.sql`NULL::text`,
        image: Prisma.sql`NULL::text`,
        joins: Prisma.empty,
        group: [Prisma.sql`p.family`],
      },
    }[dim];
    const now = Prisma.sql`s.day >= ${dayToDate(f.from)}`;
    const was = Prisma.sql`s.day < ${dayToDate(f.from)}`;
    const order = {
      units: Prisma.sql`units`,
      sales: Prisma.sql`sales`,
      reward: Prisma.sql`"rewardMillimes"`,
    }[f.sort];
    const rows = await tx.$queryRaw<
      {
        id: string;
        name: string;
        sub: string | null;
        imageId: string | null;
        units: number;
        sales: number;
        rewardMillimes: bigint;
        beforeUnits: number;
        beforeSales: number;
        beforeRewardMillimes: bigint;
        lastAt: Date | null;
      }[]
    >`SELECT ${d.key} AS id, ${d.name} AS name, ${d.sub} AS sub, ${d.image} AS "imageId",
        COALESCE(SUM(l.quantity) FILTER (WHERE ${now}), 0)::int AS units,
        COUNT(DISTINCT s.id) FILTER (WHERE ${now})::int AS sales,
        COALESCE(SUM(l.quantity * l."unitRewardMillimes") FILTER (WHERE ${now}), 0)::bigint AS "rewardMillimes",
        COALESCE(SUM(l.quantity) FILTER (WHERE ${was}), 0)::int AS "beforeUnits",
        COUNT(DISTINCT s.id) FILTER (WHERE ${was})::int AS "beforeSales",
        COALESCE(SUM(l.quantity * l."unitRewardMillimes") FILTER (WHERE ${was}), 0)::bigint AS "beforeRewardMillimes",
        MAX(s."occurredAt") FILTER (WHERE ${now}) AS "lastAt"
      FROM ${LINES} ${d.joins}
      WHERE ${this.where(f, { from: previous.from, to: f.to })}
      GROUP BY ${Prisma.join(d.group)}
      HAVING COALESCE(SUM(l.quantity) FILTER (WHERE ${now}), 0) > 0
      ORDER BY ${order} DESC, name LIMIT 100`;
    return rows;
  }

  // ───────────────────────── Stock and money ─────────────────────────

  /**
   * The stock the sales leave: for a product, where it sits; for a store, what it holds; else the
   * products about to run out and those that do not move. Days left use the pace of four weeks.
   */
  private async stock(tx: Tx, f: Lens) {
    const since = dayToDate(addDays(tunisDay(new Date()), -(PACE_DAYS - 1)));
    const pace = <T extends { quantity: number; sold: number }>(r: T) => ({
      ...r,
      perDay: Math.round((r.sold / PACE_DAYS) * 10) / 10,
      daysLeft:
        r.sold > 0
          ? Math.max(0, Math.floor(r.quantity / (r.sold / PACE_DAYS)))
          : null,
    });
    if (f.sellerId) return null;
    if (f.productId) {
      const rows = await tx.$queryRaw<
        {
          locationId: string;
          kind: string;
          name: string;
          city: string;
          region: string | null;
          quantity: number;
          sold: number;
        }[]
      >`SELECT st."locationId", st."locationKind"::text AS kind, COALESCE(pd.name, d.name) AS name,
          COALESCE(pd.city, d.city) AS city, r.name AS region, st.quantity,
          COALESCE((SELECT SUM(l.quantity) FROM "SaleLine" l JOIN "Sale" s ON s.id = l."saleId"
            WHERE l."productId" = st."productId" AND s."pdvId" = st."locationId" AND s.status = 'ACTIVE' AND s.day >= ${since}), 0)::int AS sold
        FROM "Stock" st LEFT JOIN "Pdv" pd ON pd.id = st."locationId" LEFT JOIN "Depot" d ON d.id = st."locationId"
        LEFT JOIN "Region" r ON r.id = st."regionId"
        WHERE st."productId" = ${f.productId}::uuid
          ${f.regionId ? Prisma.sql`AND st."regionId" = ${f.regionId}::uuid` : Prisma.empty}
          ${f.groupId ? Prisma.sql`AND pd."groupId" = ${f.groupId}::uuid` : Prisma.empty}
          ${f.pdvId ? Prisma.sql`AND st."locationId" = ${f.pdvId}::uuid` : Prisma.empty}
        ORDER BY st."locationKind", st.quantity, name`;
      const places = rows.map(pace);
      return {
        kind: "product" as const,
        total: places
          .filter((r) => r.kind === "PDV")
          .reduce((t, r) => t + r.quantity, 0),
        inGrossistes: places
          .filter((r) => r.kind === "DEPOT")
          .reduce((t, r) => t + r.quantity, 0),
        rows: places,
      };
    }
    if (f.pdvId) {
      const rows = await tx.$queryRaw<
        {
          productId: string;
          name: string;
          family: string;
          imageId: string | null;
          quantity: number;
          sold: number;
        }[]
      >`SELECT st."productId", p.name, p.family, p."imageId", st.quantity,
          COALESCE((SELECT SUM(l.quantity) FROM "SaleLine" l JOIN "Sale" s ON s.id = l."saleId"
            WHERE l."productId" = st."productId" AND s."pdvId" = st."locationId" AND s.status = 'ACTIVE' AND s.day >= ${since}), 0)::int AS sold
        FROM "Stock" st JOIN "Product" p ON p.id = st."productId"
        WHERE st."locationId" = ${f.pdvId}::uuid AND p.active
          ${f.family ? Prisma.sql`AND p.family = ${f.family}` : Prisma.empty}
        ORDER BY st.quantity, p.name`;
      const items = rows.map(pace);
      return {
        kind: "store" as const,
        total: items.reduce((t, r) => t + r.quantity, 0),
        rows: items.sort(
          (a, b) =>
            (a.daysLeft ?? Number.MAX_SAFE_INTEGER) -
              (b.daysLeft ?? Number.MAX_SAFE_INTEGER) ||
            a.quantity - b.quantity,
        ),
      };
    }
    // The scope's points of sale together, product by product.
    const rows = await tx.$queryRaw<
      {
        id: string;
        name: string;
        family: string;
        imageId: string | null;
        quantity: number;
        sold: number;
      }[]
    >`SELECT p.id, p.name, p.family, p."imageId",
        COALESCE((SELECT SUM(st.quantity) FROM "Stock" st JOIN "Pdv" pd ON pd.id = st."locationId"
          WHERE st."productId" = p.id
            ${f.regionId ? Prisma.sql`AND st."regionId" = ${f.regionId}::uuid` : Prisma.empty}
            ${f.groupId ? Prisma.sql`AND pd."groupId" = ${f.groupId}::uuid` : Prisma.empty}), 0)::int AS quantity,
        COALESCE((SELECT SUM(l.quantity) FROM "SaleLine" l JOIN "Sale" s ON s.id = l."saleId"
          WHERE l."productId" = p.id AND s.status = 'ACTIVE' AND s.day >= ${since}
            ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
            ${f.groupId ? Prisma.sql`AND s."pdvId" IN (SELECT id FROM "Pdv" WHERE "groupId" = ${f.groupId}::uuid)` : Prisma.empty}), 0)::int AS sold
      FROM "Product" p WHERE p.active ${f.family ? Prisma.sql`AND p.family = ${f.family}` : Prisma.empty}`;
    const all = rows.map(pace);
    const dead = all.filter((r) => r.quantity > LOW_STOCK && r.sold === 0);
    return {
      kind: "network" as const,
      total: all.reduce((t, r) => t + r.quantity, 0),
      runningOut: all
        .filter((r) => r.daysLeft !== null && r.daysLeft <= 7)
        .sort((a, b) => a.daysLeft! - b.daysLeft!)
        .slice(0, 12),
      dead: {
        count: dead.length,
        items: dead.sort((a, b) => b.quantity - a.quantity).slice(0, 12),
      },
    };
  }

  /**
   * The rewards in money: what the team members of the scope are owed, what waits to be paid and
   * what was approved in the period. Only the admin handles payouts, so only the admin sees it.
   */
  private async money(tx: Tx, f: Lens) {
    if (f.productId || f.family) return null;
    const people = f.sellerId
      ? Prisma.sql`u.id = ${f.sellerId}::uuid`
      : Prisma.sql`u.role = 'VENDEUR'
          ${f.regionId ? Prisma.sql`AND u."regionId" = ${f.regionId}::uuid` : Prisma.empty}
          ${f.pdvId ? Prisma.sql`AND u."pdvId" = ${f.pdvId}::uuid` : Prisma.empty}
          ${f.groupId ? Prisma.sql`AND u."pdvId" IN (SELECT id FROM "Pdv" WHERE "groupId" = ${f.groupId}::uuid)` : Prisma.empty}`;
    const paidDay = Prisma.sql`((q."decidedAt" AT TIME ZONE 'UTC') AT TIME ZONE 'Africa/Tunis')::date`;
    const [row] = await tx.$queryRaw<
      {
        owed: bigint;
        pendingCount: number;
        pendingAmount: bigint;
        paidCount: number;
        paidAmount: bigint;
      }[]
    >`WITH people AS (SELECT u.id FROM "User" u WHERE ${people})
      SELECT
        COALESCE((SELECT SUM(w."amountMillimes") FROM "WalletEntry" w WHERE w."userId" IN (SELECT id FROM people)), 0)::bigint AS owed,
        (SELECT COUNT(*) FROM "PayoutRequest" q WHERE q.status = 'PENDING' AND q."userId" IN (SELECT id FROM people))::int AS "pendingCount",
        COALESCE((SELECT SUM(q."amountMillimes") FROM "PayoutRequest" q WHERE q.status = 'PENDING' AND q."userId" IN (SELECT id FROM people)), 0)::bigint AS "pendingAmount",
        (SELECT COUNT(*) FROM "PayoutRequest" q WHERE q.status = 'APPROVED' AND q."userId" IN (SELECT id FROM people)
          AND ${paidDay} BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)})::int AS "paidCount",
        COALESCE((SELECT SUM(q."amountMillimes") FROM "PayoutRequest" q WHERE q.status = 'APPROVED' AND q."userId" IN (SELECT id FROM people)
          AND ${paidDay} BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)}), 0)::bigint AS "paidAmount"`;
    return {
      owedMillimes: row?.owed ?? 0n,
      pending: {
        count: row?.pendingCount ?? 0,
        amountMillimes: row?.pendingAmount ?? 0n,
      },
      paid: {
        count: row?.paidCount ?? 0,
        amountMillimes: row?.paidAmount ?? 0n,
      },
    };
  }

  // ───────────────────────── Sentences ─────────────────────────

  /** What the numbers say, as keys the phone words in its own language. */
  private sentences(
    f: Lens,
    now: Measures,
    b: Partial<Record<Dimension, Awaited<ReturnType<typeof this.breakdown>>>>,
    hours: (Measures & { hour: number })[],
    weekdays: { weekday: number; units: number }[],
    stock: Awaited<ReturnType<typeof this.stock>>,
    silent: number | null,
  ) {
    const out: { key: string; params: Record<string, unknown> }[] = [];
    if (now.units === 0) return out;
    const share = (units: number) => Math.round((units * 100) / now.units);
    // Rankings follow the measure on screen; the sentences speak of units.
    const most = <T extends { units: number }>(rows?: T[]) =>
      rows?.reduce<T | undefined>(
        (m, r) => (!m || r.units > m.units ? r : m),
        undefined,
      );
    const family = most(b.families);
    if (family && b.families!.length > 1)
      out.push({
        key: "TOP_FAMILY",
        params: {
          family: family.name,
          share: share(family.units),
          change: pct(family.units, family.beforeUnits),
        },
      });
    const stores = (b.stores ?? []).filter((s) => s.beforeUnits >= 10);
    const falling = stores
      .map((s) => ({ ...s, change: pct(s.units, s.beforeUnits)! }))
      .filter((s) => s.change <= -20)
      .sort((x, y) => x.change - y.change)[0];
    if (falling)
      out.push({
        key: "STORE_DOWN",
        params: { store: falling.name, change: falling.change },
      });
    const rising = stores
      .map((s) => ({ ...s, change: pct(s.units, s.beforeUnits)! }))
      .filter((s) => s.change >= 20)
      .sort((x, y) => y.change - x.change)[0];
    if (rising)
      out.push({
        key: "STORE_UP",
        params: { store: rising.name, change: rising.change },
      });
    if (silent) out.push({ key: "SILENT_STORES", params: { count: silent } });
    if (stock?.kind === "network" && stock.runningOut.length)
      out.push({
        key: "RUNNING_OUT",
        params: { count: stock.runningOut.length, days: 7 },
      });
    if (stock?.kind === "network" && stock.dead.count)
      out.push({ key: "DEAD_STOCK", params: { count: stock.dead.count } });
    const hour = hours.reduce((m, h) => (h.units > m.units ? h : m));
    if (hour.units > 0)
      out.push({
        key: "BEST_HOUR",
        params: { hour: hour.hour, share: share(hour.units) },
      });
    if (length(f) >= 7) {
      const day = weekdays.reduce((m, d) => (d.units > m.units ? d : m));
      out.push({
        key: "BEST_WEEKDAY",
        params: { weekday: day.weekday, share: share(day.units) },
      });
    }
    const seller = most(b.sellers);
    if (seller && b.sellers!.length > 1)
      out.push({
        key: "TOP_SELLER",
        params: { name: seller.name, units: seller.units },
      });
    out.push({
      key: "REWARD_PER_UNIT",
      params: {
        amountMillimes: Math.round(Number(now.rewardMillimes) / now.units),
      },
    });
    return out;
  }
}
