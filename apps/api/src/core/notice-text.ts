import wording from "./notice-text.json";

type Locale = "fr" | "en";
const texts: Record<string, Record<Locale, string>> = wording;

/** An amount in millimes as the phone shows it: "2,100 TND" / "2,100 TND" (three decimals). */
export function formatMillimes(millimes: number, locale: Locale) {
  const text = new Intl.NumberFormat(locale === "fr" ? "fr-FR" : "en-US", {
    minimumFractionDigits: 3,
    maximumFractionDigits: 3,
  }).format(Math.abs(millimes) / 1000);
  return `${millimes < 0 ? "−" : ""}${text} TND`;
}

/** A count with the word that goes with it: French says "0 unité", "1 unité", English "1 unit". */
function counted(locale: Locale, value: unknown, one: string, many: string) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "";
  const singular = locale === "fr" ? Math.abs(n) < 2 : n === 1;
  const shown = new Intl.NumberFormat(
    locale === "fr" ? "fr-FR" : "en-US",
  ).format(n);
  return `${shown} ${singular ? one : many}`;
}

/**
 * A system notification in words, the same as the app shows it (the app keeps the same table,
 * checked by its tests): `{placeholders}` filled from the params (`{units:unit|units}` gives the
 * count and the right word, `{day}` a date as 13/10/2026), a note added at the end.
 */
export function noticeText(
  locale: Locale,
  key: string,
  params: Record<string, unknown>,
): string | null {
  const text = texts[key];
  if (!text) return null;
  let line = text[locale].replace(
    /\{(\w+):([^|}]*)\|([^}]*)\}/g,
    (_, name: string, one: string, many: string) =>
      counted(locale, params[name], one, many),
  );
  for (const [name, value] of Object.entries(params)) {
    const shown =
      name === "amountMillimes" && typeof value === "number"
        ? formatMillimes(value, locale)
        : name === "day" && typeof value === "string"
          ? value.split("-").reverse().join("/")
          : String(value ?? "");
    line = line.replaceAll(
      `{${name === "amountMillimes" ? "amount" : name}}`,
      shown,
    );
  }
  line = line
    .replace(/\{\w+\}/g, "")
    .replace(/\s+/g, " ")
    .trim();
  // A note the wording does not already show is added at the end.
  const note = params.note;
  if (
    typeof note === "string" &&
    note.trim() &&
    !text[locale].includes("{note}")
  )
    line = `${line} — ${note.trim()}`;
  return line;
}
