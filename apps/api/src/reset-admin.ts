import "reflect-metadata";
import { randomBytes } from "node:crypto";
import { writeFile } from "node:fs/promises";
import argon2 from "argon2";
import { Secret, TOTP } from "otpauth";
import { z } from "zod";
import { Database } from "./core/database";
import { encryptSecret } from "./modules/auth/mfa";

/**
 * An administrator lost their phone or password. Issues a new password and a new authenticator secret,
 * ends every session, and writes them to a file (mode 0600, never overwritten):
 *   ADMIN_EMAIL=you@example.com ADMIN_SETUP_FILE=/secure/path.json node dist/reset-admin.js
 * No business data is touched.
 */
async function main() {
  const email = z.email().parse(process.env.ADMIN_EMAIL).trim().toLowerCase();
  const output = z.string().min(1).parse(process.env.ADMIN_SETUP_FILE);
  const db = new Database();
  try {
    const admin = await db.user.findFirst({ where: { email, role: "ADMIN" } });
    if (!admin) throw new Error("No administrator has this email.");
    const password = randomBytes(24).toString("base64url");
    const secret = new Secret({ size: 20 });
    const totpUri = new TOTP({
      issuer: "BioBalance",
      label: email,
      secret,
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    }).toString();
    await writeFile(
      output,
      JSON.stringify({ email, password, totpUri }, null, 2),
      { mode: 0o600, flag: "wx" },
    );
    await db.$transaction([
      db.user.update({
        where: { id: admin.id },
        data: {
          passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
          mfaSecret: encryptSecret(secret.hex),
          lastTotpStep: -1n,
          status: "ACTIVE",
        },
      }),
      db.session.updateMany({
        where: { userId: admin.id, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
      db.auditEntry.createMany({
        data: [
          {
            actorId: admin.id,
            action: "admin.credentials_reset",
            entity: "User",
            entityId: admin.id,
            details: {},
          },
        ],
      }),
    ]);
    console.log(
      "New credentials written. Import the authenticator link and keep the file private.",
    );
  } finally {
    await db.$disconnect();
  }
}

void main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
