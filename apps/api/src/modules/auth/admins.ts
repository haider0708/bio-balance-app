import argon2 from "argon2";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Database } from "../../core/database";
import { encryptSecret } from "./mfa";
import { issueSetupLink, newAuthenticator } from "./setup-link";

export const AdminInput = z.union([
  z.object({
    email: z.email(),
    name: z.string().trim().min(2).max(100),
    password: z.string().min(12).max(128),
  }),
  z.object({ email: z.email(), again: z.literal(true) }),
]);
export type AdminInput = z.infer<typeof AdminInput>;

/**
 * Adds an administrator (active at once, two-step sign-in required) or, with `again`, gives an
 * existing one a new authenticator and ends their sessions. Returns the one-time link that shows
 * the QR code once.
 */
export async function addAdministrator(
  db: Database,
  input: AdminInput,
  publicUrl: string,
) {
  const email = input.email.trim().toLowerCase();
  const authenticator = newAuthenticator(email);
  let userId: string;
  if ("again" in input) {
    const admin = await db.user.findFirst({ where: { email, role: "ADMIN" } });
    if (!admin) throw new Error("No administrator has this email.");
    userId = admin.id;
    await db.$transaction([
      db.user.update({
        where: { id: admin.id },
        data: {
          mfaSecret: encryptSecret(authenticator.hex),
          lastTotpStep: -1n,
        },
      }),
      db.session.updateMany({
        where: { userId: admin.id, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);
  } else {
    if (await db.user.findUnique({ where: { email } }))
      throw new Error("This email already has an account.");
    userId = randomUUID();
    await db.user.create({
      data: {
        id: userId,
        email,
        name: input.name,
        role: "ADMIN",
        status: "ACTIVE",
        passwordHash: await argon2.hash(input.password, {
          type: argon2.argon2id,
        }),
        mfaSecret: encryptSecret(authenticator.hex),
      },
    });
  }
  await db.auditEntry.createMany({
    data: [
      {
        actorId: null,
        action:
          "again" in input ? "admin.authenticator_reissued" : "admin.added",
        entity: "User",
        entityId: userId,
        details: { email },
      },
    ],
  });
  const token = await issueSetupLink(db, userId, authenticator.uri);
  return `${publicUrl.replace(/\/$/, "")}/s#${token}`;
}
