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
  | "RESTOCK_REQUEST";

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
  const [groups, pdvs, members, stock, receipts, requests, payouts] =
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
    ]);
  return {
    GROUP: groups,
    PDV: pdvs,
    MEMBER: members,
    STOCK: stock,
    RECEIPT: receipts,
    RESTOCK_REQUEST: requests,
    PAYOUT: payouts,
    total: groups + pdvs + members + stock + receipts + requests + payouts,
  };
}
