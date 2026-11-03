/** The calendar a responsable adds to their calendar app: their visits, read-only (RFC 5545). */
export interface FeedVisit {
  id: string;
  revision: number;
  kind: "COUNT" | "DELIVERY" | "TRAINING" | "FOLLOW_UP" | "OTHER";
  status: "PLANNED" | "ON_SITE" | "DONE" | "MISSED" | "CANCELLED";
  plannedStart: Date;
  plannedEnd: Date;
  updatedAt: Date;
  note: string | null;
  place: string;
  address: string;
  city: string;
  latitude: number | null;
  longitude: number | null;
}

const KIND: Record<FeedVisit["kind"], { fr: string; en: string }> = {
  COUNT: { fr: "Comptage de stock", en: "Stock count" },
  DELIVERY: { fr: "Livraison", en: "Delivery" },
  TRAINING: { fr: "Formation", en: "Training" },
  FOLLOW_UP: { fr: "Suivi", en: "Follow-up" },
  OTHER: { fr: "Visite", en: "Visit" },
};

const escape = (text: string) =>
  text
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");

/** Lines are cut at 75 bytes and continued with a leading space. */
function fold(line: string) {
  const out: string[] = [];
  let current = "";
  let bytes = 0;
  for (const char of line) {
    const size = Buffer.byteLength(char);
    if (bytes + size > (out.length ? 74 : 75)) {
      out.push(current);
      current = "";
      bytes = 0;
    }
    current += char;
    bytes += size;
  }
  out.push(current);
  return out.join("\r\n ");
}

const stamp = (d: Date) =>
  d
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}/, "");

export function buildCalendar(
  visits: FeedVisit[],
  options: { locale: "fr" | "en"; leadMinutes: number; now?: Date },
) {
  const { locale, leadMinutes } = options;
  const now = options.now ?? new Date();
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//BioBalance//Planning//FR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:BioBalance · ${locale === "fr" ? "Planning" : "Schedule"}`,
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
  ];
  for (const v of visits) {
    const summary = `${KIND[v.kind][locale]} · ${v.place}`;
    const where = [v.address, v.city].filter(Boolean).join(", ");
    lines.push(
      "BEGIN:VEVENT",
      `UID:visit-${v.id}@galylio.com`,
      `DTSTAMP:${stamp(now)}`,
      `LAST-MODIFIED:${stamp(v.updatedAt)}`,
      `SEQUENCE:${v.revision}`,
      `DTSTART:${stamp(v.plannedStart)}`,
      `DTEND:${stamp(v.plannedEnd)}`,
      `SUMMARY:${escape(summary)}`,
      `LOCATION:${escape(`${v.place}, ${where}`)}`,
      `STATUS:${v.status === "CANCELLED" ? "CANCELLED" : "CONFIRMED"}`,
      "TRANSP:OPAQUE",
    );
    if (v.note) lines.push(`DESCRIPTION:${escape(v.note)}`);
    if (v.latitude != null && v.longitude != null)
      lines.push(`GEO:${v.latitude};${v.longitude}`);
    if (leadMinutes > 0 && v.status === "PLANNED")
      lines.push(
        "BEGIN:VALARM",
        "ACTION:DISPLAY",
        `DESCRIPTION:${escape(summary)}`,
        `TRIGGER:-PT${leadMinutes}M`,
        "END:VALARM",
      );
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.map(fold).join("\r\n") + "\r\n";
}
