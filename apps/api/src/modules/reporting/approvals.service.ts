import { Injectable } from "@nestjs/common";
import type { Actor } from "../../core/actor";
import { Database, type Tx } from "../../core/database";
import { requireRule } from "../../core/errors";

export type ApprovalType =
  | "GROUP"
  | "PDV"
  | "MEMBER"
  | "STOCK"
  | "RECEIPT"
  | "PAYOUT"
  | "RESTOCK_REQUEST"
  | "RECOUNT";

export interface ApprovalItem {
  type: ApprovalType;
  id: string;
  name: string;
  by: string | null;
  regionId: string | null;
  region: string | null;
  createdAt: Date;
  /** Small extra facts the phone shows: place, units, amount. */
  meta: Record<string, unknown>;
}

/** Everything waiting for a decision from the admin, in one place. */
@Injectable()
export class ApprovalsService {
  constructor(private readonly db: Database) {}

  counts(tx: Tx) {
    return countPending(tx);
  }

  /**
   * Everything the admin already decided, newest first: who decided, when and why.
   * Read from the audit log, which records every decision exactly once (a restock
   * has two: the request, then the delivery). Page backwards with `before`.
   */
  history(actor: Actor, filter: { type?: ApprovalType; before?: Date }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin has the approvals history.",
      403,
    );
    const take = 40;
    const actions = Object.entries(DECISIONS)
      .filter(([, d]) => !filter.type || d.type === filter.type)
      .map(([action]) => action);
    return this.db.run(actor, async (tx) => {
      const admins = (
        await tx.user.findMany({
          where: { role: "ADMIN" },
          select: { id: true, name: true },
        })
      ).map((u) => u);
      const rows = await tx.auditEntry.findMany({
        where: {
          action: { in: actions },
          actorId: { in: admins.map((a) => a.id) },
          ...(filter.before && { createdAt: { lt: filter.before } }),
        },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: take + 1,
      });
      const page = rows.slice(0, take);
      const ids = (entity: string) =>
        page.filter((r) => r.entity === entity).map((r) => r.entityId);
      const [
        regions,
        groups,
        pdvs,
        users,
        declarations,
        orders,
        payouts,
        recounts,
      ] = await Promise.all([
        tx.region.findMany(),
        tx.group.findMany({ where: { id: { in: ids("Group") } } }),
        tx.pdv.findMany({ where: { id: { in: ids("Pdv") } } }),
        tx.user.findMany({
          where: { id: { in: ids("User") } },
          select: { id: true, name: true },
        }),
        tx.stockDeclaration.findMany({
          where: { id: { in: ids("StockDeclaration") } },
          select: { id: true, locationId: true },
        }),
        tx.restockOrder.findMany({
          where: { id: { in: ids("RestockOrder") } },
          select: { id: true, destId: true, number: true },
        }),
        tx.payoutRequest.findMany({
          where: { id: { in: ids("PayoutRequest") } },
          select: { id: true, userId: true, amountMillimes: true },
        }),
        tx.stockRecount.findMany({
          where: { id: { in: ids("StockRecount") } },
          select: { id: true, locationId: true },
        }),
      ]);
      const places = await placeNames(tx, [
        ...declarations.map((d) => d.locationId),
        ...orders.map((o) => o.destId),
        ...recounts.map((r) => r.locationId),
      ]);
      const payees = new Map(
        (
          await tx.user.findMany({
            where: { id: { in: payouts.map((p) => p.userId) } },
            select: { id: true, name: true },
          })
        ).map((u) => [u.id, u.name]),
      );
      const name = new Map<string, string>([
        ...groups.map((g) => [g.id, g.name] as const),
        ...pdvs.map((p) => [p.id, p.name] as const),
        ...users.map((u) => [u.id, u.name] as const),
        ...declarations.map(
          (d) => [d.id, places.get(d.locationId) ?? ""] as const,
        ),
        ...orders.map(
          (o) => [o.id, `${places.get(o.destId) ?? ""} · ${o.number}`] as const,
        ),
        ...payouts.map(
          (p) =>
            [
              p.id,
              `${payees.get(p.userId) ?? ""} · ${(Number(p.amountMillimes) / 1000).toFixed(3)} TND`,
            ] as const,
        ),
        ...recounts.map((r) => [r.id, places.get(r.locationId) ?? ""] as const),
      ]);
      const regionName = new Map(regions.map((r) => [r.id, r.name]));
      const adminName = new Map(admins.map((a) => [a.id, a.name]));
      return {
        items: page.map((r) => {
          const decision = DECISIONS[r.action]!;
          const details = (r.details ?? {}) as Record<string, unknown>;
          return {
            type: decision.type,
            id: r.entityId,
            name: name.get(r.entityId) ?? "",
            outcome: decision.outcome,
            decidedAt: r.createdAt,
            decidedBy: r.actorId ? (adminName.get(r.actorId) ?? null) : null,
            region: r.regionId ? (regionName.get(r.regionId) ?? null) : null,
            note:
              typeof details.note === "string"
                ? details.note
                : typeof details.reason === "string"
                  ? details.reason
                  : null,
          };
        }),
        nextBefore:
          rows.length > take ? page[page.length - 1]!.createdAt : null,
      };
    });
  }

  inbox(actor: Actor, filter: { regionId?: string; type?: ApprovalType }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin has the approvals inbox.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const region = filter.regionId;
      const want = (t: ApprovalType) => !filter.type || filter.type === t;
      const regions = new Map(
        (await tx.region.findMany()).map((r) => [r.id, r.name]),
      );
      const people = new Map<string, string>();
      const person = async (ids: (string | null)[]) => {
        const missing = ids.filter((x): x is string => !!x && !people.has(x));
        if (missing.length)
          for (const u of await tx.user.findMany({
            where: { id: { in: missing } },
            select: { id: true, name: true },
          }))
            people.set(u.id, u.name);
      };
      const items: ApprovalItem[] = [];
      const at = (id: string | null) => (id ? (regions.get(id) ?? null) : null);

      if (want("GROUP")) {
        const rows = await tx.group.findMany({
          where: { status: "PENDING", ...(region && { regionId: region }) },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        await person(rows.map((r) => r.createdById));
        for (const r of rows)
          items.push({
            type: "GROUP",
            id: r.id,
            name: r.name,
            by: people.get(r.createdById) ?? null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: {},
          });
      }
      if (want("PDV")) {
        const rows = await tx.pdv.findMany({
          where: { status: "PENDING", ...(region && { regionId: region }) },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        await person(rows.map((r) => r.createdById));
        for (const r of rows)
          items.push({
            type: "PDV",
            id: r.id,
            name: r.name,
            by: people.get(r.createdById) ?? null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: { city: r.city },
          });
      }
      if (want("MEMBER")) {
        const rows = await tx.user.findMany({
          where: {
            status: "PENDING",
            role: "VENDEUR",
            ...(region && { regionId: region }),
          },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        const pdvs = new Map(
          (
            await tx.pdv.findMany({
              where: { id: { in: rows.map((r) => r.pdvId!).filter(Boolean) } },
              select: { id: true, name: true },
            })
          ).map((p) => [p.id, p.name]),
        );
        await person(rows.map((r) => r.createdById));
        for (const r of rows)
          items.push({
            type: "MEMBER",
            id: r.id,
            name: r.name,
            by: r.createdById ? (people.get(r.createdById) ?? null) : null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: { pdv: r.pdvId ? pdvs.get(r.pdvId) : null },
          });
      }
      if (want("STOCK")) {
        const rows = await tx.stockDeclaration.findMany({
          where: { status: "PENDING", ...(region && { regionId: region }) },
          include: { lines: { select: { quantity: true } } },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        const places = await placeNames(
          tx,
          rows.map((r) => r.locationId),
        );
        await person(rows.map((r) => r.createdById));
        for (const r of rows)
          items.push({
            type: "STOCK",
            id: r.id,
            name: places.get(r.locationId) ?? "",
            by: people.get(r.createdById) ?? null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: {
              kind: r.kind,
              lines: r.lines.length,
              units: r.lines.reduce((s, l) => s + l.quantity, 0),
            },
          });
      }
      for (const [type, status] of [
        ["RECEIPT", "RECEIVED"],
        ["RESTOCK_REQUEST", "REQUESTED"],
      ] as const) {
        if (!want(type)) continue;
        const rows = await tx.restockOrder.findMany({
          where: { status, ...(region && { regionId: region }) },
          include: { lines: { select: { requested: true, received: true } } },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        const places = await placeNames(
          tx,
          rows.map((r) => r.destId),
        );
        await person(rows.map((r) => r.requestedById));
        for (const r of rows)
          items.push({
            type,
            id: r.id,
            name: places.get(r.destId) ?? "",
            by: people.get(r.requestedById) ?? null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.receivedAt ?? r.createdAt,
            meta: {
              number: r.number,
              units: r.lines.reduce(
                (s, l) =>
                  s + (type === "RECEIPT" ? (l.received ?? 0) : l.requested),
                0,
              ),
            },
          });
      }
      if (want("RECOUNT")) {
        const rows = await tx.stockRecount.findMany({
          where: { status: "PENDING", ...(region && { regionId: region }) },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        const places = await placeNames(
          tx,
          rows.map((r) => r.locationId),
        );
        await person(rows.map((r) => r.requestedById));
        for (const r of rows)
          items.push({
            type: "RECOUNT",
            id: r.id,
            name: places.get(r.locationId) ?? "",
            by: people.get(r.requestedById) ?? null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: { reason: r.reason },
          });
      }
      if (want("PAYOUT")) {
        const rows = await tx.payoutRequest.findMany({
          where: { status: "PENDING", ...(region && { regionId: region }) },
          orderBy: { createdAt: "asc" },
          take: 100,
        });
        await person(rows.map((r) => r.userId));
        for (const r of rows)
          items.push({
            type: "PAYOUT",
            id: r.id,
            name: people.get(r.userId) ?? "",
            by: null,
            regionId: r.regionId,
            region: at(r.regionId),
            createdAt: r.createdAt,
            meta: { amountMillimes: r.amountMillimes },
          });
      }
      items.sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
      return { counts: await countPending(tx, region), items };
    });
  }
}

/** The audit actions that are decisions, and what they mean in the history. */
const DECISIONS: Record<
  string,
  { type: ApprovalType; outcome: "APPROVED" | "REJECTED" | "DEACTIVATED" }
> = {
  "group.approve": { type: "GROUP", outcome: "APPROVED" },
  "group.reject": { type: "GROUP", outcome: "REJECTED" },
  "group.suspend": { type: "GROUP", outcome: "DEACTIVATED" },
  "group.reactivate": { type: "GROUP", outcome: "APPROVED" },
  "pdv.approve": { type: "PDV", outcome: "APPROVED" },
  "pdv.reject": { type: "PDV", outcome: "REJECTED" },
  "pdv.suspend": { type: "PDV", outcome: "DEACTIVATED" },
  "pdv.reactivate": { type: "PDV", outcome: "APPROVED" },
  "user.approve": { type: "MEMBER", outcome: "APPROVED" },
  "user.reject": { type: "MEMBER", outcome: "REJECTED" },
  "user.suspend": { type: "MEMBER", outcome: "DEACTIVATED" },
  "user.reactivate": { type: "MEMBER", outcome: "APPROVED" },
  "stock.approved": { type: "STOCK", outcome: "APPROVED" },
  "stock.rejected": { type: "STOCK", outcome: "REJECTED" },
  "restock.assigned": { type: "RESTOCK_REQUEST", outcome: "APPROVED" },
  "restock.sent_direct": { type: "RESTOCK_REQUEST", outcome: "APPROVED" },
  "restock.recorded": { type: "RECEIPT", outcome: "APPROVED" },
  "restock.cancelled": { type: "RESTOCK_REQUEST", outcome: "REJECTED" },
  "restock.approved": { type: "RECEIPT", outcome: "APPROVED" },
  "restock.receipt_rejected": { type: "RECEIPT", outcome: "REJECTED" },
  "payout.approved": { type: "PAYOUT", outcome: "APPROVED" },
  "payout.rejected": { type: "PAYOUT", outcome: "REJECTED" },
  "stock.recount_approved": { type: "RECOUNT", outcome: "APPROVED" },
  "stock.recount_rejected": { type: "RECOUNT", outcome: "REJECTED" },
};

async function placeNames(tx: Tx, ids: string[]) {
  const [pdvs, depots] = await Promise.all([
    tx.pdv.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true },
    }),
    tx.depot.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true },
    }),
  ]);
  return new Map([...pdvs, ...depots].map((p) => [p.id, p.name]));
}

/** How many things wait for the admin, by kind. Scoped by row-level security to the caller. */
export async function countPending(tx: Tx, regionId?: string) {
  const region = regionId ? { regionId } : {};
  const [groups, pdvs, members, stock, receipts, requests, payouts, recounts] =
    await Promise.all([
      tx.group.count({ where: { status: "PENDING", ...region } }),
      tx.pdv.count({ where: { status: "PENDING", ...region } }),
      tx.user.count({
        where: { status: "PENDING", role: "VENDEUR", ...region },
      }),
      tx.stockDeclaration.count({ where: { status: "PENDING", ...region } }),
      tx.restockOrder.count({ where: { status: "RECEIVED", ...region } }),
      tx.restockOrder.count({ where: { status: "REQUESTED", ...region } }),
      tx.payoutRequest.count({ where: { status: "PENDING", ...region } }),
      tx.stockRecount.count({ where: { status: "PENDING", ...region } }),
    ]);
  return {
    GROUP: groups,
    PDV: pdvs,
    MEMBER: members,
    STOCK: stock,
    RECEIPT: receipts,
    RESTOCK_REQUEST: requests,
    PAYOUT: payouts,
    RECOUNT: recounts,
    total:
      groups +
      pdvs +
      members +
      stock +
      receipts +
      requests +
      payouts +
      recounts,
  };
}
