import { requireRule } from "./errors";
export class Money {
  private constructor(
    readonly millimes: bigint,
    readonly currency = "TND",
  ) {
    Object.freeze(this);
  }
  static from(value: string | bigint): Money {
    requireRule(
      typeof value === "bigint" || /^(0|[1-9]\d{0,14})$/.test(value),
      "INVALID_MONEY",
      "Montant invalide.",
    );
    const amount = BigInt(value);
    requireRule(
      amount >= 0n && amount <= 999_999_999_999_999n,
      "INVALID_MONEY",
      "Montant hors limites.",
    );
    return new Money(amount);
  }
  multiply(quantity: number): Money {
    unitQuantity(quantity);
    return Money.from(this.millimes * BigInt(quantity));
  }
  add(other: Money): Money {
    return Money.from(this.millimes + other.millimes);
  }
  toJSON() {
    return { currency: this.currency, millimes: this.millimes.toString() };
  }
}
export function unitQuantity(value: number, allowZero = false): number {
  requireRule(
    Number.isSafeInteger(value) &&
      value >= (allowZero ? 0 : 1) &&
      value <= 1_000_000,
    "INVALID_QUANTITY",
    "Saisissez un nombre entier d’unités valide.",
  );
  return value;
}
export function expiryDate(input: string): string {
  requireRule(
    /^\d{4}-\d{2}(-\d{2})?$/.test(input),
    "INVALID_EXPIRY",
    "Date de péremption invalide.",
  );
  const [year, month, day] = input.split("-").map(Number);
  requireRule(
    year! >= 2000 && year! <= 2200 && month! >= 1 && month! <= 12,
    "INVALID_EXPIRY",
    "Date de péremption invalide.",
  );
  const date =
    day === undefined
      ? new Date(Date.UTC(year!, month!, 0))
      : new Date(Date.UTC(year!, month! - 1, day));
  requireRule(
    date.getUTCFullYear() === year && date.getUTCMonth() + 1 === month,
    "INVALID_EXPIRY",
    "Date de péremption invalide.",
  );
  return date.toISOString().slice(0, 10);
}
export function localDate(date: Date, timezone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
