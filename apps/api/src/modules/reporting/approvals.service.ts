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
   * Page backwards with `before` (the date of the last item received).
   */
  history(actor: Actor, filter: { type?: ApprovalType; before?: Date }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin has the approvals history.",
      403,
    );
    const take = 40;
    return this.db.run(actor, async (tx) => {
      const before = filter.before ?? new Date(Date.now() + 60_000);
      const decided = { not: null, lt: before } as const;
      const want = (t: ApprovalType) => !filter.type || filter.type === t;
      const regions = new Map(
        (await tx.region.findMany()).map((r) => [r.id, r.name]),
      );
      const rows: (HistoryItem & { by: string | null })[] = [];
      const outcome = (status: string): HistoryItem["outcome"] =>
        status === "REJECTED"
          ? "REJECTED"
          : status === "SUSPENDED"
            ? "DEACTIVATED"
            : "APPROVED";
      const push = (
        type: ApprovalType,
        r: {
          id: string;
          decidedAt: Date | null;
          decidedById: string | null;
          decisionNote: string | null;
          regionId: string | null;
        },
        name: string,
        result: HistoryItem["outcome"],
      ) =>
        rows.push({
          type,
          id: r.id,
          name,
          outcome: result,
          decidedAt: r.decidedAt!,
          decidedBy: r.decidedById,
          region: r.regionId ? (regions.get(r.regionId) ?? null) : null,
          note: r.decisionNote,
          by: null,
        });
      if (want("GROUP"))
        for (const r of await tx.group.findMany({
          where: { decidedAt: decided },
          orderBy: { decidedAt: "desc" },
          take,
        }))
          push("GROUP", r, r.name, outcome(r.status));
      if (want("PDV"))
        for (const r of await tx.pdv.findMany({
          where: { decidedAt: decided },
          orderBy: { decidedAt: "desc" },
          take,
        }))
          push("PDV", r, r.name, outcome(r.status));
      if (want("MEMBER"))
        for (const r of await tx.user.findMany({
          where: { decidedAt: decided, role: "VENDEUR" },
          orderBy: { decidedAt: "desc" },
          take,
        }))
          push("MEMBER", r, r.name, outcome(r.status));
      if (want("STOCK")) {
        const list = await tx.stockDeclaration.findMany({
          where: { decidedAt: decided },
          orderBy: { decidedAt: "desc" },
          take,
        });
        const places = await placeNames(
          tx,
          list.map((d) => d.locationId),
        );
        for (const r of list)
          push(
            "STOCK",
            r,
            places.get(r.locationId) ?? "",
            r.status === "REJECTED" ? "REJECTED" : "APPROVED",
          );
      }
      for (const type of ["RECEIPT", "RESTOCK_REQUEST"] as const) {
        if (!want(type)) continue;
        const list = await tx.restockOrder.findMany({
          where: {
            decidedAt: decided,
            // A receipt is decided once delivered; a request is decided when assigned or cancelled.
            ...(type === "RECEIPT"
              ? { receivedAt: { not: null } }
              : { receivedAt: null }),
          },
          orderBy: { decidedAt: "desc" },
          take,
        });
        const places = await placeNames(
          tx,
          list.map((o) => o.destId),
        );
        for (const r of list)
          push(
            type,
            r,
            `${places.get(r.destId) ?? ""} · ${r.number}`,
            r.status === "CANCELLED" ? "REJECTED" : "APPROVED",
          );
      }
      if (want("PAYOUT")) {
        const list = await tx.payoutRequest.findMany({
          where: { decidedAt: decided },
          orderBy: { decidedAt: "desc" },
          take,
        });
        const names = new Map(
          (
            await tx.user.findMany({
              where: { id: { in: list.map((p) => p.userId) } },
              select: { id: true, name: true },
            })
          ).map((u) => [u.id, u.name]),
        );
        for (const r of list)
          push(
            "PAYOUT",
            { ...r, regionId: r.regionId ?? null },
            `${names.get(r.userId) ?? ""} · ${(Number(r.amountMillimes) / 1000).toFixed(3)} TND`,
            r.status === "REJECTED" ? "REJECTED" : "APPROVED",
          );
      }
      if (want("RECOUNT")) {
        const list = await tx.stockRecount.findMany({
          where: { decidedAt: decided },
          orderBy: { decidedAt: "desc" },
          take,
        });
        const places = await placeNames(
          tx,
          list.map((d) => d.locationId),
        );
        for (const r of list)
          push(
            "RECOUNT",
            r,
            places.get(r.locationId) ?? "",
            r.status === "REJECTED" ? "REJECTED" : "APPROVED",
          );
      }
      rows.sort((a, b) => b.decidedAt.getTime() - a.decidedAt.getTime());
      const page = rows.slice(0, take);
      const people = new Map(
        (
          await tx.user.findMany({
            where: {
              id: {
                in: page
                  .map((r) => r.decidedBy)
                  .filter((x): x is string => !!x),
              },
            },
            select: { id: true, name: true },
          })
        ).map((u) => [u.id, u.name]),
      );
      return {
        items: page.map(({ by: _by, ...r }) => ({
          ...r,
          decidedBy: r.decidedBy ? (people.get(r.decidedBy) ?? null) : null,
        })),
        nextBefore:
          rows.length > take ? page[page.length - 1]!.decidedAt : null,
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

export interface HistoryItem {
  type: ApprovalType;
  id: string;
  name: string;
  outcome: "APPROVED" | "REJECTED" | "DEACTIVATED";
  decidedAt: Date;
  decidedBy: string | null;
  region: string | null;
  note: string | null;
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
  const [
    groups,
    pdvs,
    members,
    stock,
    receipts,
    requests,
    payouts,
    recounts,
    review,
  ] = await Promise.all([
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
    tx.stockDeclaration.count({ where: { status: "REVIEW", ...region } }),
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
    /** Grossiste counts waiting for the responsable (not part of the admin's total). */
    REVIEW: review,
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
