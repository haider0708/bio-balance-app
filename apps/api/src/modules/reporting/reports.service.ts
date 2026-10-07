import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { addDays, dayToDate } from "../../core/dates";
import { Database, type Tx } from "../../core/database";
import { requireRule } from "../../core/errors";
import { decodeCursor, page } from "../../core/pagination";

export type GroupBy =
  "day" | "region" | "pdv" | "seller" | "product" | "family";
export interface SalesFilter {
  from: string;
  to: string;
  groupBy: GroupBy;
  regionId?: string;
  pdvId?: string;
  sellerId?: string;
  productId?: string;
  family?: string;
}

export const LOW_STOCK = 5;

@Injectable()
export class ReportsService {
  constructor(private readonly db: Database) {}

  /** Units sold and rewards earned over a period, grouped as asked. */
  sales(actor: Actor, f: SalesFilter) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    // A responsable's reports are their region's: say so, so the database can use its indexes.
    if (actor.role === "RESPONSABLE" && actor.regionId && !f.regionId)
      f = { ...f, regionId: actor.regionId };
    return this.db.run(actor, async (tx) => {
      const rows = await this.rows(tx, f);
      const sum = (list: Row[]) =>
        list.reduce(
          (t, r) => ({
            sales: t.sales + r.sales,
            units: t.units + r.units,
            rewardMillimes: t.rewardMillimes + r.rewardMillimes,
          }),
          { sales: 0, units: 0, rewardMillimes: 0n },
        );
      // The period just before, as long as this one, to show whether things go up or down.
      const length = daysBetween(f.from, f.to) + 1;
      const previous = sum(
        await this.rows(tx, {
          ...f,
          groupBy: "day",
          from: addDays(f.from, -length),
          to: addDays(f.from, -1),
        }),
      );
      const perDay = new Map(
        (f.groupBy === "day"
          ? rows
          : await this.rows(tx, { ...f, groupBy: "day" })
        ).map((r) => [r.key, r]),
      );
      const trend: { day: string; units: number; sales: number }[] = [];
      for (let d = f.from; d <= f.to && trend.length < 400; d = addDays(d, 1))
        trend.push({
          day: d,
          units: perDay.get(d)?.units ?? 0,
          sales: perDay.get(d)?.sales ?? 0,
        });
      // Product rows carry the picture, so the app can show what was sold.
      const images =
        f.groupBy === "product"
          ? new Map(
              (
                await tx.product.findMany({
                  where: { id: { in: rows.map((r) => r.key) } },
                  select: { id: true, imageId: true },
                })
              ).map((p) => [p.id, p.imageId]),
            )
          : null;
      return {
        rows: rows.map((r) => ({ ...r, imageId: images?.get(r.key) ?? null })),
        totals: sum(rows),
        previous,
        trend,
      };
    });
  }

  private async rows(tx: Tx, f: SalesFilter): Promise<Row[]> {
    const byLine =
      f.groupBy === "product" ||
      f.groupBy === "family" ||
      !!f.productId ||
      !!f.family;
    const where = Prisma.sql`s.status = 'ACTIVE' AND s.day BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)}
        ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
        ${f.pdvId ? Prisma.sql`AND s."pdvId" = ${f.pdvId}::uuid` : Prisma.empty}
        ${f.sellerId ? Prisma.sql`AND s."sellerId" = ${f.sellerId}::uuid` : Prisma.empty}
        ${f.productId ? Prisma.sql`AND l."productId" = ${f.productId}::uuid` : Prisma.empty}
        ${f.family ? Prisma.sql`AND p.family = ${f.family}` : Prisma.empty}`;
    const key = {
      day: Prisma.sql`to_char(s.day,'YYYY-MM-DD')`,
      region: Prisma.sql`r.id::text`,
      pdv: Prisma.sql`s."pdvId"::text`,
      seller: Prisma.sql`s."sellerId"::text`,
      product: Prisma.sql`l."productId"::text`,
      family: Prisma.sql`p.family`,
    }[f.groupBy];
    const label = {
      day: Prisma.sql`to_char(s.day,'YYYY-MM-DD')`,
      region: Prisma.sql`r.name`,
      pdv: Prisma.sql`pd.name`,
      seller: Prisma.sql`u.name`,
      product: Prisma.sql`p.name`,
      family: Prisma.sql`p.family`,
    }[f.groupBy];
    // Only join what the grouping shows: each extra table is checked row by row by the database.
    const joins = {
      region: Prisma.sql`JOIN "Region" r ON r.id = s."regionId"`,
      pdv: Prisma.sql`JOIN "Pdv" pd ON pd.id = s."pdvId"`,
      seller: Prisma.sql`JOIN "User" u ON u.id = s."sellerId"`,
      day: Prisma.empty,
      product: Prisma.empty,
      family: Prisma.empty,
    }[f.groupBy];
    return byLine
      ? await tx.$queryRaw<
          Row[]
        >`SELECT ${key} AS key, ${label} AS label, COUNT(DISTINCT s.id)::int AS sales,
            COALESCE(SUM(l.quantity),0)::int AS units, COALESCE(SUM(l.quantity * l."unitRewardMillimes"),0)::bigint AS "rewardMillimes"
          FROM "Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId" ${joins}
          WHERE ${where} GROUP BY 1, 2 ORDER BY ${f.groupBy === "day" ? Prisma.sql`1` : Prisma.sql`units DESC, 2`}`
      : await tx.$queryRaw<
          Row[]
        >`SELECT ${key} AS key, ${label} AS label, COUNT(*)::int AS sales,
            COALESCE(SUM(s.units),0)::int AS units, COALESCE(SUM(s."rewardMillimes"),0)::bigint AS "rewardMillimes"
          FROM "Sale" s ${joins}
          WHERE ${where} GROUP BY 1, 2 ORDER BY ${f.groupBy === "day" ? Prisma.sql`1` : Prisma.sql`units DESC, 2`}`;
  }

  /** One line per product sold, for spreadsheets. */
  async salesCsv(
    actor: Actor,
    f: { from: string; to: string; regionId?: string; pdvId?: string },
  ) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    const rows = await this.db.run(
      actor,
      (tx) => tx.$queryRaw<
        {
          occurredAt: Date;
          region: string;
          pdv: string;
          seller: string;
          product: string;
          family: string;
          quantity: number;
          reward: bigint;
        }[]
      >`SELECT s."occurredAt", r.name AS region, pd.name AS pdv, u.name AS seller, p.name AS product, p.family, l.quantity,
        (l.quantity * l."unitRewardMillimes")::bigint AS reward
      FROM "Sale" s JOIN "SaleLine" l ON l."saleId" = s.id JOIN "Product" p ON p.id = l."productId"
      JOIN "Region" r ON r.id = s."regionId" JOIN "Pdv" pd ON pd.id = s."pdvId" JOIN "User" u ON u.id = s."sellerId"
      WHERE s.status = 'ACTIVE' AND s.day BETWEEN ${dayToDate(f.from)} AND ${dayToDate(f.to)}
        ${f.regionId ? Prisma.sql`AND s."regionId" = ${f.regionId}::uuid` : Prisma.empty}
        ${f.pdvId ? Prisma.sql`AND s."pdvId" = ${f.pdvId}::uuid` : Prisma.empty}
      ORDER BY s."occurredAt", s.id LIMIT 100000`,
    );
    const cell = (v: string | number | bigint) => {
      let text = String(v);
      // Spreadsheets run text that starts with these characters as a formula.
      if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
      return /[",\n;]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
    };
    const lines = [
      "Date,Time,Region,Point of sale,Seller,Product,Family,Quantity,Reward (TND)",
    ];
    for (const r of rows) {
      const iso = r.occurredAt.toISOString();
      lines.push(
        [
          iso.slice(0, 10),
          iso.slice(11, 16),
          r.region,
          r.pdv,
          r.seller,
          r.product,
          r.family,
          r.quantity,
          (Number(r.reward) / 1000).toFixed(3),
        ]
          .map(cell)
          .join(","),
      );
    }
    return "﻿" + lines.join("\r\n") + "\r\n";
  }

  /** Stock per point of sale, with how many products are low or below zero. */
  stock(actor: Actor, filter: { regionId?: string }) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.$queryRaw<
        {
          id: string;
          name: string;
          kind: string;
          region: string | null;
          units: bigint;
          products: number;
          low: number;
          negative: number;
        }[]
      >`SELECT s."locationId" AS id, COALESCE(p.name, d.name) AS name, s."locationKind"::text AS kind, r.name AS region,
          SUM(s.quantity)::bigint AS units, COUNT(*)::int AS products,
          COUNT(*) FILTER (WHERE s.quantity >= 0 AND s.quantity <= ${LOW_STOCK})::int AS low,
          COUNT(*) FILTER (WHERE s.quantity < 0)::int AS negative
        FROM "Stock" s LEFT JOIN "Pdv" p ON p.id = s."locationId" LEFT JOIN "Depot" d ON d.id = s."locationId"
        LEFT JOIN "Region" r ON r.id = s."regionId"
        WHERE ${filter.regionId ? Prisma.sql`s."regionId" = ${filter.regionId}::uuid` : Prisma.sql`TRUE`}
        GROUP BY s."locationId", p.name, d.name, s."locationKind", r.name ORDER BY name`;
      return rows;
    });
  }

  /** The products that need attention: below zero or nearly out. */
  stockAttention(actor: Actor, filter: { regionId?: string }) {
    requireRule(
      ["ADMIN", "RESPONSABLE"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(
      actor,
      (tx) =>
        tx.$queryRaw<
          {
            locationId: string;
            place: string;
            kind: string;
            productId: string;
            product: string;
            family: string;
            quantity: number;
          }[]
        >`
        SELECT s."locationId", COALESCE(p.name, d.name) AS place, s."locationKind"::text AS kind, s."productId", pr.name AS product, pr.family, s.quantity
        FROM "Stock" s JOIN "Product" pr ON pr.id = s."productId"
        LEFT JOIN "Pdv" p ON p.id = s."locationId" LEFT JOIN "Depot" d ON d.id = s."locationId"
        WHERE s.quantity <= ${LOW_STOCK} AND pr.active
          ${filter.regionId ? Prisma.sql`AND s."regionId" = ${filter.regionId}::uuid` : Prisma.empty}
        ORDER BY s.quantity, place, product LIMIT 200`,
    );
  }

  /** The history of changes: who did what. */
  audit(
    actor: Actor,
    filter: {
      entity?: string;
      entityId?: string;
      actorId?: string;
      regionId?: string;
      limit: number;
      cursor?: string;
    },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin reads the audit log.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const after = decodeCursor(filter.cursor);
      const rows = await tx.auditEntry.findMany({
        where: {
          ...(filter.entity && { entity: filter.entity }),
          ...(filter.entityId && { entityId: filter.entityId }),
          ...(filter.actorId && { actorId: filter.actorId }),
          ...(filter.regionId && { regionId: filter.regionId }),
          ...(after && {
            OR: [
              { createdAt: { lt: after.createdAt } },
              { createdAt: after.createdAt, id: { lt: after.id } },
            ],
          }),
        },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: filter.limit + 1,
      });
      const result = page(rows, filter.limit);
      const actors = await tx.user.findMany({
        where: {
          id: {
            in: result.items
              .map((r) => r.actorId)
              .filter((x): x is string => !!x),
          },
        },
        select: { id: true, name: true, role: true },
      });
      const who = new Map(actors.map((a) => [a.id, a]));
      return {
        nextCursor: result.nextCursor,
        items: result.items.map((r) => ({
          ...r,
          actor: r.actorId ? (who.get(r.actorId) ?? null) : null,
        })),
      };
    });
  }
}

interface Row {
  key: string;
  label: string;
  sales: number;
  units: number;
  rewardMillimes: bigint;
}

const daysBetween = (from: string, to: string) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86400_000);
