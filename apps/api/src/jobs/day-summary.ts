import type { Database } from "../core/database";
import { dayToDate, tunisDay } from "../core/dates";
import { adminIds, notify, responsableIds } from "../core/notifier";

/** The evening summary goes out at 20:30, Tunis time (the stores close around 20:00). */
const SEND_AT_MINUTES = 20 * 60 + 30;

interface RegionDay {
  id: string;
  name: string;
  sales: number;
  units: number;
  reward: bigint;
  outOfStock: number;
}

/**
 * The day in one alert, instead of one per sale: each responsable gets their region's sales,
 * units and rewards (and the products out of stock in its stores, or that nothing was sold), the
 * admins the whole network. Regions without an active store, and the test region, are left out;
 * a network without any store sends nothing.
 */
export async function sendDaySummaries(
  db: Database,
  tunisDate = tunisDay(new Date()),
) {
  const day = dayToDate(tunisDate);
  await db.run("SYSTEM", async (tx) => {
    const regions = await tx.$queryRaw<RegionDay[]>`
      SELECT r.id, r.name,
        COUNT(s.id)::int AS sales,
        COALESCE(SUM(s.units), 0)::int AS units,
        COALESCE(SUM(s."rewardMillimes"), 0)::bigint AS reward,
        (SELECT COUNT(*)::int FROM "Stock" st
           JOIN "Pdv" p ON p.id = st."locationId" JOIN "Product" pr ON pr.id = st."productId"
          WHERE st."locationKind" = 'PDV' AND p."regionId" = r.id AND p.status = 'ACTIVE'
            AND pr.active AND st.quantity <= 0) AS "outOfStock"
      FROM "Region" r
      LEFT JOIN "Sale" s ON s."regionId" = r.id AND s.status = 'ACTIVE' AND s.day = ${day}::date
      WHERE NOT r.sandbox
        AND EXISTS (SELECT 1 FROM "Pdv" p WHERE p."regionId" = r.id AND p.status = 'ACTIVE')
      GROUP BY r.id, r.name
      ORDER BY r.name`;
    for (const r of regions)
      await notify(tx, await responsableIds(tx, r.id), {
        key:
          r.sales === 0
            ? "day.summary_none"
            : r.outOfStock > 0
              ? "day.summary_stock"
              : "day.summary",
        params: {
          region: r.name,
          sales: r.sales,
          units: r.units,
          amountMillimes: Number(r.reward),
          outOfStock: r.outOfStock,
        },
        entityType: "Region",
        entityId: r.id,
      });
    if (!regions.length) return;
    await notify(tx, await adminIds(tx), {
      key: "day.network",
      params: {
        sales: regions.reduce((sum, r) => sum + r.sales, 0),
        units: regions.reduce((sum, r) => sum + r.units, 0),
        amountMillimes: Number(regions.reduce((sum, r) => sum + r.reward, 0n)),
      },
      entityType: "Network",
    });
  });
}

/** Once a day, from 20:30 Tunis time (a worker started later that evening still sends it). */
export async function scheduleDaySummary(db: Database, now = new Date()) {
  const tunis = new Date(now.getTime() + 3_600_000);
  if (tunis.getUTCHours() * 60 + tunis.getUTCMinutes() < SEND_AT_MINUTES)
    return;
  await db.job.createMany({
    data: [
      {
        kind: "day-summary",
        key: `day-summary:${tunisDay(now)}`,
        payload: { day: tunisDay(now) },
      },
    ],
    skipDuplicates: true,
  });
}
