import type { Tx } from "../../core/database";
import { audit } from "../../core/audit";
import type { Actor } from "../../core/actor";
import {
  generateTempPassword,
  TEMP_PASSWORD_DAYS,
} from "../../core/temp-password";
import { PasswordHasher } from "./password-hasher";
import { decryptSecret, encryptSecret } from "./mfa";
import type { Database } from "../../core/database";
import type { User } from "@prisma/client";

const hasher = new PasswordHasher(8);

/**
 * Gives a team member a fresh temporary password and queues the email and the WhatsApp message that
 * carry it. The password is stored only as a hash; the messages hold it encrypted until they are sent,
 * and it is wiped from them then. Any earlier password, sign-in session or activation code stops working.
 */
export async function issueCredentials(
  tx: Tx,
  actor: Actor | null,
  userId: string,
) {
  const password = generateTempPassword();
  const passwordHash = await hasher.hash(password);
  const expiresAt = new Date(Date.now() + TEMP_PASSWORD_DAYS * 86_400_000);
  const user = await tx.user.update({
    where: { id: userId },
    data: {
      passwordHash,
      mustChangePassword: true,
      passwordExpiresAt: expiresAt,
    },
  });
  await tx.session.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  await tx.accessToken.updateMany({
    where: { userId, purpose: "invite", usedAt: null },
    data: { usedAt: new Date() },
  });
  const issuedAt = new Date().toISOString();
  const payload = {
    template: "credentials",
    userId,
    sealed: encryptSecret(password),
    issuedAt,
  };
  const key = `${userId}:${issuedAt}`;
  await tx.job.create({
    data: { kind: "email", key: `credentials:${key}`, payload },
  });
  await tx.job.create({
    data: { kind: "whatsapp", key: `wa:credentials:${key}`, payload },
  });
  await audit(
    tx,
    actor,
    "user.credentials_issued",
    "User",
    userId,
    { expiresAt: expiresAt.toISOString() },
    user.regionId,
  );
  return { expiresAt };
}

/** The person chose their own password (or reset it): nothing temporary is left. */
export const clearTemporary = {
  mustChangePassword: false,
  passwordExpiresAt: null,
} as const;

const checker = new PasswordHasher(8);

/**
 * The password a queued message carries, if it is still the one that works: the person is still on
 * their temporary password, it has not expired, and a newer one has not replaced it. Anything else is
 * not sent (a retry must never mail a dead or replaced password).
 */
export async function openCredentials(
  user: Pick<User, "passwordHash" | "mustChangePassword" | "passwordExpiresAt">,
  sealed: string,
): Promise<string | null> {
  if (
    !sealed ||
    !user.mustChangePassword ||
    !user.passwordHash ||
    !user.passwordExpiresAt ||
    user.passwordExpiresAt <= new Date()
  )
    return null;
  let password: string;
  try {
    password = decryptSecret(sealed);
  } catch {
    return null;
  }
  return (await checker.verify(user.passwordHash, password)) ? password : null;
}

/** Once a message is sent (or will never be), the password is wiped from it. */
export async function wipeCredentials(db: Database, jobId: string) {
  await db.$executeRaw`UPDATE "Job" SET payload = jsonb_set(payload, '{sealed}', '""') WHERE id = ${jobId}::uuid`;
}
