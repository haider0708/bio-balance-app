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

/**
 * A system notification in words, the same as the app shows it (the app keeps the same table,
 * checked by its tests): `{placeholders}` filled from the params, a note added at the end.
 */
export function noticeText(
  locale: Locale,
  key: string,
  params: Record<string, unknown>,
): string | null {
  const text = texts[key];
  if (!text) return null;
  let line = text[locale];
  for (const [name, value] of Object.entries(params)) {
    const shown =
      name === "amountMillimes" && typeof value === "number"
        ? formatMillimes(value, locale)
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
