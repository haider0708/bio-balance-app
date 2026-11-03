import type { Database, Tx } from "../core/database";
import { addDays, tunisDay } from "../core/dates";
import { notify } from "../core/notifier";

/** The evening alert about tomorrow's visits goes out at 20:00, Tunis time. */
const EVENING_AT_MINUTES = 20 * 60;
/** Visits of the day are closed at 23:30: a planned one nobody started is missed. */
const CLOSE_AT_MINUTES = 23 * 60 + 30;

const tunisMinutes = (at: Date) => {
  const local = new Date(at.getTime() + 3_600_000);
  return local.getUTCHours() * 60 + local.getUTCMinutes();
};
/** HH:MM in Tunis time. */
const clock = (at: Date) =>
  new Date(at.getTime() + 3_600_000).toISOString().slice(11, 16);

interface PlaceRef {
  targetKind: "PDV" | "DEPOT";
  targetId: string;
}

async function placeNames(tx: Tx, rows: PlaceRef[]) {
  const names = new Map<string, string>();
  const pdvs = [
    ...new Set(
      rows.filter((r) => r.targetKind === "PDV").map((r) => r.targetId),
    ),
  ];
  const depots = [
    ...new Set(
      rows.filter((r) => r.targetKind === "DEPOT").map((r) => r.targetId),
    ),
  ];
  if (pdvs.length)
    for (const p of await tx.pdv.findMany({
      where: { id: { in: pdvs } },
      select: { id: true, name: true },
    }))
      names.set(`PDV:${p.id}`, p.name);
  if (depots.length)
    for (const d of await tx.depot.findMany({
      where: { id: { in: depots } },
      select: { id: true, name: true },
    }))
      names.set(`DEPOT:${d.id}`, d.name);
  return (row: PlaceRef) =>
    names.get(`${row.targetKind}:${row.targetId}`) ?? "?";
}

/**
 * The reminder before each planned visit, at the lead the responsable chose (60 minutes unless they
 * changed it; none if they turned it off). A visit planned or changed after its reminder time is
 * not reminded: the person has just seen it. Safe to run as often as wanted: each visit is claimed once.
 */
export async function sendVisitReminders(db: Database, now = new Date()) {
  await db.run("SYSTEM", async (tx) => {
    const due = await tx.$queryRaw<
      (PlaceRef & {
        id: string;
        responsableId: string;
        plannedStart: Date;
        kind: string;
      })[]
    >`
      UPDATE "Visit" v SET "reminderSentAt" = ${now}
      FROM (
        SELECT v2.id FROM "Visit" v2
        LEFT JOIN "PlanningPreference" p ON p."userId" = v2."responsableId"
        WHERE v2.status = 'PLANNED' AND v2."reminderSentAt" IS NULL
          AND v2."plannedStart" > ${now}
          AND COALESCE(p."leadMinutes", 60) > 0
          AND v2."plannedStart" - make_interval(mins => COALESCE(p."leadMinutes", 60)) <= ${now}
          AND v2."updatedAt" < v2."plannedStart" - make_interval(mins => COALESCE(p."leadMinutes", 60))
        FOR UPDATE OF v2 SKIP LOCKED
      ) due
      WHERE v.id = due.id
      RETURNING v.id, v."responsableId", v."plannedStart", v."targetKind", v."targetId", v.kind`;
    if (!due.length) return;
    const name = await placeNames(tx, due);
    for (const v of due)
      await notify(tx, [v.responsableId], {
        key: "visit.reminder",
        params: { place: name(v), time: clock(v.plannedStart) },
        entityType: "Visit",
        entityId: v.id,
      });
  });
}

/** At 20:00: each responsable who has visits tomorrow hears how many, and the first. */
export async function sendEveningPlans(db: Database, tomorrow: string) {
  await db.run("SYSTEM", async (tx) => {
    const rows = await tx.$queryRaw<
      (PlaceRef & {
        responsableId: string;
        plannedStart: Date;
        total: number;
      })[]
    >`
      SELECT DISTINCT ON (v."responsableId") v."responsableId", v."plannedStart", v."targetKind", v."targetId",
        COUNT(*) OVER (PARTITION BY v."responsableId")::int AS total
      FROM "Visit" v
      LEFT JOIN "PlanningPreference" p ON p."userId" = v."responsableId"
      WHERE v.status = 'PLANNED' AND v.day = ${tomorrow}::date AND COALESCE(p."eveningSummary", true)
      ORDER BY v."responsableId", v."plannedStart"`;
    if (!rows.length) return;
    const name = await placeNames(tx, rows);
    for (const r of rows)
      await notify(tx, [r.responsableId], {
        key: "visit.tomorrow",
        params: { count: r.total, time: clock(r.plannedStart), place: name(r) },
        entityType: "Planning",
      });
  });
}

/**
 * Closes visits: a planned one nobody started is missed (the responsable is told), one still on
 * site is done. At the day's end (`endedOnly`) only visits whose planned time is over are closed,
 * so a visit planned late in the evening is not missed before it begins; the next day everything
 * of the days before is settled.
 */
export async function closeVisitDay(
  db: Database,
  day: string,
  endedOnly = true,
) {
  await db.run("SYSTEM", async (tx) => {
    const missed = await tx.$queryRaw<
      (PlaceRef & { id: string; responsableId: string; day: Date })[]
    >`
      UPDATE "Visit" SET status = 'MISSED', revision = revision + 1, "updatedAt" = now()
      WHERE status = 'PLANNED'
        AND (day < ${day}::date OR (day = ${day}::date AND (NOT ${endedOnly} OR "plannedEnd" <= now())))
      RETURNING id, "responsableId", day, "targetKind", "targetId"`;
    await tx.$executeRaw`
      UPDATE "Visit" SET status = 'DONE', revision = revision + 1, "updatedAt" = now()
      WHERE status = 'ON_SITE'
        AND (day < ${day}::date OR (day = ${day}::date AND (NOT ${endedOnly} OR "plannedEnd" <= now())))`;
    if (!missed.length) return;
    const name = await placeNames(tx, missed);
    for (const v of missed)
      await notify(tx, [v.responsableId], {
        key: "visit.missed",
        params: { place: name(v), day: v.day.toISOString().slice(0, 10) },
        entityType: "Visit",
        entityId: v.id,
      });
  });
}

/**
 * Queues the evening alert from 20:00, the day's closing from 23:30, and the settling of yesterday
 * (visits that ended late, or if the worker was down).
 */
export async function scheduleVisitJobs(db: Database, now = new Date()) {
  const today = tunisDay(now);
  const minutes = tunisMinutes(now);
  const yesterday = addDays(today, -1);
  const jobs: { kind: string; key: string; payload: object }[] = [
    {
      kind: "visit-settle",
      key: `visit-settle:${yesterday}`,
      payload: { day: yesterday },
    },
  ];
  if (minutes >= EVENING_AT_MINUTES)
    jobs.push({
      kind: "visit-evening",
      key: `visit-evening:${today}`,
      payload: { day: addDays(today, 1) },
    });
  if (minutes >= CLOSE_AT_MINUTES)
    jobs.push({
      kind: "visit-close",
      key: `visit-close:${today}`,
      payload: { day: today },
    });
  await db.job.createMany({ data: jobs, skipDuplicates: true });
}

/** Visits and their check-ins are kept 12 months, with two days of margin (the database refuses earlier). */
export async function purgeOldVisits(db: Database) {
  await db.run(
    "SYSTEM",
    (tx) =>
      tx.$executeRaw`DELETE FROM "Visit" WHERE day < (now() - interval '12 months 2 days')::date`,
  );
}
