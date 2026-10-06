import { Injectable } from "@nestjs/common";
import type { PayoutStatus } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, notifyAdmins } from "../../core/notifier";
import { decodeCursor, page } from "../../core/pagination";
import { walletSummary } from "./wallet.queries";

/** A team member's wallet: it receives the rewards, and money leaves it only when the admin approves a payout. */
@Injectable()
export class WalletService {
  constructor(private readonly db: Database) {}

  mine(actor: Actor) {
    requireRule(
      actor.role === "VENDEUR",
      "FORBIDDEN",
      "Only team members have a wallet.",
      403,
    );
    return this.db.run(actor, (tx) => walletSummary(tx, actor.id));
  }

  entries(actor: Actor, filter: { limit: number; cursor?: string }) {
    requireRule(
      actor.role === "VENDEUR",
      "FORBIDDEN",
      "Only team members have a wallet.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const after = decodeCursor(filter.cursor);
      const rows = await tx.walletEntry.findMany({
        where: {
          userId: actor.id,
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
      return page(rows, filter.limit);
    });
  }

  // ───────────────────────── Payouts ─────────────────────────

  request(actor: Actor, amountMillimes: number) {
    requireRule(
      actor.role === "VENDEUR" && actor.regionId,
      "FORBIDDEN",
      "Only team members request payouts.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      // Requests from one person are handled one at a time, so they can never exceed the balance together.
      await this.db.lock(tx, "User", actor.id);
      const wallet = await walletSummary(tx, actor.id);
      requireRule(
        BigInt(amountMillimes) <= wallet.availableMillimes,
        "INSUFFICIENT_BALANCE",
        "The amount is higher than your available balance.",
        409,
      );
      const payout = await tx.payoutRequest.create({
        data: {
          userId: actor.id,
          regionId: actor.regionId!,
          amountMillimes: BigInt(amountMillimes),
        },
      });
      await audit(
        tx,
        actor,
        "payout.requested",
        "PayoutRequest",
        payout.id,
        { amountMillimes },
        actor.regionId,
      );
      await notifyAdmins(tx, {
        key: "payout.requested",
        params: { name: actor.name, amountMillimes },
        entityType: "PayoutRequest",
        entityId: payout.id,
      });
      return payout;
    });
  }

  cancel(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "PayoutRequest", id);
      const payout = await tx.payoutRequest.findUnique({ where: { id } });
      if (!payout || payout.userId !== actor.id)
        throw notFound("Payout request");
      requireRule(
        payout.status === "PENDING",
        "INVALID_STATE",
        "This request was already decided.",
        409,
      );
      return tx.payoutRequest.update({
        where: { id },
        data: { status: "CANCELLED" },
      });
    });
  }

  list(actor: Actor, filter: { status?: PayoutStatus; regionId?: string }) {
    requireRule(
      ["VENDEUR", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.payoutRequest.findMany({
        where: {
          ...(filter.status && { status: filter.status }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
        },
        orderBy: { createdAt: "desc" },
        take: 200,
      });
      return this.present(tx, rows);
    });
  }

  /** The admin has paid the person: the amount leaves the wallet. */
  approve(
    actor: Actor,
    id: string,
    input: { paidAt?: Date; reference?: string; note?: string },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin approves payouts.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "PayoutRequest", id);
      const payout = await tx.payoutRequest.findUnique({ where: { id } });
      if (!payout) throw notFound("Payout request");
      requireRule(
        payout.status === "PENDING",
        "INVALID_STATE",
        "This request was already decided.",
        409,
      );
      await this.db.lock(tx, "User", payout.userId);
      const balance = await tx.walletEntry.aggregate({
        where: { userId: payout.userId },
        _sum: { amountMillimes: true },
      });
      if ((balance._sum.amountMillimes ?? 0n) < payout.amountMillimes)
        throw new DomainError(
          "INSUFFICIENT_BALANCE",
          "Corrections lowered the balance below this amount.",
          409,
          { balanceMillimes: balance._sum.amountMillimes ?? 0n },
        );
      await tx.walletEntry.createMany({
        data: [
          {
            userId: payout.userId,
            kind: "PAYOUT",
            amountMillimes: -payout.amountMillimes,
            payoutId: id,
            note: input.reference ?? null,
          },
        ],
      });
      const updated = await tx.payoutRequest.update({
        where: { id },
        data: {
          status: "APPROVED",
          decidedById: actor.id,
          decidedAt: new Date(),
          paidAt: input.paidAt ?? new Date(),
          reference: input.reference?.trim() || null,
          decisionNote: input.note?.trim() || null,
        },
      });
      await audit(
        tx,
        actor,
        "payout.approved",
        "PayoutRequest",
        id,
        { amountMillimes: payout.amountMillimes },
        payout.regionId,
      );
      await notify(tx, [payout.userId], {
        key: "payout.approved",
        params: { amountMillimes: payout.amountMillimes },
        entityType: "PayoutRequest",
        entityId: id,
      });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  reject(actor: Actor, id: string, note: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin decides payouts.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      await this.db.lock(tx, "PayoutRequest", id);
      const payout = await tx.payoutRequest.findUnique({ where: { id } });
      if (!payout) throw notFound("Payout request");
      requireRule(
        payout.status === "PENDING",
        "INVALID_STATE",
        "This request was already decided.",
        409,
      );
      const updated = await tx.payoutRequest.update({
        where: { id },
        data: {
          status: "REJECTED",
          decidedById: actor.id,
          decidedAt: new Date(),
          decisionNote: note,
        },
      });
      await audit(
        tx,
        actor,
        "payout.rejected",
        "PayoutRequest",
        id,
        { note },
        payout.regionId,
      );
      await notify(tx, [payout.userId], {
        key: "payout.rejected",
        params: { amountMillimes: payout.amountMillimes, note },
        entityType: "PayoutRequest",
        entityId: id,
      });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** Admin overview: every team member's balance, earnings and paid amounts. */
  overview(actor: Actor, filter: { regionId?: string }) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sees all wallets.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.$queryRaw<
        {
          userId: string;
          name: string;
          pdv: string;
          region: string;
          earned: bigint;
          paid: bigint;
          balance: bigint;
          pending: bigint;
        }[]
      >`SELECT u.id AS "userId", u.name, p.name AS pdv, r.name AS region,
          COALESCE(SUM(w."amountMillimes") FILTER (WHERE w.kind IN ('SALE','CORRECTION')),0)::bigint AS earned,
          COALESCE(-SUM(w."amountMillimes") FILTER (WHERE w.kind = 'PAYOUT'),0)::bigint AS paid,
          COALESCE(SUM(w."amountMillimes"),0)::bigint AS balance,
          COALESCE((SELECT SUM(q."amountMillimes") FROM "PayoutRequest" q WHERE q."userId"=u.id AND q.status='PENDING'),0)::bigint AS pending
        FROM "User" u
        JOIN "Pdv" p ON p.id = u."pdvId" JOIN "Region" r ON r.id = u."regionId"
        LEFT JOIN "WalletEntry" w ON w."userId" = u.id
        WHERE u.role = 'VENDEUR' AND u.status = 'ACTIVE' AND (${filter.regionId ?? null}::uuid IS NULL OR u."regionId" = ${filter.regionId ?? null}::uuid)
        GROUP BY u.id, u.name, p.name, r.name ORDER BY u.name`;
      return rows.map((r) => ({
        ...r,
        availableMillimes: r.balance - r.pending,
      }));
    });
  }

  private async present(
    tx: Tx,
    rows: Awaited<ReturnType<Tx["payoutRequest"]["findMany"]>>,
  ) {
    const users = await tx.user.findMany({
      where: { id: { in: rows.map((r) => r.userId) } },
      select: { id: true, name: true, phone: true, pdvId: true },
    });
    const pdvs = await tx.pdv.findMany({
      where: {
        id: { in: users.map((u) => u.pdvId).filter((x): x is string => !!x) },
      },
      select: { id: true, name: true },
    });
    const pdv = new Map(pdvs.map((p) => [p.id, p.name]));
    const user = new Map(
      users.map((u) => [
        u.id,
        {
          id: u.id,
          name: u.name,
          phone: u.phone,
          pdv: u.pdvId ? (pdv.get(u.pdvId) ?? "") : "",
        },
      ]),
    );
    return rows.map((r) => ({ ...r, user: user.get(r.userId) ?? null }));
  }
}
