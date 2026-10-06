import type { Tx } from "../../core/database";

/** The reward (millimes per unit) each product earns on a given Tunis day. */
export async function unitRewards(
  tx: Tx,
  products: { id: string; family: string }[],
  day: Date,
): Promise<Map<string, bigint>> {
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
  // A rule for the product itself wins over the rule for its family.
  return new Map(
    products.map((p) => [
      p.id,
      byKey.get(`P:${p.id}`) ?? byKey.get(`F:${p.family}`) ?? 0n,
    ]),
  );
}
