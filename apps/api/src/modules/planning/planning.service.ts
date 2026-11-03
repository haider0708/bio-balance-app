import { Injectable } from "@nestjs/common";
import {
  Prisma,
  type Depot,
  type LocationKind,
  type Pdv,
  type Visit,
  type VisitEvent,
  type VisitKind,
} from "@prisma/client";
import { randomBytes } from "node:crypto";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { addDays, dateToDay, dayToDate, tunisDay } from "../../core/dates";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { buildCalendar, type FeedVisit } from "./ics";
import {
  MAX_POSITION_ACCURACY_M,
  inTunisia,
  judgePresence,
  type Point,
} from "./geo";

const MINUTE = 60_000;
/** A responsable may start a visit this long before its planned time. */
const EARLY_MS = 60 * MINUTE;
const MAX_VISITS_PER_DAY = 20;
/** A tap on the phone is accepted up to two days later (a phone without signal), never in the future. */
const MAX_AGE_MS = 48 * 60 * MINUTE;
const MAX_AHEAD_MS = 5 * MINUTE;
/** Sent later than this after the tap, an event is marked LATE_SYNC. */
const LATE_MS = 15 * MINUTE;
const FEED_DAYS_BACK = 30;
const FEED_DAYS_AHEAD = 120;
export const LEAD_CHOICES = [0, 15, 30, 60, 120] as const;

export interface VisitInput {
  targetKind: LocationKind;
  targetId: string;
  kind: VisitKind;
  start: Date;
  durationMinutes: number;
  note?: string;
  /** The responsable saw that another visit covers this time and still means it. */
  allowOverlap?: boolean;
}

export interface PresenceInput {
  occurredAt?: Date;
  latitude?: number;
  longitude?: number;
  accuracyMeters?: number;
  /** The phone says the position was given by a location-faking app. */
  mocked?: boolean;
  reason?: string;
}

type Place = Pick<
  Pdv,
  | "id"
  | "regionId"
  | "name"
  | "address"
  | "city"
  | "status"
  | "latitude"
  | "longitude"
  | "positionLocked"
> & { phone: string | null };

type VisitWithEvents = Visit & { events: VisitEvent[] };

/** A responsable's plan: visits to the stores and grossistes of their region, and the proof of being there. */
@Injectable()
export class PlanningService {
  constructor(private readonly db: Database) {}

  // ───────────────────────────── Visits ─────────────────────────────

  private responsable(actor: Actor) {
    requireRule(
      actor.role === "RESPONSABLE" && actor.regionId,
      "FORBIDDEN",
      "Only a responsable plans visits.",
      403,
    );
  }

  private async place(
    tx: Tx,
    kind: LocationKind,
    id: string,
  ): Promise<Place | null> {
    const row: Pdv | Depot | null =
      kind === "PDV"
        ? await tx.pdv.findUnique({ where: { id } })
        : await tx.depot.findUnique({ where: { id } });
    return row ? { ...row, phone: row.phone ?? null } : null;
  }

  private async ownPlace(tx: Tx, actor: Actor, kind: LocationKind, id: string) {
    const place = await this.place(tx, kind, id);
    requireRule(
      place && place.regionId === actor.regionId,
      "PLACE_NOT_FOUND",
      "Choose a store or a grossiste of your region.",
      404,
    );
    requireRule(
      place.status === "ACTIVE",
      "PLACE_INACTIVE",
      "This place is not active.",
    );
    return place;
  }

  private async assertRoom(
    tx: Tx,
    actor: Actor,
    start: Date,
    end: Date,
    day: string,
    except: string | null,
    allowOverlap?: boolean,
  ) {
    const count = await tx.visit.count({
      where: {
        responsableId: actor.id,
        day: dayToDate(day),
        status: { not: "CANCELLED" },
        ...(except && { id: { not: except } }),
      },
    });
    requireRule(
      count < MAX_VISITS_PER_DAY,
      "TOO_MANY_VISITS",
      "That day already has twenty visits.",
    );
    if (allowOverlap) return;
    const clash = await tx.visit.findFirst({
      where: {
        responsableId: actor.id,
        status: { in: ["PLANNED", "ON_SITE"] },
        plannedStart: { lt: end },
        plannedEnd: { gt: start },
        ...(except && { id: { not: except } }),
      },
      select: { id: true, plannedStart: true, plannedEnd: true },
    });
    if (clash)
      throw new DomainError(
        "VISIT_OVERLAP",
        "Another visit covers some of this time.",
        409,
        {
          existing: {
            id: clash.id,
            plannedStart: clash.plannedStart,
            plannedEnd: clash.plannedEnd,
          },
        },
      );
  }

  private period(start: Date, durationMinutes: number) {
    const end = new Date(start.getTime() + durationMinutes * MINUTE);
    return { end, day: tunisDay(start) };
  }

  create(actor: Actor, input: VisitInput) {
    this.responsable(actor);
    const { end, day } = this.period(input.start, input.durationMinutes);
    requireRule(
      day >= tunisDay(new Date()),
      "INVALID_DATE",
      "A visit cannot be planned in the past.",
    );
    return this.db.run(actor, async (tx) => {
      await this.ownPlace(tx, actor, input.targetKind, input.targetId);
      await this.assertRoom(
        tx,
        actor,
        input.start,
        end,
        day,
        null,
        input.allowOverlap,
      );
      const visit = await tx.visit.create({
        data: {
          regionId: actor.regionId!,
          responsableId: actor.id,
          targetKind: input.targetKind,
          targetId: input.targetId,
          kind: input.kind,
          plannedStart: input.start,
          plannedEnd: end,
          day: dayToDate(day),
          note: input.note?.trim() || null,
        },
        include: { events: true },
      });
      await audit(
        tx,
        actor,
        "visit.planned",
        "Visit",
        visit.id,
        { targetKind: input.targetKind, targetId: input.targetId, day },
        actor.regionId,
      );
      return (await this.present(tx, [visit]))[0]!;
    });
  }

  update(
    actor: Actor,
    id: string,
    input: Partial<Omit<VisitInput, "kind">> & { kind?: VisitKind },
  ) {
    this.responsable(actor);
    return this.db.run(actor, async (tx) => {
      const visit = await this.mine(tx, actor, id);
      requireRule(
        visit.status === "PLANNED",
        "INVALID_STATE",
        "Only a planned visit can be changed.",
        409,
      );
      const start = input.start ?? visit.plannedStart;
      const minutes =
        input.durationMinutes ??
        Math.round(
          (visit.plannedEnd.getTime() - visit.plannedStart.getTime()) / MINUTE,
        );
      const { end, day } = this.period(start, minutes);
      requireRule(
        day >= tunisDay(new Date()),
        "INVALID_DATE",
        "A visit cannot be planned in the past.",
      );
      const targetKind = input.targetKind ?? visit.targetKind;
      const targetId = input.targetId ?? visit.targetId;
      if (targetKind !== visit.targetKind || targetId !== visit.targetId)
        await this.ownPlace(tx, actor, targetKind, targetId);
      await this.assertRoom(tx, actor, start, end, day, id, input.allowOverlap);
      const moved = start.getTime() !== visit.plannedStart.getTime();
      const updated = await tx.visit.update({
        where: { id },
        data: {
          targetKind,
          targetId,
          kind: input.kind ?? visit.kind,
          plannedStart: start,
          plannedEnd: end,
          day: dayToDate(day),
          note:
            input.note === undefined ? visit.note : input.note.trim() || null,
          revision: { increment: 1 },
          // A visit moved to another time is reminded again.
          ...(moved && { reminderSentAt: null }),
        },
        include: { events: true },
      });
      await audit(
        tx,
        actor,
        "visit.changed",
        "Visit",
        id,
        { day },
        actor.regionId,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  cancel(actor: Actor, id: string) {
    this.responsable(actor);
    return this.db.run(actor, async (tx) => {
      const visit = await this.mine(tx, actor, id);
      requireRule(
        visit.status === "PLANNED",
        "INVALID_STATE",
        "Only a planned visit can be cancelled.",
        409,
      );
      const updated = await tx.visit.update({
        where: { id },
        data: {
          status: "CANCELLED",
          cancelledAt: new Date(),
          revision: { increment: 1 },
        },
        include: { events: true },
      });
      await audit(
        tx,
        actor,
        "visit.cancelled",
        "Visit",
        id,
        {},
        actor.regionId,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  private async mine(tx: Tx, actor: Actor, id: string) {
    await this.db.lock(tx, "Visit", id);
    const visit = await tx.visit.findUnique({
      where: { id },
      include: { events: true },
    });
    if (!visit || visit.responsableId !== actor.id) throw notFound("Visit");
    return visit;
  }

  async list(
    actor: Actor,
    filter: {
      from: string;
      to: string;
      responsableId?: string;
      regionId?: string;
      status?: Visit["status"];
    },
  ) {
    requireRule(
      actor.role === "RESPONSABLE" || actor.role === "ADMIN",
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    requireRule(
      filter.to >= filter.from && addDays(filter.from, 120) >= filter.to,
      "INVALID_PERIOD",
      "Ask for at most 120 days.",
    );
    return this.db.run(actor, async (tx) => {
      const visits = await tx.visit.findMany({
        where: {
          day: { gte: dayToDate(filter.from), lte: dayToDate(filter.to) },
          // A responsable sees their own; the admin can narrow down (RLS keeps the test region out).
          ...(actor.role === "RESPONSABLE"
            ? { responsableId: actor.id }
            : {
                ...(filter.responsableId && {
                  responsableId: filter.responsableId,
                }),
                ...(filter.regionId && { regionId: filter.regionId }),
              }),
          ...(filter.status && { status: filter.status }),
        },
        include: { events: true },
        orderBy: [{ plannedStart: "asc" }, { id: "asc" }],
        take: 500,
      });
      return this.present(tx, visits, actor.role === "ADMIN");
    });
  }

  async get(actor: Actor, id: string) {
    requireRule(
      actor.role === "RESPONSABLE" || actor.role === "ADMIN",
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const visit = await tx.visit.findUnique({
        where: { id },
        include: { events: true },
      });
      if (!visit) throw notFound("Visit");
      return (await this.present(tx, [visit], actor.role === "ADMIN"))[0]!;
    });
  }

  // ───────────────────────────── Presence ─────────────────────────────

  /** The moment the person tapped, as their phone says, kept within what a phone without signal can explain. */
  private eventTime(given: Date | undefined) {
    const now = Date.now();
    const at = given ?? new Date(now);
    requireRule(
      at.getTime() <= now + MAX_AHEAD_MS && at.getTime() >= now - MAX_AGE_MS,
      "INVALID_DATE",
      "The time of this check is not possible.",
    );
    return at;
  }

  private async record(
    tx: Tx,
    actor: Actor,
    visit: Visit,
    kind: "CHECK_IN" | "CHECK_OUT",
    occurredAt: Date,
    input: PresenceInput,
    place: Place | null,
  ) {
    const hasPlace = place?.latitude != null && place.longitude != null;
    const placePoint: Point | null = hasPlace
      ? { latitude: place!.latitude!, longitude: place!.longitude! }
      : null;
    const judged = judgePresence({
      place: placePoint,
      fix:
        input.latitude != null && input.longitude != null
          ? { latitude: input.latitude, longitude: input.longitude }
          : null,
      accuracyM: input.accuracyMeters,
      sandbox: actor.sandbox,
    });
    const flags = [...judged.flags];
    if (input.mocked) flags.push("MOCK_LOCATION");
    if (Date.now() - occurredAt.getTime() > LATE_MS) flags.push("LATE_SYNC");
    // Arriving where the position does not match (or with no position at all) is allowed, with a reason.
    if (
      kind === "CHECK_IN" &&
      (judged.verdict === "OUT_OF_RANGE" || judged.verdict === "NO_FIX")
    )
      requireRule(
        (input.reason?.trim().length ?? 0) >= 2,
        "POSITION_REASON_REQUIRED",
        "The position does not match this place: say why.",
      );
    return tx.visitEvent.create({
      data: {
        visitId: visit.id,
        regionId: visit.regionId,
        responsableId: visit.responsableId,
        kind,
        occurredAt,
        latitude: input.latitude ?? null,
        longitude: input.longitude ?? null,
        accuracyM: input.accuracyMeters ?? null,
        distanceM: judged.distanceM,
        verdict: judged.verdict,
        flags,
        reason: input.reason?.trim() || null,
      },
    });
  }

  checkIn(actor: Actor, id: string, input: PresenceInput) {
    this.responsable(actor);
    const occurredAt = this.eventTime(input.occurredAt);
    return this.db.run(actor, async (tx) => {
      const visit = await this.mine(tx, actor, id);
      // The phone may send the same check-in twice (a retry): the first one stands.
      if (visit.events.some((e) => e.kind === "CHECK_IN"))
        return (await this.present(tx, [visit]))[0]!;
      requireRule(
        visit.status === "PLANNED",
        "INVALID_STATE",
        "This visit cannot be started.",
        409,
      );
      requireRule(
        occurredAt.getTime() >= visit.plannedStart.getTime() - EARLY_MS,
        "TOO_EARLY",
        "You can start a visit one hour before it begins.",
      );
      requireRule(
        tunisDay(occurredAt) === dateToDay(visit.day),
        "WRONG_DAY",
        "This visit was planned for another day.",
      );
      const place = await this.place(tx, visit.targetKind, visit.targetId);
      await this.record(tx, actor, visit, "CHECK_IN", occurredAt, input, place);
      const updated = await tx.visit.update({
        where: { id },
        data: {
          status: "ON_SITE",
          checkedInAt: occurredAt,
          revision: { increment: 1 },
        },
        include: { events: true },
      });
      await audit(
        tx,
        actor,
        "visit.checked_in",
        "Visit",
        id,
        {},
        visit.regionId,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  checkOut(actor: Actor, id: string, input: PresenceInput) {
    this.responsable(actor);
    const occurredAt = this.eventTime(input.occurredAt);
    return this.db.run(actor, async (tx) => {
      const visit = await this.mine(tx, actor, id);
      if (visit.events.some((e) => e.kind === "CHECK_OUT"))
        return (await this.present(tx, [visit]))[0]!;
      requireRule(
        visit.status === "ON_SITE" && visit.checkedInAt,
        "INVALID_STATE",
        "Check in before checking out.",
        409,
      );
      requireRule(
        occurredAt.getTime() >= visit.checkedInAt.getTime(),
        "INVALID_DATE",
        "The time of this check is not possible.",
      );
      const place = await this.place(tx, visit.targetKind, visit.targetId);
      await this.record(
        tx,
        actor,
        visit,
        "CHECK_OUT",
        occurredAt,
        input,
        place,
      );
      const updated = await tx.visit.update({
        where: { id },
        data: {
          status: "DONE",
          checkedOutAt: occurredAt,
          revision: { increment: 1 },
        },
        include: { events: true },
      });
      await audit(
        tx,
        actor,
        "visit.checked_out",
        "Visit",
        id,
        {},
        visit.regionId,
      );
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** "I am at this store": a visit nobody planned, started on the spot. The phone picks the id (a retry changes nothing). */
  startUnplanned(
    actor: Actor,
    input: PresenceInput & {
      id: string;
      targetKind: LocationKind;
      targetId: string;
      kind: VisitKind;
    },
  ) {
    this.responsable(actor);
    const occurredAt = this.eventTime(input.occurredAt);
    return this.db.run(actor, async (tx) => {
      const existing = await tx.visit.findUnique({
        where: { id: input.id },
        include: { events: true },
      });
      if (existing) {
        if (existing.responsableId !== actor.id) throw notFound("Visit");
        return (await this.present(tx, [existing]))[0]!;
      }
      const place = await this.ownPlace(
        tx,
        actor,
        input.targetKind,
        input.targetId,
      );
      const day = tunisDay(occurredAt);
      requireRule(
        (await tx.visit.count({
          where: {
            responsableId: actor.id,
            day: dayToDate(day),
            status: { not: "CANCELLED" },
          },
        })) < MAX_VISITS_PER_DAY,
        "TOO_MANY_VISITS",
        "That day already has twenty visits.",
      );
      const visit = await tx.visit.create({
        data: {
          id: input.id,
          regionId: actor.regionId!,
          responsableId: actor.id,
          targetKind: input.targetKind,
          targetId: input.targetId,
          kind: input.kind,
          plannedStart: occurredAt,
          plannedEnd: new Date(occurredAt.getTime() + 60 * MINUTE),
          day: dayToDate(day),
          status: "ON_SITE",
          unplanned: true,
          checkedInAt: occurredAt,
        },
      });
      await this.record(tx, actor, visit, "CHECK_IN", occurredAt, input, place);
      await audit(
        tx,
        actor,
        "visit.unplanned",
        "Visit",
        visit.id,
        { targetKind: input.targetKind, targetId: input.targetId },
        actor.regionId,
      );
      const full = await tx.visit.findUniqueOrThrow({
        where: { id: visit.id },
        include: { events: true },
      });
      return (await this.present(tx, [full]))[0]!;
    });
  }

  // ───────────────────────────── Positions of the places ─────────────────────────────

  /**
   * Where a place is. The responsable fixes it once, on site, with a good reading; after that only the
   * admin moves it, so a visit is never checked against a position its own responsable could shift.
   */
  async setPosition(
    actor: Actor,
    kind: LocationKind,
    id: string,
    input: {
      latitude: number;
      longitude: number;
      accuracyMeters?: number;
      locked?: boolean;
    },
  ) {
    requireRule(
      actor.role === "RESPONSABLE" || actor.role === "ADMIN",
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const place = await this.place(tx, kind, id);
      if (!place) throw notFound("Place");
      if (actor.role === "RESPONSABLE") {
        requireRule(
          place.regionId === actor.regionId,
          "PLACE_NOT_FOUND",
          "Choose a store or a grossiste of your region.",
          404,
        );
        requireRule(
          place.latitude == null && !place.positionLocked,
          "POSITION_FIXED",
          "This place already has a position. Ask the admin to change it.",
          403,
        );
        requireRule(
          input.accuracyMeters != null &&
            input.accuracyMeters <= MAX_POSITION_ACCURACY_M,
          "LOW_ACCURACY",
          "The position is not precise enough. Wait for a better signal, outdoors if you can.",
        );
      }
      requireRule(
        actor.sandbox || inTunisia(input),
        "OUTSIDE_TUNISIA",
        "This position is outside Tunisia.",
      );
      const data = {
        latitude: input.latitude,
        longitude: input.longitude,
        positionAccuracyM: input.accuracyMeters ?? null,
        positionSetById: actor.id,
        positionSetAt: new Date(),
        ...(actor.role === "ADMIN" &&
          input.locked !== undefined && { positionLocked: input.locked }),
      };
      if (kind === "PDV") await tx.pdv.update({ where: { id }, data });
      else await tx.depot.update({ where: { id }, data });
      await audit(
        tx,
        actor,
        "place.position_set",
        kind === "PDV" ? "Pdv" : "Depot",
        id,
        {
          latitude: input.latitude,
          longitude: input.longitude,
          accuracyMeters: input.accuracyMeters ?? null,
          previous:
            place.latitude == null ? null : [place.latitude, place.longitude],
        },
        place.regionId,
      );
      return {
        kind,
        id,
        latitude: input.latitude,
        longitude: input.longitude,
        positionLocked:
          actor.role === "ADMIN" && input.locked !== undefined
            ? input.locked
            : place.positionLocked,
      };
    });
  }

  // ───────────────────────────── Preferences and the calendar link ─────────────────────────────

  async preferences(actor: Actor) {
    this.responsable(actor);
    return this.db.run(actor, async (tx) => {
      const row = await tx.planningPreference.findUnique({
        where: { userId: actor.id },
      });
      return {
        leadMinutes: row?.leadMinutes ?? 60,
        eveningSummary: row?.eveningSummary ?? true,
      };
    });
  }

  async setPreferences(
    actor: Actor,
    input: { leadMinutes?: number; eveningSummary?: boolean },
  ) {
    this.responsable(actor);
    requireRule(
      input.leadMinutes === undefined ||
        (LEAD_CHOICES as readonly number[]).includes(input.leadMinutes),
      "INVALID_LEAD",
      "Choose none, 15, 30, 60 or 120 minutes.",
    );
    await this.db.run(actor, (tx) =>
      tx.planningPreference.upsert({
        where: { userId: actor.id },
        create: { userId: actor.id, ...input },
        update: input,
      }),
    );
    return this.preferences(actor);
  }

  private feedUrl(token: string) {
    const base = (
      process.env.API_PUBLIC_URL ?? "https://api.galylio.com"
    ).replace(/\/$/, "");
    return {
      url: `${base}/cal/${token}.ics`,
      webcal: `${base.replace(/^https?:/, "webcal:")}/cal/${token}.ics`,
    };
  }

  async calendarLink(actor: Actor, rotate = false) {
    this.responsable(actor);
    return this.db.run(actor, async (tx) => {
      const existing = await tx.calendarFeed.findUnique({
        where: { userId: actor.id },
      });
      if (existing && !rotate) return this.feedUrl(existing.token);
      // 32 random bytes: nobody can guess a link, and a new one makes the old one stop working.
      const token = randomBytes(32).toString("base64url");
      await tx.calendarFeed.upsert({
        where: { userId: actor.id },
        create: { userId: actor.id, token },
        update: { token, createdAt: new Date() },
      });
      return this.feedUrl(token);
    });
  }

  /** The calendar behind a secret link (no sign-in: the link is the key). Null when the link is not valid. */
  async calendar(token: string, now = new Date()) {
    return this.db.run("SYSTEM", async (tx) => {
      const feed = await tx.calendarFeed.findUnique({ where: { token } });
      if (!feed) return null;
      const user = await tx.user.findUnique({
        where: { id: feed.userId },
        select: { id: true, locale: true, role: true, status: true },
      });
      if (!user || user.role !== "RESPONSABLE" || user.status !== "ACTIVE")
        return null;
      const prefs = await tx.planningPreference.findUnique({
        where: { userId: user.id },
      });
      const today = tunisDay(now);
      const visits = await tx.visit.findMany({
        where: {
          responsableId: user.id,
          day: {
            gte: dayToDate(addDays(today, -FEED_DAYS_BACK)),
            lte: dayToDate(addDays(today, FEED_DAYS_AHEAD)),
          },
          // A missed visit is no appointment any more; a cancelled one stays (as cancelled) so the calendar drops it.
          status: { not: "MISSED" },
        },
        orderBy: { plannedStart: "asc" },
      });
      const places = await this.places(tx, visits);
      const rows: FeedVisit[] = visits.map((v) => {
        const p = places.get(`${v.targetKind}:${v.targetId}`);
        return {
          id: v.id,
          revision: v.revision,
          kind: v.kind,
          status: v.status,
          plannedStart: v.plannedStart,
          plannedEnd: v.plannedEnd,
          updatedAt: v.updatedAt,
          note: v.note,
          place: p?.name ?? "?",
          address: p?.address ?? "",
          city: p?.city ?? "",
          latitude: p?.latitude ?? null,
          longitude: p?.longitude ?? null,
        };
      });
      return buildCalendar(rows, {
        locale: user.locale === "en" ? "en" : "fr",
        leadMinutes: prefs?.leadMinutes ?? 60,
        now,
      });
    });
  }

  // ───────────────────────────── The admin's overview ─────────────────────────────

  /** Per responsable, over a period: what was planned, done, missed, and what the check-ins said. */
  async overview(
    actor: Actor,
    filter: { from: string; to: string; regionId?: string },
  ) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Not allowed.", 403);
    requireRule(
      filter.to >= filter.from && addDays(filter.from, 400) >= filter.to,
      "INVALID_PERIOD",
      "Ask for at most 400 days.",
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.$queryRaw<
        {
          responsableId: string;
          name: string;
          regionId: string;
          region: string;
          planned: number;
          done: number;
          missed: number;
          onSite: number;
          cancelled: number;
          unplanned: number;
          verified: number;
          outOfRange: number;
          noFix: number;
          flagged: number;
          avgMinutes: number | null;
        }[]
      >`
        SELECT v."responsableId", u.name, v."regionId", r.name AS region,
          COUNT(DISTINCT v.id) FILTER (WHERE v.status <> 'CANCELLED' AND NOT v.unplanned)::int AS planned,
          COUNT(DISTINCT v.id) FILTER (WHERE v.status = 'DONE')::int AS done,
          COUNT(DISTINCT v.id) FILTER (WHERE v.status = 'MISSED')::int AS missed,
          COUNT(DISTINCT v.id) FILTER (WHERE v.status = 'ON_SITE')::int AS "onSite",
          COUNT(DISTINCT v.id) FILTER (WHERE v.status = 'CANCELLED')::int AS cancelled,
          COUNT(DISTINCT v.id) FILTER (WHERE v.unplanned)::int AS unplanned,
          COUNT(e.id) FILTER (WHERE e.kind = 'CHECK_IN' AND e.verdict IN ('VERIFIED','SANDBOX'))::int AS verified,
          COUNT(e.id) FILTER (WHERE e.kind = 'CHECK_IN' AND e.verdict = 'OUT_OF_RANGE')::int AS "outOfRange",
          COUNT(e.id) FILTER (WHERE e.kind = 'CHECK_IN' AND e.verdict IN ('NO_FIX','NO_POSITION'))::int AS "noFix",
          COUNT(e.id) FILTER (WHERE cardinality(e.flags) > 0)::int AS flagged,
          ROUND(AVG(EXTRACT(EPOCH FROM (v."checkedOutAt" - v."checkedInAt")) / 60)
            FILTER (WHERE v.status = 'DONE' AND v."checkedOutAt" IS NOT NULL))::int AS "avgMinutes"
        FROM "Visit" v
        JOIN "User" u ON u.id = v."responsableId"
        JOIN "Region" r ON r.id = v."regionId"
        LEFT JOIN "VisitEvent" e ON e."visitId" = v.id
        WHERE v.day BETWEEN ${filter.from}::date AND ${filter.to}::date
          ${filter.regionId ? Prisma.sql`AND v."regionId" = ${filter.regionId}::uuid` : Prisma.sql``}
        GROUP BY v."responsableId", u.name, v."regionId", r.name
        ORDER BY r.name, u.name`;
      return { from: filter.from, to: filter.to, responsables: rows };
    });
  }

  // ───────────────────────────── Presenting ─────────────────────────────

  private async places(
    tx: Tx,
    visits: Pick<Visit, "targetKind" | "targetId">[],
  ) {
    const pdvIds = [
      ...new Set(
        visits.filter((v) => v.targetKind === "PDV").map((v) => v.targetId),
      ),
    ];
    const depotIds = [
      ...new Set(
        visits.filter((v) => v.targetKind === "DEPOT").map((v) => v.targetId),
      ),
    ];
    const [pdvs, depots] = await Promise.all([
      pdvIds.length ? tx.pdv.findMany({ where: { id: { in: pdvIds } } }) : [],
      depotIds.length
        ? tx.depot.findMany({ where: { id: { in: depotIds } } })
        : [],
    ]);
    const map = new Map<string, Place>();
    for (const p of pdvs)
      map.set(`PDV:${p.id}`, { ...p, phone: p.phone ?? null });
    for (const d of depots)
      map.set(`DEPOT:${d.id}`, { ...d, phone: d.phone ?? null });
    return map;
  }

  private async present(
    tx: Tx,
    visits: VisitWithEvents[],
    withResponsable = false,
  ) {
    const places = await this.places(tx, visits);
    const people = withResponsable
      ? new Map(
          (
            await tx.user.findMany({
              where: {
                id: { in: [...new Set(visits.map((v) => v.responsableId))] },
              },
              select: { id: true, name: true },
            })
          ).map((u) => [u.id, u.name]),
        )
      : null;
    return visits.map((v) => {
      const p = places.get(`${v.targetKind}:${v.targetId}`);
      return {
        id: v.id,
        kind: v.kind,
        status: v.status,
        unplanned: v.unplanned,
        plannedStart: v.plannedStart,
        plannedEnd: v.plannedEnd,
        day: dateToDay(v.day),
        note: v.note,
        revision: v.revision,
        checkedInAt: v.checkedInAt,
        checkedOutAt: v.checkedOutAt,
        // The earliest moment the phone offers "I'm here".
        canStartFrom: new Date(v.plannedStart.getTime() - EARLY_MS),
        responsable: people
          ? { id: v.responsableId, name: people.get(v.responsableId) ?? "?" }
          : undefined,
        target: {
          kind: v.targetKind,
          id: v.targetId,
          name: p?.name ?? "?",
          address: p?.address ?? "",
          city: p?.city ?? "",
          phone: p?.phone ?? null,
          latitude: p?.latitude ?? null,
          longitude: p?.longitude ?? null,
          hasPosition: p?.latitude != null,
          positionLocked: p?.positionLocked ?? false,
        },
        events: [...v.events]
          .sort((a, b) => a.occurredAt.getTime() - b.occurredAt.getTime())
          .map((e) => ({
            kind: e.kind,
            occurredAt: e.occurredAt,
            verdict: e.verdict,
            distanceM: e.distanceM,
            accuracyM: e.accuracyM,
            latitude: e.latitude,
            longitude: e.longitude,
            flags: e.flags,
            reason: e.reason,
          })),
      };
    });
  }
}
