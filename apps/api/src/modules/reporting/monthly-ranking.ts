import { Prisma } from "@prisma/client";
import { localDate } from "../../shared/domain/money";

/** Spending never changes this ranking; returns use the earned-points ledger. */
export async function monthlyRanking(
  tx: Prisma.TransactionClient,
  store: string,
  timezone: string,
  userId?: string,
) {
  const month = localDate(new Date(), timezone).slice(0, 7);
  const scores = await tx.$queryRaw<
    { userId: string; name: string; score: bigint; rank: bigint }[]
  >(Prisma.sql`WITH ranking AS (
    SELECT p."userId",u.name,SUM(p.amount)::bigint AS score,
      DENSE_RANK() OVER(ORDER BY SUM(p.amount) DESC)::bigint AS rank
    FROM "PointsEntry" p JOIN "User" u ON u.id=p."userId"
    WHERE p."storeId"=${store}::uuid AND p.kind='earned'
      AND p."createdAt">=(${month + "-01"}::timestamp AT TIME ZONE ${timezone} AT TIME ZONE 'UTC')
      AND p."createdAt"<((${month + "-01"}::timestamp + interval '1 month') AT TIME ZONE ${timezone} AT TIME ZONE 'UTC')
    GROUP BY p."userId",u.name
  ) SELECT * FROM ranking ${userId ? Prisma.sql`WHERE "userId"=${userId}::uuid` : Prisma.empty}
    ORDER BY score DESC,name,"userId" LIMIT 200`);
  return { month, scores };
}
