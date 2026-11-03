import { Injectable } from "@nestjs/common";
import { TEAM_ROLES } from "../../core/roles";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database } from "../../core/database";
import { addDays, tunisDay } from "../../core/dates";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, responsableIds } from "../../core/notifier";
import { LOW_STOCK } from "../reporting/reports.service";

/** Asking the same para again within this time is refused: one nudge, then wait for the answer. */
const ASK_AGAIN_MS = 30 * 60_000;

interface ParaRow {
  id: string;
  name: string;
  address: string;
  city: string;
  phone: string | null;
  regionId: string;
  region: string;
  groupId: string | null;
  groupName: string | null;
  low: number;
  out: number;
  units: number;
  products: number;
  sold7: number;
  open: number;
}

/**
 * The order manager's view of the network: every para with its stock, what is getting low, how fast
 * it sells and what is on order, and a way to ask a para whether it needs anything. It carries no
 * money (no rewards, wallets or payouts), and never shows the test region. Reads are trusted
 * server work for a role that may see the whole network; the admin may use it too.
 */
@Injectable()
export class OrdersService {
  constructor(private readonly db: Database) {}

  private allowed(actor: Actor) {
    requireRule(
      actor.role === "ORDERS" || actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the order manager or the admin.",
      403,
    );
  }

  /** What each para holds and sells, one row per active para. */
  private async rows(filter: {
    regionId?: string;
    groupId?: string;
    pdvId?: string;
    q?: string;
  }) {
    const since = addDays(tunisDay(new Date()), -7);
    return this.db.run(
      "SYSTEM",
      (tx) =>
        tx.$queryRaw<ParaRow[]>`
        SELECT p.id, p.name, p.address, p.city, p.phone, p."regionId", r.name AS region,
          p."groupId", g.name AS "groupName",
          COALESCE(s.low, 0) AS low, COALESCE(s."out", 0) AS "out",
          COALESCE(s.units, 0) AS units, COALESCE(s.products, 0) AS products,
          COALESCE(v.sold7, 0) AS sold7, COALESCE(o.open, 0) AS open
        FROM "Pdv" p
        JOIN "Region" r ON r.id = p."regionId"
        LEFT JOIN "Group" g ON g.id = p."groupId"
        LEFT JOIN (
          SELECT "locationId",
            COUNT(*) FILTER (WHERE quantity > 0 AND quantity <= ${LOW_STOCK})::int AS low,
            COUNT(*) FILTER (WHERE quantity <= 0)::int AS "out",
            COALESCE(SUM(GREATEST(quantity, 0)), 0)::int AS units,
            COUNT(*)::int AS products
          FROM "Stock" WHERE "locationKind" = 'PDV' GROUP BY "locationId"
        ) s ON s."locationId" = p.id
        LEFT JOIN (
          SELECT "pdvId", SUM(units)::int AS sold7 FROM "Sale"
          WHERE status = 'ACTIVE' AND day >= ${since}::date GROUP BY "pdvId"
        ) v ON v."pdvId" = p.id
        LEFT JOIN (
          SELECT "destId", COUNT(*)::int AS open FROM "RestockOrder"
          WHERE status IN ('REQUESTED', 'ASSIGNED', 'SHIPPED', 'RECEIVED') GROUP BY "destId"
        ) o ON o."destId" = p.id
        WHERE NOT r.sandbox AND p.status = 'ACTIVE'
          AND (${filter.regionId ?? null}::uuid IS NULL OR p."regionId" = ${filter.regionId ?? null}::uuid)
          AND (${filter.groupId ?? null}::uuid IS NULL OR p."groupId" = ${filter.groupId ?? null}::uuid)
          AND (${filter.pdvId ?? null}::uuid IS NULL OR p.id = ${filter.pdvId ?? null}::uuid)
          AND (${filter.q ?? null}::text IS NULL OR p.name ILIKE '%' || ${filter.q ?? null}::text || '%'
               OR p.city ILIKE '%' || ${filter.q ?? null}::text || '%')
        ORDER BY (COALESCE(s.low, 0) + COALESCE(s."out", 0)) DESC, p.name`,
    );
  }

  private present(r: ParaRow) {
    return {
      id: r.id,
      name: r.name,
      address: r.address,
      city: r.city,
      phone: r.phone,
      region: { id: r.regionId, name: r.region },
      group: r.groupId ? { id: r.groupId, name: r.groupName ?? "" } : null,
      stock: {
        products: r.products,
        units: r.units,
        low: r.low,
        out: r.out,
      },
      sold7Days: r.sold7,
      openOrders: r.open,
    };
  }

  async paras(
    actor: Actor,
    filter: { regionId?: string; groupId?: string; q?: string; low?: boolean },
  ) {
    this.allowed(actor);
    const rows = await this.rows(filter);
    return (filter.low ? rows.filter((r) => r.low + r.out > 0) : rows).map(
      (r) => this.present(r),
    );
  }

  /** The home of the role: what waits, and which paras are getting low. */
  async overview(actor: Actor) {
    this.allowed(actor);
    return this.db
      .run("SYSTEM", async (tx) => {
        const [counts] = await tx.$queryRaw<
          {
            requested: number;
            proposed: number;
            toShip: number;
            onTheRoad: number;
            delivered: number;
            toApprove: number;
          }[]
        >`
        SELECT
          COUNT(*) FILTER (WHERE o.status = 'REQUESTED' AND o."proposedSource" IS NULL)::int AS requested,
          COUNT(*) FILTER (WHERE o.status = 'REQUESTED' AND o."proposedSource" IS NOT NULL)::int AS proposed,
          COUNT(*) FILTER (WHERE o.status = 'ASSIGNED')::int AS "toShip",
          COUNT(*) FILTER (WHERE o.status = 'SHIPPED' AND o."deliveredAt" IS NULL)::int AS "onTheRoad",
          COUNT(*) FILTER (WHERE o.status = 'SHIPPED' AND o."deliveredAt" IS NOT NULL)::int AS delivered,
          COUNT(*) FILTER (WHERE o.status = 'RECEIVED')::int AS "toApprove"
        FROM "RestockOrder" o
        JOIN "Region" r ON r.id = o."regionId"
        WHERE NOT r.sandbox`;
        return counts!;
      })
      .then(async (counts) => {
        const rows = await this.rows({});
        const lowParas = rows.filter((r) => r.low + r.out > 0);
        return {
          orders: counts,
          paras: {
            total: rows.length,
            low: lowParas.length,
            out: rows.filter((r) => r.out > 0).length,
          },
          // The ten paras that need attention first.
          attention: lowParas.slice(0, 10).map((r) => this.present(r)),
        };
      });
  }

  /** One para: its stock with how fast each product sells, what is on order for it, and who to call. */
  async para(actor: Actor, id: string) {
    this.allowed(actor);
    const [row] = await this.rows({ pdvId: id });
    if (!row) throw notFound("Para");
    const since = addDays(tunisDay(new Date()), -7);
    return this.db.run("SYSTEM", async (tx) => {
      const stock = await tx.$queryRaw<
        {
          productId: string;
          name: string;
          family: string;
          quantity: number;
          sold7: number;
        }[]
      >`
        SELECT s."productId", pr.name, pr.family, s.quantity,
          COALESCE(v.sold7, 0)::int AS sold7
        FROM "Stock" s JOIN "Product" pr ON pr.id = s."productId"
        LEFT JOIN (
          SELECT l."productId", SUM(l.quantity)::int AS sold7
          FROM "SaleLine" l JOIN "Sale" sa ON sa.id = l."saleId"
          WHERE sa."pdvId" = ${id}::uuid AND sa.status = 'ACTIVE' AND sa.day >= ${since}::date
          GROUP BY l."productId"
        ) v ON v."productId" = s."productId"
        WHERE s."locationId" = ${id}::uuid
        ORDER BY pr.name`;
      const orders = await tx.restockOrder.findMany({
        where: {
          destId: id,
          status: { in: ["REQUESTED", "ASSIGNED", "SHIPPED", "RECEIVED"] },
        },
        include: { lines: { select: { requested: true } } },
        orderBy: { createdAt: "desc" },
        take: 20,
      });
      const contacts = await tx.user.findMany({
        where: {
          status: "ACTIVE",
          OR: [
            { role: "RESPONSABLE", regionId: row.regionId },
            { role: { in: TEAM_ROLES }, pdvId: id },
          ],
        },
        select: { id: true, name: true, role: true, phone: true },
        orderBy: [{ role: "desc" }, { name: "asc" }],
      });
      const asked = await tx.auditEntry.findFirst({
        where: { action: "orders.asked", entity: "Pdv", entityId: id },
        orderBy: { createdAt: "desc" },
        select: { createdAt: true },
      });
      return {
        ...this.present(row),
        stock: {
          ...this.present(row).stock,
          lines: stock.map((s) => ({
            productId: s.productId,
            name: s.name,
            family: s.family,
            quantity: s.quantity,
            level:
              s.quantity <= 0 ? "OUT" : s.quantity <= LOW_STOCK ? "LOW" : "OK",
            sold7Days: s.sold7,
            // Days the quantity would last at the pace of the last week (null: nothing sold).
            coverDays:
              s.sold7 > 0 ? Math.floor(s.quantity / (s.sold7 / 7)) : null,
          })),
        },
        orders: orders.map((o) => ({
          id: o.id,
          number: o.number,
          status: o.status,
          units: o.lines.reduce((sum, l) => sum + l.requested, 0),
          proposed: o.proposedSource !== null,
          delivered: o.deliveredAt !== null,
          createdAt: o.createdAt,
        })),
        contacts: contacts.map((c) => ({
          id: c.id,
          name: c.name,
          role: c.role,
          phone: c.phone,
        })),
        lastAskedAt: asked?.createdAt ?? null,
      };
    });
  }

  /** "Do you need anything?": the para's team and its responsable are told (and can answer by phone). */
  async ask(actor: Actor, pdvId: string, input: { message?: string }) {
    requireRule(
      actor.role === "ORDERS",
      "FORBIDDEN",
      "Only the order manager asks.",
      403,
    );
    return this.db.run("SYSTEM", async (tx) => {
      const pdv = await tx.pdv.findUnique({
        where: { id: pdvId },
        select: { id: true, name: true, regionId: true, status: true },
      });
      const region = pdv
        ? await tx.region.findUnique({
            where: { id: pdv.regionId },
            select: { sandbox: true },
          })
        : null;
      if (!pdv || region?.sandbox) throw notFound("Para");
      requireRule(
        pdv.status === "ACTIVE",
        "PLACE_INACTIVE",
        "This para is not active.",
      );
      const recent = await tx.auditEntry.findFirst({
        where: {
          action: "orders.asked",
          entity: "Pdv",
          entityId: pdv.id,
          createdAt: { gt: new Date(Date.now() - ASK_AGAIN_MS) },
        },
        select: { id: true },
      });
      if (recent)
        throw new DomainError(
          "TOO_SOON",
          "This para was asked a moment ago: wait for its answer.",
          429,
        );
      const team = await tx.user.findMany({
        where: { role: { in: TEAM_ROLES }, status: "ACTIVE", pdvId: pdv.id },
        select: { id: true },
      });
      const text = input.message?.trim();
      await notify(
        tx,
        [...team.map((t) => t.id), ...(await responsableIds(tx, pdv.regionId))],
        {
          key: "orders.asks",
          params: {
            by: actor.name,
            place: pdv.name,
            message: text ? ` « ${text} »` : "",
          },
          entityType: "Pdv",
          entityId: pdv.id,
        },
      );
      await audit(
        tx,
        actor,
        "orders.asked",
        "Pdv",
        pdv.id,
        { message: text ?? null },
        pdv.regionId,
      );
      return { ok: true };
    });
  }
}
