import type { Tx } from "../../core/database";
import { addDays, dayToDate, tunisDay } from "../../core/dates";

/** What a team member sees: balance, what is already requested, and what they earned recently. */
export async function walletSummary(tx: Tx, userId: string) {
  const [balance, held, today, week, month] = await Promise.all([
    tx.walletEntry.aggregate({ where: { userId }, _sum: { amountMillimes: true } }),
    tx.payoutRequest.aggregate({ where: { userId, status: "PENDING" }, _sum: { amountMillimes: true } }),
    earned(tx, userId, tunisDay(new Date())),
    earned(tx, userId, addDays(tunisDay(new Date()), -6)),
    earned(tx, userId, addDays(tunisDay(new Date()), -29)),
  ]);
  const total = balance._sum.amountMillimes ?? 0n;
  const pending = held._sum.amountMillimes ?? 0n;
  return {
    balanceMillimes: total,
    pendingPayoutMillimes: pending,
    availableMillimes: total - pending,
    today, week, month,
  };
}

/** Units and reward of the seller's sales from `fromDay` until now. */
async function earned(tx: Tx, userId: string, fromDay: string) {
  const row = await tx.sale.aggregate({
    where: { sellerId: userId, status: "ACTIVE", day: { gte: dayToDate(fromDay) } },
    _sum: { units: true, rewardMillimes: true },
    _count: { _all: true },
  });
  return {
    sales: row._count._all,
    units: row._sum.units ?? 0,
    rewardMillimes: row._sum.rewardMillimes ?? 0n,
  };
}
