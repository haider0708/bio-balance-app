import { createHash, randomInt } from "node:crypto";
import type { Tx } from "../../core/database";

// 40 random bits, no look-alike characters (I/O/0/1). A code is single-use,
// hashed at rest, short-lived, and only valid together with its email address.
const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export const newCode = () =>
  Array.from({ length: 8 }, () => alphabet[randomInt(alphabet.length)]).join(
    "",
  );

export const normalizeCode = (value: string) =>
  value.replace(/[\s-]/g, "").toUpperCase();

export const displayCode = (code: string) =>
  `${code.slice(0, 4)}-${code.slice(4)}`;

export const hashCode = (code: string) =>
  createHash("sha256").update(normalizeCode(code)).digest("hex");

export const tokenHash = (token: string) =>
  createHash("sha256").update(token).digest("hex");

export type CodePurpose = "invite" | "reset";
const lifetimeMs: Record<CodePurpose, number> = {
  invite: 72 * 3600_000,
  reset: 30 * 60_000,
};

/**
 * Issue a fresh code for a person and queue the email that carries it.
 * Earlier unused codes for the same purpose stop working.
 */
export async function issueCode(tx: Tx, userId: string, purpose: CodePurpose) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`code:${purpose}:${userId}`}, 0))`;
  await tx.accessToken.updateMany({
    where: { userId, purpose, usedAt: null },
    data: { usedAt: new Date() },
  });
  let code = newCode();
  const token = await tx.accessToken.create({
    data: {
      userId,
      purpose,
      tokenHash: hashCode(code),
      expiresAt: new Date(Date.now() + lifetimeMs[purpose]),
    },
  });
  await tx.job.create({
    data: {
      kind: "email",
      key: `${purpose}:${token.id}`,
      payload: { template: purpose, userId, accessTokenId: token.id, code },
    },
  });
  code = "";
  return { id: token.id, expiresAt: token.expiresAt };
}
