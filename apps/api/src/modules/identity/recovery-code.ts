import { randomInt } from "node:crypto";

// 40 random bits; no visually ambiguous I/O/0/1. Codes remain single-use,
// hashed at rest, short-lived, and protected by the recovery attempt limits.
const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const recoveryCode = () =>
  Array.from({ length: 8 }, () => alphabet[randomInt(alphabet.length)]).join(
    "",
  );

export function normalizeRecoveryCode(value: string) {
  const token = value.trim();
  // Previously issued long tokens stay case-sensitive during the rollout.
  return /^[a-z0-9]{4}[- ]?[a-z0-9]{4}$/i.test(token)
    ? token.replace(/[- ]/g, "").toUpperCase()
    : token;
}

export const displayRecoveryCode = (token: string) =>
  /^[A-Z0-9]{8}$/.test(token)
    ? `${token.slice(0, 4)}-${token.slice(4)}`
    : token;
