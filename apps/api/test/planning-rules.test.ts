import { describe, expect, it } from "vitest";
import {
  distanceMeters,
  inTunisia,
  judgePresence,
} from "../src/modules/planning/geo";
import { buildCalendar, type FeedVisit } from "../src/modules/planning/ics";

const tunis = { latitude: 36.8065, longitude: 10.1815 };
/** About `m` metres north of the place. */
const north = (m: number) => ({
  latitude: tunis.latitude + m / 111_195,
  longitude: tunis.longitude,
});

describe("being at a place", () => {
  it("measures a distance on the earth", () => {
    expect(distanceMeters(tunis, tunis)).toBe(0);
    expect(distanceMeters(tunis, north(1000))).toBeGreaterThan(995);
    expect(distanceMeters(tunis, north(1000))).toBeLessThan(1005);
    // Tunis to Sfax is about 235 km as the crow flies.
    const sfax = { latitude: 34.7406, longitude: 10.7603 };
    expect(distanceMeters(tunis, sfax)).toBeGreaterThan(230_000);
    expect(distanceMeters(tunis, sfax)).toBeLessThan(240_000);
  });

  it("verifies a position within 150 metres, widened by the doubt of the reading", () => {
    const judge = (m: number, accuracyM?: number) =>
      judgePresence({ place: tunis, fix: north(m), accuracyM });
    expect(judge(100, 10).verdict).toBe("VERIFIED");
    expect(judge(175, 10).verdict).toBe("OUT_OF_RANGE");
    // Indoors the phone is 80 m unsure: 150 + 80 is the limit.
    expect(judge(220, 80).verdict).toBe("VERIFIED");
    expect(judge(240, 80).verdict).toBe("OUT_OF_RANGE");
    // The doubt only widens the limit by 100 m at most.
    expect(judge(270, 190).verdict).toBe("OUT_OF_RANGE");
    expect(judge(100, 10).distanceM).toBeGreaterThan(95);
  });

  it("says nothing of a reading too doubtful, a missing one, or a place without a position", () => {
    expect(
      judgePresence({ place: tunis, fix: north(10), accuracyM: 500 }),
    ).toEqual({
      verdict: "NO_FIX",
      distanceM: null,
      flags: ["LOW_ACCURACY"],
    });
    expect(judgePresence({ place: tunis, fix: null }).verdict).toBe("NO_FIX");
    expect(
      judgePresence({ place: tunis, fix: { latitude: 36.8 } }).verdict,
    ).toBe("NO_FIX");
    expect(judgePresence({ place: null, fix: north(5) }).verdict).toBe(
      "NO_POSITION",
    );
  });

  it("accepts any position in the test region (a store reviewer is not at a store)", () => {
    expect(
      judgePresence({
        place: tunis,
        fix: { latitude: 48.85, longitude: 2.35 },
        sandbox: true,
      }).verdict,
    ).toBe("SANDBOX");
    expect(
      judgePresence({ place: null, fix: null, sandbox: true }).verdict,
    ).toBe("SANDBOX");
  });

  it("knows Tunisia, so a latitude and longitude typed the wrong way round are caught", () => {
    expect(inTunisia(tunis)).toBe(true);
    expect(inTunisia({ latitude: 10.18, longitude: 36.8 })).toBe(false);
    expect(inTunisia({ latitude: 48.85, longitude: 2.35 })).toBe(false);
  });
});

const visit = (extra: Partial<FeedVisit> = {}): FeedVisit => ({
  id: "11111111-2222-3333-4444-555555555555",
  revision: 3,
  kind: "COUNT",
  status: "PLANNED",
  plannedStart: new Date("2026-11-04T09:00:00Z"),
  plannedEnd: new Date("2026-11-04T10:00:00Z"),
  updatedAt: new Date("2026-11-03T08:00:00Z"),
  note: "Bring the form, then call; thanks",
  place: "Para Joie",
  address: "12 rue de Marseille",
  city: "Tunis",
  latitude: 36.8065,
  longitude: 10.1815,
  ...extra,
});

describe("the calendar feed", () => {
  const options = {
    locale: "fr" as const,
    leadMinutes: 60,
    now: new Date("2026-11-03T12:00:00Z"),
  };

  it("describes a visit in UTC with a stable id, a revision and an alert", () => {
    const text = buildCalendar([visit()], options);
    expect(text.startsWith("BEGIN:VCALENDAR\r\n")).toBe(true);
    expect(text.endsWith("END:VCALENDAR\r\n")).toBe(true);
    expect(text).toContain(
      "UID:visit-11111111-2222-3333-4444-555555555555@galylio.com",
    );
    expect(text).toContain("DTSTART:20261104T090000Z");
    expect(text).toContain("DTEND:20261104T100000Z");
    expect(text).toContain("SEQUENCE:3");
    expect(text).toContain("SUMMARY:Comptage de stock · Para Joie");
    expect(text).toContain("GEO:36.8065;10.1815");
    expect(text).toContain("TRIGGER:-PT60M");
    expect(text).toContain("STATUS:CONFIRMED");
  });

  it("escapes what must be escaped and cuts long lines at 75 bytes", () => {
    const text = buildCalendar(
      [visit({ note: "x".repeat(200) + ", end; \\ ok", place: "Para é" })],
      options,
    );
    for (const line of text.split("\r\n"))
      expect(Buffer.byteLength(line)).toBeLessThanOrEqual(75);
    const unfolded = text.replace(/\r\n /g, "");
    expect(unfolded).toContain("end\; \\\\ ok");
    expect(unfolded).toContain("Para é");
  });

  it("keeps a cancelled visit as cancelled, and gives no alert to a visit that is not coming", () => {
    const cancelled = buildCalendar([visit({ status: "CANCELLED" })], options);
    expect(cancelled).toContain("STATUS:CANCELLED");
    expect(cancelled).not.toContain("VALARM");
    expect(buildCalendar([visit({ status: "DONE" })], options)).not.toContain(
      "VALARM",
    );
    expect(
      buildCalendar([visit()], { ...options, leadMinutes: 0 }),
    ).not.toContain("VALARM");
  });

  it("is in the person's language", () => {
    expect(buildCalendar([visit()], { ...options, locale: "en" })).toContain(
      "SUMMARY:Stock count · Para Joie",
    );
  });
});
