/** Amounts are whole millimes (1 TND = 1000 millimes) so sums are always exact. */
export const MAX_MILLIMES = 1_000_000_000n; // 1 000 000 TND

export function toMillimes(value: bigint | number): bigint {
  return typeof value === "bigint" ? value : BigInt(Math.trunc(value));
}

/** "12.500" — used by emails and exports; the phone formats its own. */
export function formatTnd(millimes: bigint | number): string {
  const v = BigInt(millimes);
  const sign = v < 0n ? "-" : "";
  const abs = v < 0n ? -v : v;
  return `${sign}${abs / 1000n}.${String(abs % 1000n).padStart(3, "0")}`;
}
