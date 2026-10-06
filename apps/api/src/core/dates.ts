const TUNIS = "Africa/Tunis";
const dayFormat = new Intl.DateTimeFormat("en-CA", {
  timeZone: TUNIS,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** The Tunis calendar day (YYYY-MM-DD) of an instant. */
export function tunisDay(at: Date): string {
  return dayFormat.format(at);
}

/** A Date at UTC midnight for a YYYY-MM-DD string: what PostgreSQL DATE columns hold. */
export function dayToDate(day: string): Date {
  return new Date(`${day}T00:00:00.000Z`);
}

export function dateToDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(day: string, days: number): string {
  const d = dayToDate(day);
  d.setUTCDate(d.getUTCDate() + days);
  return dateToDay(d);
}
