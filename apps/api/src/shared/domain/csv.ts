/** Quote cells without discarding text, and neutralize spreadsheet formulas. */
export function csvCell(value: unknown): string {
  const text = String(value ?? "");
  const safe =
    /^[\s\u0000-\u001f]*[=+@-]/u.test(text) || /^[\t\r\n]/u.test(text)
      ? `'${text}`
      : text;
  return `"${safe.replace(/"/g, '""')}"`;
}
