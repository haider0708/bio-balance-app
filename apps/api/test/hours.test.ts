import { describe, expect, it } from "vitest";
import {
  DEFAULT_HOURS,
  type Hours,
  isOpenAt,
  nextOpening,
} from "../src/core/hours";

/** Tunis is UTC+1 all year: 08:00 in Tunis is 07:00 UTC. */
const tunis = (day: string, hhmm: string) =>
  new Date(`${day}T${hhmm}:00+01:00`);
const hours = (days: Hours["days"]): Hours => ({ enabled: true, days });
const weekdays = hours([
  null, // Sunday: closed
  { open: "08:00", close: "21:00" },
  { open: "08:00", close: "21:00" },
  { open: "08:00", close: "21:00" },
  { open: "08:00", close: "21:00" },
  { open: "08:00", close: "21:00" },
  { open: "09:00", close: "13:00" },
]);

describe("opening hours (Tunis time)", () => {
  it("are always open when switched off", () => {
    expect(
      isOpenAt(
        { ...DEFAULT_HOURS, enabled: false },
        tunis("2026-10-18", "03:00"),
      ),
    ).toBe(true);
  });

  it("open at the opening minute, closed at the closing minute", () => {
    // 2026-10-19 is a Monday.
    expect(isOpenAt(weekdays, tunis("2026-10-19", "07:59"))).toBe(false);
    expect(isOpenAt(weekdays, tunis("2026-10-19", "08:00"))).toBe(true);
    expect(isOpenAt(weekdays, tunis("2026-10-19", "20:59"))).toBe(true);
    expect(isOpenAt(weekdays, tunis("2026-10-19", "21:00"))).toBe(false);
  });

  it("follow Tunis, not UTC: 23:30 UTC on Sunday is already Monday 00:30 in Tunis", () => {
    expect(isOpenAt(weekdays, new Date("2026-10-18T23:30:00Z"))).toBe(false);
    // 07:30 UTC Monday = 08:30 Tunis: open. 07:30 UTC Sunday = 08:30 Tunis, Sunday: closed.
    expect(isOpenAt(weekdays, new Date("2026-10-19T07:30:00Z"))).toBe(true);
    expect(isOpenAt(weekdays, new Date("2026-10-18T07:30:00Z"))).toBe(false);
  });

  it("have their own day: Saturday is shorter, Sunday closed", () => {
    expect(isOpenAt(weekdays, tunis("2026-10-17", "12:59"))).toBe(true);
    expect(isOpenAt(weekdays, tunis("2026-10-17", "13:00"))).toBe(false);
    expect(isOpenAt(weekdays, tunis("2026-10-18", "12:00"))).toBe(false);
  });

  it("tell when it opens next", () => {
    // Monday 06:00: opens the same day at 08:00.
    const same = nextOpening(weekdays, tunis("2026-10-19", "06:00"))!;
    expect(same).toMatchObject({ time: "08:00", today: true });
    expect(same.at.toISOString()).toBe("2026-10-19T07:00:00.000Z");
    // Saturday 14:00: Sunday is closed, so Monday 08:00.
    const monday = nextOpening(weekdays, tunis("2026-10-17", "14:00"))!;
    expect(monday).toMatchObject({ time: "08:00", today: false });
    expect(monday.at.toISOString()).toBe("2026-10-19T07:00:00.000Z");
    // Monday 22:00: Tuesday 08:00.
    expect(
      nextOpening(weekdays, tunis("2026-10-19", "22:00"))!.at.toISOString(),
    ).toBe("2026-10-20T07:00:00.000Z");
    // Switched off: nothing to announce.
    expect(nextOpening({ ...weekdays, enabled: false }, new Date())).toBeNull();
  });
});
