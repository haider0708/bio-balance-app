import { randomInt } from "node:crypto";

// No look-alike characters (0/O, 1/l/I): the person reads this in a message and types it on a phone.
const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnopqrstuvwxyz";
const DIGIT = "23456789";
const ALL = UPPER + LOWER + DIGIT;
const LENGTH = 10;

/** How long a generated password works. */
export const TEMP_PASSWORD_DAYS = 7;

/**
 * A random temporary password: ten characters (about 57 bits), always with an upper-case letter, a
 * lower-case letter and a digit. It is shown to nobody but the person it is sent to.
 */
export function generateTempPassword(): string {
  for (;;) {
    const chars = Array.from(
      { length: LENGTH },
      () => ALL[randomInt(ALL.length)]!,
    );
    const text = chars.join("");
    if (
      [...text].some((c) => UPPER.includes(c)) &&
      [...text].some((c) => LOWER.includes(c)) &&
      [...text].some((c) => DIGIT.includes(c))
    )
      return text;
  }
}
