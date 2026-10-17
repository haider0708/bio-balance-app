import { createHash, randomBytes } from "node:crypto";
import qrcode from "qrcode-generator";
import { Secret, TOTP } from "otpauth";
import type { Database } from "../../core/database";
import { DomainError } from "../../core/errors";
import { decryptSecret, encryptSecret } from "./mfa";

const hash = (token: string) =>
  createHash("sha256").update(token).digest("hex");

/** A new authenticator secret for an account: what the database keeps, and the link an app scans. */
export function newAuthenticator(email: string) {
  const secret = new Secret({ size: 20 });
  const uri = new TOTP({
    issuer: "BioBalance",
    label: email,
    secret,
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  }).toString();
  return { hex: secret.hex, base32: secret.base32, uri };
}

/**
 * A one-time link for a new administrator: it shows the authenticator QR code once, then forgets
 * it. Returns the token (the link is `/s#<token>`: the part after # is never sent to a server).
 */
export async function issueSetupLink(
  db: Database,
  userId: string,
  uri: string,
  minutes = 24 * 60,
) {
  const token = randomBytes(32).toString("base64url");
  await db.run("SYSTEM", async (tx) => {
    // Earlier links for this person stop working.
    await tx.setupLink.updateMany({
      where: { userId, usedAt: null },
      data: { secret: null, usedAt: new Date() },
    });
    await tx.setupLink.create({
      data: {
        tokenHash: hash(token),
        userId,
        secret: encryptSecret(uri),
        expiresAt: new Date(Date.now() + minutes * 60_000),
      },
    });
  });
  return token;
}

/** Shows the QR code of a link, once: the secret is erased in the same statement that reads it. */
export async function claimSetupLink(db: Database, token: string) {
  if (token.length < 32 || token.length > 100) throw invalid();
  // One statement locks the row, checks it is unused and unexpired, and erases the secret; a second
  // simultaneous reader waits, then finds nothing.
  const rows = await db.run(
    "SYSTEM",
    (tx) =>
      tx.$queryRaw<{ secret: string }[]>`
      WITH claimed AS (
        SELECT id, secret FROM "SetupLink"
        WHERE "tokenHash" = ${hash(token)} AND secret IS NOT NULL AND "usedAt" IS NULL
          AND "expiresAt" > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
        FOR UPDATE)
      UPDATE "SetupLink" l SET secret = NULL, "usedAt" = (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
      FROM claimed WHERE l.id = claimed.id
      RETURNING claimed.secret`,
  );
  const stored = rows[0]?.secret;
  if (!stored) throw invalid();
  const uri = decryptSecret(stored);
  const qr = qrcode(0, "M");
  qr.addData(uri);
  qr.make();
  const key = new URL(uri).searchParams.get("secret") ?? "";
  return {
    svg: qr.createSvgTag({ cellSize: 6, margin: 3, scalable: true }),
    key,
  };
}

const invalid = () =>
  new DomainError(
    "LINK_USED",
    "This link was already used or has expired.",
    410,
  );
