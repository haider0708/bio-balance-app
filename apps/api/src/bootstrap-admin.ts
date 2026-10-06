import "reflect-metadata";
import { randomBytes, randomUUID } from "node:crypto";
import { writeFile } from "node:fs/promises";
import argon2 from "argon2";
import { Secret, TOTP } from "otpauth";
import { z } from "zod";
import { Database } from "./core/database";
import { encryptSecret } from "./modules/auth/mfa";

/**
 * Create the first administrator on an empty system.
 *   ADMIN_EMAIL=you@example.com ADMIN_SETUP_FILE=/secure/path.json node dist/bootstrap-admin.js
 * The password and the authenticator (TOTP) link are written to the file once, mode 0600.
 */
async function main() {
  const email = z.email().parse(process.env.ADMIN_EMAIL).trim().toLowerCase();
  const output = z.string().min(1).parse(process.env.ADMIN_SETUP_FILE);
  const db = new Database();
  try {
    if (await db.user.findFirst({ where: { role: "ADMIN" } }))
      throw new Error("An administrator already exists. Use account recovery.");
    const chosen = process.env.ADMIN_PASSWORD?.trim();
    if (chosen && chosen.length < 8)
      throw new Error("ADMIN_PASSWORD needs at least 8 characters.");
    const password = chosen || randomBytes(24).toString("base64url");
    const secret = new Secret({ size: 20 });
    const totpUri = new TOTP({
      issuer: "BioBalance",
      label: email,
      secret,
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    }).toString();
    // Exclusive creation: never overwrite earlier recovery material.
    await writeFile(
      output,
      JSON.stringify(
        {
          email,
          password: chosen ? "(the password you chose)" : password,
          totpUri,
        },
        null,
        2,
      ),
      { mode: 0o600, flag: "wx" },
    );
    const id = randomUUID();
    await db.user.create({
      data: {
        id,
        email,
        name: process.env.ADMIN_NAME ?? "BioBalance",
        role: "ADMIN",
        status: "ACTIVE",
        passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
        mfaSecret: encryptSecret(secret.hex),
      },
    });
    await db.auditEntry.createMany({
      data: [
        {
          actorId: id,
          action: "admin.bootstrap",
          entity: "User",
          entityId: id,
          details: {},
        },
      ],
    });
    console.log(
      "Administrator created. Import the authenticator link and keep the setup file private.",
    );
  } finally {
    await db.$disconnect();
  }
}

void main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
