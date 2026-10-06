import type { Tx } from "../../core/database";

export type RewardSource = "PRODUCT" | "FAMILY" | "NONE";

/**
 * The reward (millimes per unit) each product earns on a given Tunis day, and
 * which rule decided it. A rule for the product itself always wins over the
 * rule for its family; the family rule is only the default for the others.
 */
export async function rewardSources(
  tx: Tx,
  products: { id: string; family: string }[],
  day: Date,
): Promise<Map<string, { amount: bigint; source: RewardSource }>> {
  const keys = products.flatMap((p) => [`P:${p.id}`, `F:${p.family}`]);
  const rules = await tx.rewardRule.findMany({
    where: {
      targetKey: { in: keys },
      cancelledAt: null,
      startsOn: { lte: day },
      OR: [{ endsOn: null }, { endsOn: { gte: day } }],
    },
  });
  // At most one live rule covers a day per target (the database guarantees it).
  const byKey = new Map(rules.map((r) => [r.targetKey, r.amountMillimes]));
  return new Map<string, { amount: bigint; source: RewardSource }>(
    products.map((p): [string, { amount: bigint; source: RewardSource }] => {
      const own = byKey.get(`P:${p.id}`);
      if (own !== undefined) return [p.id, { amount: own, source: "PRODUCT" }];
      const family = byKey.get(`F:${p.family}`);
      if (family !== undefined)
        return [p.id, { amount: family, source: "FAMILY" }];
      return [p.id, { amount: 0n, source: "NONE" }];
    }),
  );
}

/** Just the amounts, for recording sales. */
export async function unitRewards(
  tx: Tx,
  products: { id: string; family: string }[],
  day: Date,
): Promise<Map<string, bigint>> {
  const sources = await rewardSources(tx, products, day);
  return new Map([...sources].map(([id, s]) => [id, s.amount]));
}
