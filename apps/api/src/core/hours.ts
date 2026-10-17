/** Opening hours, always in Tunis time (UTC+1, no daylight saving): the phone's clock never matters. */
export interface Hours {
  enabled: boolean;
  /** Index 0 is Sunday. `null`: closed all day. Times are "HH:MM", close after open, same day. */
  days: ({ open: string; close: string } | null)[];
}

export const DEFAULT_HOURS: Hours = {
  enabled: false,
  days: Array.from({ length: 7 }, () => ({ open: "08:00", close: "21:00" })),
};

const TUNIS_OFFSET_MS = 3_600_000;
const minutes = (hhmm: string) =>
  Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));

/** Tunis weekday (0 = Sunday) and minutes since midnight of an instant. */
function tunis(at: Date) {
  const local = new Date(at.getTime() + TUNIS_OFFSET_MS);
  return {
    day: local.getUTCDay(),
    minute: local.getUTCHours() * 60 + local.getUTCMinutes(),
  };
}

/** Whether BioBalance is open at an instant (always, when the hours are switched off). */
export function isOpenAt(hours: Hours, at: Date): boolean {
  if (!hours.enabled) return true;
  const { day, minute } = tunis(at);
  const today = hours.days[day];
  return (
    !!today && minute >= minutes(today.open) && minute < minutes(today.close)
  );
}

/** The next opening after `from` as a local day offset and time, for "back at 08:00". */
export function nextOpening(
  hours: Hours,
  from: Date,
): { at: Date; time: string; today: boolean } | null {
  if (!hours.enabled) return null;
  const { day, minute } = tunis(from);
  for (let ahead = 0; ahead < 8; ahead++) {
    const window = hours.days[(day + ahead) % 7];
    if (!window) continue;
    if (ahead === 0 && minute >= minutes(window.open)) continue;
    const local = new Date(from.getTime() + TUNIS_OFFSET_MS);
    local.setUTCHours(0, 0, 0, 0);
    local.setUTCDate(local.getUTCDate() + ahead);
    const at = new Date(
      local.getTime() + minutes(window.open) * 60_000 - TUNIS_OFFSET_MS,
    );
    return { at, time: window.open, today: ahead === 0 };
  }
  return null;
}
