import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Account,
  type Api,
} from "./helpers";
import { approvedPdv, buildWorld, type World } from "./world";
import argon2 from "argon2";
import { Database } from "../src/core/database";
import { addDays, tunisDay } from "../src/core/dates";
import {
  closeVisitDay,
  purgeOldVisits,
  sendEveningPlans,
  sendVisitReminders,
} from "../src/jobs/visits";

let api: Api;
let w: World;
let db: Database;
let pdv: { id: string };
let sudPdv: { id: string };
const today = () => tunisDay(new Date());
const tomorrow = () => addDays(today(), 1);
/** 10:00 Tunis time (UTC+1) on a day. */
const at10 = (day: string) => new Date(`${day}T09:00:00Z`).toISOString();
const MIN = 60_000;
/** A visit that starts now (same Tunis day whatever the hour). */
const nowStart = () => new Date(Date.now() - MIN).toISOString();

const tunis = { latitude: 36.8065, longitude: 10.1815 };
const north = (m: number) => ({
  latitude: tunis.latitude + m / 111_195,
  longitude: tunis.longitude,
});

beforeAll(async () => {
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api?.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  pdv = await approvedPdv(w, "n", "Para Nord");
  sudPdv = await approvedPdv(w, "s", "Para Sud");
});

const plan = (over: object = {}) => ({
  targetKind: "PDV",
  targetId: pdv.id,
  kind: "COUNT",
  start: at10(tomorrow()),
  durationMinutes: 60,
  ...over,
});
const range = () => `from=${today()}&to=${addDays(today(), 30)}`;

async function inbox(account: Account) {
  const ownerDb = await owner();
  try {
    return (
      await ownerDb.query<{ key: string; params: any }>(
        `SELECT key, params FROM "Notification" WHERE "userId" = $1 ORDER BY "createdAt"`,
        [account.id],
      )
    ).rows;
  } finally {
    await ownerDb.end();
  }
}

describe("planning visits", () => {
  it("a responsable plans a visit to a place of their region and sees it in their calendar", async () => {
    const made = await w.n.post(
      "/v1/visits",
      plan({ note: "Count the serums" }),
    );
    expect(made.status).toBe(201);
    expect(made.body).toMatchObject({
      kind: "COUNT",
      status: "PLANNED",
      day: tomorrow(),
      note: "Count the serums",
      unplanned: false,
      target: { kind: "PDV", name: "Para Nord", hasPosition: false },
    });
    const list = (await w.n.get(`/v1/visits?${range()}`)).body;
    expect(list.map((v: any) => v.id)).toEqual([made.body.id]);
  });

  it("is for responsables only, and each sees only their own region", async () => {
    const seller = await createAccount({ role: "VENDEUR", pdvId: pdv.id });
    expect(
      (await client(api, seller.token).post("/v1/visits", plan())).status,
    ).toBe(403);
    expect(
      (await client(api, seller.token).get(`/v1/visits?${range()}`)).status,
    ).toBe(403);
    // The admin reads, never plans.
    expect((await w.a.post("/v1/visits", plan())).status).toBe(403);

    const made = (await w.n.post("/v1/visits", plan())).body;
    expect((await w.s.get(`/v1/visits?${range()}`)).body).toEqual([]);
    expect((await w.s.get(`/v1/visits/${made.id}`)).status).toBe(404);
    expect(
      (await w.s.patch(`/v1/visits/${made.id}`, { note: "mine now" })).status,
    ).toBe(404);
    expect((await w.s.post(`/v1/visits/${made.id}/cancel`)).status).toBe(404);
    // The other region's store is refused for a visit.
    const wrong = await w.n.post("/v1/visits", plan({ targetId: sudPdv.id }));
    expect(wrong.body.code).toBe("PLACE_NOT_FOUND");

    const seen = (await w.a.get(`/v1/visits?${range()}`)).body;
    expect(seen).toHaveLength(1);
    expect(seen[0].responsable.name).toBe("Nora Nord");
  });

  it("refuses the past, two visits at the same time (unless confirmed), and a depot of another region", async () => {
    const past = await w.n.post(
      "/v1/visits",
      plan({ start: at10(addDays(today(), -1)) }),
    );
    expect(past.body.code).toBe("INVALID_DATE");
    expect((await w.n.post("/v1/visits", plan())).status).toBe(201);
    const clash = await w.n.post(
      "/v1/visits",
      plan({
        start: new Date(Date.parse(at10(tomorrow())) + 30 * MIN).toISOString(),
      }),
    );
    expect(clash.status).toBe(409);
    expect(clash.body.code).toBe("VISIT_OVERLAP");
    expect(
      (
        await w.n.post(
          "/v1/visits",
          plan({
            start: new Date(
              Date.parse(at10(tomorrow())) + 30 * MIN,
            ).toISOString(),
            allowOverlap: true,
          }),
        )
      ).status,
    ).toBe(201);
    // The grossiste of Nord is a valid place for Nord, not for Sud.
    expect(
      (
        await w.n.post(
          "/v1/visits",
          plan({
            targetKind: "DEPOT",
            targetId: w.depotId,
            start: at10(addDays(today(), 2)),
          }),
        )
      ).status,
    ).toBe(201);
    expect(
      (
        await w.s.post(
          "/v1/visits",
          plan({ targetKind: "DEPOT", targetId: w.depotId }),
        )
      ).body.code,
    ).toBe("PLACE_NOT_FOUND");
  });

  it("moves, changes and cancels a planned visit, and a calendar app is told by the revision", async () => {
    const made = (await w.n.post("/v1/visits", plan())).body;
    const moved = await w.n.patch(`/v1/visits/${made.id}`, {
      start: at10(addDays(today(), 3)),
      note: "New day",
      kind: "TRAINING",
    });
    expect(moved.body).toMatchObject({
      day: addDays(today(), 3),
      note: "New day",
      kind: "TRAINING",
      revision: 1,
    });
    const cancelled = await w.n.post(`/v1/visits/${made.id}/cancel`);
    expect(cancelled.body).toMatchObject({ status: "CANCELLED", revision: 2 });
    expect(
      (await w.n.patch(`/v1/visits/${made.id}`, { note: "x" })).body.code,
    ).toBe("INVALID_STATE");
  });
});

describe("the position of a place", () => {
  const set = (c: typeof w.n, id: string, body: object) =>
    c.put(`/v1/planning/positions/pdv/${id}`, body);

  it("is fixed once on site by the responsable with a good reading, then only the admin moves it", async () => {
    expect(
      (await set(w.n, pdv.id, { ...tunis, accuracyMeters: 80 })).body.code,
    ).toBe("LOW_ACCURACY");
    expect((await set(w.n, pdv.id, tunis)).body.code).toBe("LOW_ACCURACY");
    expect(
      (
        await set(w.n, pdv.id, {
          latitude: 10.18,
          longitude: 36.8,
          accuracyMeters: 10,
        })
      ).body.code,
    ).toBe("OUTSIDE_TUNISIA");
    const done = await set(w.n, pdv.id, { ...tunis, accuracyMeters: 12 });
    expect(done.status).toBe(200);
    expect(
      (await set(w.n, pdv.id, { ...north(500), accuracyMeters: 12 })).body.code,
    ).toBe("POSITION_FIXED");
    // Another region's responsable cannot touch it.
    expect(
      (await set(w.s, pdv.id, { ...tunis, accuracyMeters: 10 })).status,
    ).toBe(404);
    // The admin corrects it and locks it.
    const fixed = await set(w.a, pdv.id, { ...north(300), locked: true });
    expect(fixed.body).toMatchObject({ positionLocked: true });
    const visit = (await w.n.post("/v1/visits", plan())).body;
    expect(visit.target).toMatchObject({
      hasPosition: true,
      positionLocked: true,
    });
    // The change is in the history.
    const ownerDb = await owner();
    const audit = await ownerDb.query(
      `SELECT action FROM "AuditEntry" WHERE action = 'place.position_set' ORDER BY "createdAt"`,
    );
    await ownerDb.end();
    expect(audit.rows).toHaveLength(2);
  });
});

describe("arriving and leaving", () => {
  async function started(reason?: object, place = true) {
    if (place)
      await w.n.put(`/v1/planning/positions/pdv/${pdv.id}`, {
        ...tunis,
        accuracyMeters: 10,
      });
    return (
      await w.n.post(
        "/v1/visits",
        plan({ start: nowStart(), allowOverlap: true }),
      )
    ).body;
  }

  it("verifies a check-in at the place, then a check-out closes the visit", async () => {
    const visit = await started();
    const arrived = await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      ...north(60),
      accuracyMeters: 15,
    });
    expect(arrived.status).toBe(201);
    expect(arrived.body.status).toBe("ON_SITE");
    expect(arrived.body.events[0]).toMatchObject({
      kind: "CHECK_IN",
      verdict: "VERIFIED",
      flags: [],
    });
    expect(arrived.body.events[0].distanceM).toBeGreaterThan(55);
    // A retry changes nothing.
    const again = await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      ...north(60),
      accuracyMeters: 15,
    });
    expect(again.body.events).toHaveLength(1);
    const left = await w.n.post(`/v1/visits/${visit.id}/check-out`, {
      ...north(900),
      accuracyMeters: 20,
    });
    expect(left.body.status).toBe("DONE");
    // Leaving far away is no problem and needs no reason.
    expect(left.body.events.map((e: any) => [e.kind, e.verdict])).toEqual([
      ["CHECK_IN", "VERIFIED"],
      ["CHECK_OUT", "OUT_OF_RANGE"],
    ]);
  });

  it("allows a check-in away from the place or without a position, but asks why, and marks it", async () => {
    const visit = await started();
    const far = await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      ...north(2000),
      accuracyMeters: 10,
    });
    expect(far.status).toBe(422);
    expect(far.body.code).toBe("POSITION_REASON_REQUIRED");
    const none = await w.n.post(`/v1/visits/${visit.id}/check-in`, {});
    expect(none.body.code).toBe("POSITION_REASON_REQUIRED");
    const ok = await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      reason: "Phone had no signal",
      mocked: true,
    });
    expect(ok.status).toBe(201);
    expect(ok.body.events[0]).toMatchObject({
      verdict: "NO_FIX",
      reason: "Phone had no signal",
      flags: ["MOCK_LOCATION"],
    });
  });

  it("marks a check-in sent long after the tap, and refuses an impossible time", async () => {
    const visit = await started();
    const late = new Date(Date.now() - 40 * MIN).toISOString();
    const r = await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      ...north(20),
      accuracyMeters: 10,
      occurredAt: late,
    });
    expect(r.body.events[0].flags).toEqual(["LATE_SYNC"]);
    const other = await started();
    const future = await w.n.post(`/v1/visits/${other.id}/check-in`, {
      occurredAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    expect(future.body.code).toBe("INVALID_DATE");
  });

  it("does not start a visit of another day or long before it, and does not check out before checking in", async () => {
    const later = (await w.n.post("/v1/visits", plan())).body;
    const early = await w.n.post(`/v1/visits/${later.id}/check-in`, {
      ...tunis,
      accuracyMeters: 10,
    });
    expect(["WRONG_DAY", "TOO_EARLY"]).toContain(early.body.code);
    const todayVisit = (
      await w.n.post("/v1/visits", plan({ start: nowStart() }))
    ).body;
    expect(
      (await w.n.post(`/v1/visits/${todayVisit.id}/check-out`, {})).body.code,
    ).toBe("INVALID_STATE");
    expect((await w.n.post(`/v1/visits/${todayVisit.id}/cancel`)).status).toBe(
      201,
    );
    expect(
      (await w.n.post(`/v1/visits/${todayVisit.id}/check-in`, {})).body.code,
    ).toBe("INVALID_STATE");
  });

  it("records an unplanned visit on the spot, once, and only another responsable's place is refused", async () => {
    await w.n.put(`/v1/planning/positions/pdv/${pdv.id}`, {
      ...tunis,
      accuracyMeters: 10,
    });
    const id = randomUUID();
    const body = {
      id,
      targetKind: "PDV",
      targetId: pdv.id,
      kind: "FOLLOW_UP",
      ...north(30),
      accuracyMeters: 10,
    };
    const first = await w.n.post("/v1/visits/unplanned", body);
    expect(first.status).toBe(201);
    expect(first.body).toMatchObject({ status: "ON_SITE", unplanned: true });
    expect(first.body.events[0].verdict).toBe("VERIFIED");
    const retry = await w.n.post("/v1/visits/unplanned", body);
    expect(retry.body.id).toBe(first.body.id);
    expect((await w.n.get(`/v1/visits?${range()}`)).body).toHaveLength(1);
    expect(
      (await w.s.post("/v1/visits/unplanned", { ...body, id: randomUUID() }))
        .body.code,
    ).toBe("PLACE_NOT_FOUND");
  });

  it("keeps the evidence: it cannot be changed or deleted", async () => {
    const visit = await started();
    await w.n.post(`/v1/visits/${visit.id}/check-in`, {
      ...north(10),
      accuracyMeters: 10,
    });
    const ownerDb = await owner();
    try {
      await expect(
        ownerDb.query(
          `UPDATE "VisitEvent" SET verdict = 'VERIFIED', reason = 'edited'`,
        ),
      ).rejects.toThrow(/append-only/);
      await expect(ownerDb.query(`DELETE FROM "VisitEvent"`)).rejects.toThrow(
        /append-only/,
      );
      // Younger than twelve months, the purge keeps everything.
      await purgeOldVisits(db);
      expect((await ownerDb.query(`SELECT 1 FROM "VisitEvent"`)).rowCount).toBe(
        1,
      );
      // Twelve months later the visit goes, with its evidence (the guard is lifted only to age the test data).
      await ownerDb.query(
        `ALTER TABLE "VisitEvent" DISABLE TRIGGER "VisitEvent_append_only"`,
      );
      await ownerDb.query(
        `UPDATE "VisitEvent" SET "receivedAt" = now() - interval '13 months'`,
      );
      await ownerDb.query(
        `ALTER TABLE "VisitEvent" ENABLE TRIGGER "VisitEvent_append_only"`,
      );
      await ownerDb.query(
        `UPDATE "Visit" SET day = (now() - interval '13 months')::date`,
      );
      await purgeOldVisits(db);
      expect((await ownerDb.query(`SELECT 1 FROM "Visit"`)).rowCount).toBe(0);
      expect((await ownerDb.query(`SELECT 1 FROM "VisitEvent"`)).rowCount).toBe(
        0,
      );
    } finally {
      await ownerDb.end();
    }
  });
});

describe("the calendar link", () => {
  it("is private to the responsable, shows only their visits, and stops working when renewed", async () => {
    await w.n.post("/v1/visits", plan({ note: "Bring the form" }));
    await w.s.post(
      "/v1/visits",
      plan({ targetId: sudPdv.id, kind: "DELIVERY" }),
    );
    const seller = await createAccount({ role: "VENDEUR", pdvId: pdv.id });
    expect(
      (await client(api, seller.token).get("/v1/planning/calendar-link"))
        .status,
    ).toBe(403);
    expect((await w.a.get("/v1/planning/calendar-link")).status).toBe(403);

    const link = (await w.n.get("/v1/planning/calendar-link")).body;
    expect(link.url).toMatch(/\/cal\/[A-Za-z0-9_-]{43}\.ics$/);
    expect(link.webcal.startsWith("webcal:")).toBe(true);
    expect((await w.n.get("/v1/planning/calendar-link")).body.url).toBe(
      link.url,
    );

    const path = new URL(link.url).pathname;
    const res = await fetch(`${api.url}${path}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/calendar");
    expect(res.headers.get("cache-control")).toContain("no-store");
    const text = await res.text();
    expect(text).toContain("BEGIN:VEVENT");
    expect(text).toContain("Para Nord");
    expect(text).toContain("Bring the form");
    expect(text).not.toContain("Para Sud");

    const renewed = (await w.n.post("/v1/planning/calendar-link/rotate")).body;
    expect(renewed.url).not.toBe(link.url);
    expect((await fetch(`${api.url}${path}`)).status).toBe(404);
    expect(
      (await fetch(`${api.url}${new URL(renewed.url).pathname}`)).status,
    ).toBe(200);
    expect((await fetch(`${api.url}/cal/${"a".repeat(43)}.ics`)).status).toBe(
      404,
    );
    expect((await fetch(`${api.url}/cal/not-a-token.ics`)).status).toBe(404);
  });

  it("expires after a year: the old link stops, and the app hands out a fresh one", async () => {
    const link = (await w.n.get("/v1/planning/calendar-link")).body;
    const path = new URL(link.url).pathname;
    expect((await fetch(`${api.url}${path}`)).status).toBe(200);
    const o = await owner();
    try {
      await o.query(
        `UPDATE "CalendarFeed" SET "createdAt" = now() - interval '366 days'`,
      );
    } finally {
      await o.end();
    }
    expect((await fetch(`${api.url}${path}`)).status).toBe(404);
    const fresh = (await w.n.get("/v1/planning/calendar-link")).body;
    expect(fresh.url).not.toBe(link.url);
    expect(
      (await fetch(`${api.url}${new URL(fresh.url).pathname}`)).status,
    ).toBe(200);
  });

  it("drops a deactivated responsable's calendar", async () => {
    const link = (await w.n.get("/v1/planning/calendar-link")).body;
    const ownerDb = await owner();
    await ownerDb.query(
      `UPDATE "User" SET status = 'SUSPENDED' WHERE id = $1`,
      [w.nord.id],
    );
    await ownerDb.end();
    expect(
      (await fetch(`${api.url}${new URL(link.url).pathname}`)).status,
    ).toBe(404);
  });
});

describe("reminders and the day's end", () => {
  it("reminds once, at the chosen lead, and never for a visit planned after that time", async () => {
    const soon = new Date(Date.now() + 61 * MIN);
    const made = (
      await w.n.post("/v1/visits", plan({ start: soon.toISOString() }))
    ).body;
    const tooLate = (
      await w.n.post(
        "/v1/visits",
        plan({
          start: new Date(Date.now() + 130 * MIN).toISOString(),
          allowOverlap: true,
        }),
      )
    ).body;
    const near = (
      await w.n.post(
        "/v1/visits",
        plan({
          start: new Date(Date.now() + 20 * MIN).toISOString(),
          allowOverlap: true,
        }),
      )
    ).body;

    await sendVisitReminders(db, new Date(Date.now() + 2 * MIN));
    const first = (await inbox(w.nord)).filter(
      (n) => n.key === "visit.reminder",
    );
    expect(first).toHaveLength(1);
    expect(first[0]!.params.place).toBe("Para Nord");
    // Once only; a visit planned 20 minutes ahead was just seen by its owner, so no reminder.
    await sendVisitReminders(db, new Date(Date.now() + 3 * MIN));
    expect(
      (await inbox(w.nord)).filter((n) => n.key === "visit.reminder"),
    ).toHaveLength(1);
    // The 130-minute one comes later, at its own time.
    await sendVisitReminders(db, new Date(Date.now() + 75 * MIN));
    expect(
      (await inbox(w.nord)).filter((n) => n.key === "visit.reminder"),
    ).toHaveLength(2);
    expect([made.id, tooLate.id, near.id]).toHaveLength(3);
  });

  it("follows the chosen lead, and none at all when turned off", async () => {
    expect((await w.n.get("/v1/planning/preferences")).body).toEqual({
      leadMinutes: 60,
      eveningSummary: true,
    });
    expect(
      (await w.n.put("/v1/planning/preferences", { leadMinutes: 45 })).body
        .code,
    ).toBe("INVALID_LEAD");
    await w.n.put("/v1/planning/preferences", { leadMinutes: 0 });
    await w.n.post(
      "/v1/visits",
      plan({ start: new Date(Date.now() + 61 * MIN).toISOString() }),
    );
    await sendVisitReminders(db, new Date(Date.now() + 2 * MIN));
    expect(
      (await inbox(w.nord)).filter((n) => n.key === "visit.reminder"),
    ).toHaveLength(0);
  });

  it("tells each responsable the evening before how many visits tomorrow, unless they turned it off", async () => {
    await w.n.post("/v1/visits", plan());
    await w.n.post(
      "/v1/visits",
      plan({
        start: new Date(Date.parse(at10(tomorrow())) + 120 * MIN).toISOString(),
      }),
    );
    await w.s.post("/v1/visits", plan({ targetId: sudPdv.id }));
    await w.s.put("/v1/planning/preferences", { eveningSummary: false });
    await sendEveningPlans(db, tomorrow());
    const nord = (await inbox(w.nord)).find((n) => n.key === "visit.tomorrow");
    expect(nord!.params).toMatchObject({
      count: 2,
      time: "10:00",
      place: "Para Nord",
    });
    expect((await inbox(w.sud)).some((n) => n.key === "visit.tomorrow")).toBe(
      false,
    );
  });

  it("at the day's end, closes only visits whose time is over: a visit planned for later is not missed yet", async () => {
    const late = (
      await w.n.post(
        "/v1/visits",
        plan({
          start: new Date(Date.now() + 30 * MIN).toISOString(),
          allowOverlap: true,
        }),
      )
    ).body;
    const over = (
      await w.n.post(
        "/v1/visits",
        plan({
          start: new Date(Date.now() - 3 * 60 * MIN).toISOString(),
          allowOverlap: true,
        }),
      )
    ).body;
    // The Tunis day of those two can differ near midnight: close both days.
    await closeVisitDay(db, tunisDay(new Date(over.plannedStart)), true);
    await closeVisitDay(db, tunisDay(new Date(late.plannedStart)), true);
    expect((await w.n.get(`/v1/visits/${over.id}`)).body.status).toBe("MISSED");
    expect((await w.n.get(`/v1/visits/${late.id}`)).body.status).toBe(
      "PLANNED",
    );
    // The next day everything of the day before is settled.
    await closeVisitDay(db, tunisDay(new Date(late.plannedStart)), false);
    expect((await w.n.get(`/v1/visits/${late.id}`)).body.status).toBe("MISSED");
  });

  it("closes the day: a planned visit nobody started is missed, one still on site is done", async () => {
    await w.n.put(`/v1/planning/positions/pdv/${pdv.id}`, {
      ...tunis,
      accuracyMeters: 10,
    });
    const missed = (await w.n.post("/v1/visits", plan({ start: nowStart() })))
      .body;
    const open = (
      await w.n.post(
        "/v1/visits",
        plan({ start: nowStart(), allowOverlap: true }),
      )
    ).body;
    await w.n.post(`/v1/visits/${open.id}/check-in`, {
      ...tunis,
      accuracyMeters: 10,
    });
    await closeVisitDay(db, today(), false);
    expect((await w.n.get(`/v1/visits/${missed.id}`)).body).toMatchObject({
      status: "MISSED",
      revision: 1,
    });
    expect((await w.n.get(`/v1/visits/${open.id}`)).body.status).toBe("DONE");
    expect(
      (await inbox(w.nord)).find((n) => n.key === "visit.missed")!.params.place,
    ).toBe("Para Nord");
    // A missed visit cannot be started afterwards.
    expect(
      (await w.n.post(`/v1/visits/${missed.id}/check-in`, {})).body.code,
    ).toBe("INVALID_STATE");
  });
});

describe("what the admin sees", () => {
  it("counts planned, done, missed and what the check-ins said, per responsable", async () => {
    await w.n.put(`/v1/planning/positions/pdv/${pdv.id}`, {
      ...tunis,
      accuracyMeters: 10,
    });
    const a = (await w.n.post("/v1/visits", plan({ start: nowStart() }))).body;
    await w.n.post(`/v1/visits/${a.id}/check-in`, {
      ...tunis,
      accuracyMeters: 10,
    });
    await w.n.post(`/v1/visits/${a.id}/check-out`, {
      ...tunis,
      accuracyMeters: 10,
    });
    const b = (
      await w.n.post(
        "/v1/visits",
        plan({ start: nowStart(), allowOverlap: true }),
      )
    ).body;
    await w.n.post(`/v1/visits/${b.id}/check-in`, {
      ...north(3000),
      accuracyMeters: 10,
      reason: "Parked far",
    });
    await w.n.post(
      "/v1/visits",
      plan({ start: nowStart(), allowOverlap: true }),
    );
    await closeVisitDay(db, today(), false);
    const overview = (
      await w.a.get(`/v1/planning/overview?from=${today()}&to=${today()}`)
    ).body;
    const nord = overview.responsables.find((r: any) => r.name === "Nora Nord");
    expect(nord).toMatchObject({
      planned: 3,
      done: 2,
      missed: 1,
      verified: 1,
      outOfRange: 1,
    });
    expect(overview.responsables.map((r: any) => r.name)).not.toContain(
      "Sami Sud",
    );
    expect(
      (await w.n.get(`/v1/planning/overview?from=${today()}&to=${today()}`))
        .status,
    ).toBe(403);
  });
});

describe("deleting a responsable's account", () => {
  it("ends their calendar link and settings and cancels their planned visits, and keeps the check-ins without a name", async () => {
    const ownerDb = await owner();
    await ownerDb.query(`UPDATE "User" SET "passwordHash" = $2 WHERE id = $1`, [
      w.nord.id,
      await argon2.hash("nora-password-1", { type: argon2.argon2id }),
    ]);
    await ownerDb.end();
    await w.n.put(`/v1/planning/positions/pdv/${pdv.id}`, {
      ...tunis,
      accuracyMeters: 10,
    });
    const planned = (await w.n.post("/v1/visits", plan())).body;
    const started = (
      await w.n.post(
        "/v1/visits",
        plan({ start: nowStart(), allowOverlap: true }),
      )
    ).body;
    await w.n.post(`/v1/visits/${started.id}/check-in`, {
      ...tunis,
      accuracyMeters: 10,
    });
    await w.n.put("/v1/planning/preferences", { leadMinutes: 15 });
    const link = (await w.n.get("/v1/planning/calendar-link")).body;

    expect(
      (await w.n.post("/v1/me/delete", { password: "nora-password-1" })).status,
    ).toBe(201);

    expect(
      (await fetch(`${api.url}${new URL(link.url).pathname}`)).status,
    ).toBe(404);
    const db = await owner();
    try {
      const rows = await db.query(
        `SELECT id, status FROM "Visit" ORDER BY "plannedStart"`,
      );
      expect(rows.rows.find((r) => r.id === planned.id).status).toBe(
        "CANCELLED",
      );
      expect(rows.rows.find((r) => r.id === started.id).status).toBe("ON_SITE");
      expect((await db.query(`SELECT 1 FROM "CalendarFeed"`)).rowCount).toBe(0);
      expect(
        (await db.query(`SELECT 1 FROM "PlanningPreference"`)).rowCount,
      ).toBe(0);
      expect((await db.query(`SELECT 1 FROM "VisitEvent"`)).rowCount).toBe(1);
    } finally {
      await db.end();
    }
  });
});
