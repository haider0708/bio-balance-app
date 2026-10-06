import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
import { Secret, TOTP } from "otpauth";
import { requireRule } from "../../core/errors";

function key() {
  const k = Buffer.from(process.env.MFA_ENCRYPTION_KEY ?? "", "base64");
  requireRule(k.length === 32, "MFA_CONFIGURATION", "MFA is not configured.", 503);
  return k;
}

/** The authenticator secret is stored encrypted (AES-256-GCM). */
export function encryptSecret(secret: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key(), iv);
  return Buffer.concat([
    iv,
    cipher.update(secret, "utf8"),
    cipher.final(),
    cipher.getAuthTag(),
  ]).toString("base64");
}

export function decryptSecret(stored: string): string {
  const raw = Buffer.from(stored, "base64");
  const cipher = createDecipheriv("aes-256-gcm", key(), raw.subarray(0, 12));
  cipher.setAuthTag(raw.subarray(-16));
  return Buffer.concat([
    cipher.update(raw.subarray(12, -16)),
    cipher.final(),
  ]).toString("utf8");
}

/** RFC 6238: SHA-1, six digits, thirty seconds. */
export function totp(secretHex: string, step: bigint): string {
  return new TOTP({
    secret: Secret.fromHex(secretHex),
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  }).generate({ timestamp: Number(step) * 30000 });
}

/** The step the code matches (allowing one step of clock drift), if any, and newer than `last`. */
export function matchTotp(secretHex: string, otp: string, last: bigint) {
  const now = BigInt(Math.floor(Date.now() / 30_000));
  return [now - 1n, now, now + 1n].find(
    (s) =>
      s > last &&
      timingSafeEqual(Buffer.from(totp(secretHex, s)), Buffer.from(otp)),
  );
}
