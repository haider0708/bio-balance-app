import { Injectable } from "@nestjs/common";
import { randomBytes } from "node:crypto";
import type { Actor } from "../../core/actor";
import { Database, type Tx } from "../../core/database";
import { DomainError, requireRule } from "../../core/errors";
import { audit } from "../../core/audit";
import { notifyAdmins } from "../../core/notifier";
import { deletedEmail } from "./deleted";
import { hashCode, issueCode, normalizeCode, tokenHash } from "./codes";
import { decryptSecret, matchTotp } from "./mfa";
import { PasswordHasher } from "./password-hasher";
import { pushConfigured } from "../../push/apns";

const SESSION_HOURS = { ADMIN: 12, default: 24 * 30 };

export interface Me {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: Actor["role"];
  locale: "fr" | "en";
  region: { id: string; code: string; name: string } | null;
  pdv: { id: string; name: string } | null;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: Database,
    private readonly passwords: PasswordHasher = new PasswordHasher(),
  ) {}

  /** Fixed-window attempt counter shared by all API instances. */
  async throttle(key: string, limit = 10) {
    const now = new Date();
    const start = new Date(now.getTime() - 900_000);
    const [row] = await this.db.$queryRaw<{ count: number }[]>`
      INSERT INTO "LoginAttempt" (key, count, "windowStart") VALUES (${key}, 1, ${now})
      ON CONFLICT (key) DO UPDATE SET
        count = CASE WHEN "LoginAttempt"."windowStart" <= ${start} THEN 1 ELSE LEAST("LoginAttempt".count + 1, 1000000) END,
        "windowStart" = CASE WHEN "LoginAttempt"."windowStart" <= ${start} THEN ${now} ELSE "LoginAttempt"."windowStart" END
      RETURNING count`;
    requireRule(
      row!.count <= limit,
      "TOO_MANY_ATTEMPTS",
      "Too many attempts. Try again in 15 minutes.",
      429,
    );
  }

  async login(
    email: string,
    password: string,
    otp: string | undefined,
    ip: string,
  ) {
    await this.throttle(`ip:${tokenHash(ip)}`, 60);
    await this.throttle(`email:${tokenHash(email)}`);
    const user = await this.db.user.findUnique({ where: { email } });
    // Always hash, so unknown accounts cost the same time as wrong passwords.
    const valid = user?.passwordHash
      ? await this.passwords.verify(user.passwordHash, password)
      : await this.passwords.hash(password).then(() => false);
    requireRule(
      user && valid && user.status === "ACTIVE",
      "INVALID_CREDENTIALS",
      "Incorrect email or password.",
      401,
    );
    const token = randomBytes(32).toString("base64url");
    const hours =
      user.role === "ADMIN" ? SESSION_HOURS.ADMIN : SESSION_HOURS.default;
    const expiresAt = new Date(Date.now() + hours * 3600_000);
    await this.db.run("SYSTEM", async (tx) => {
      // Serialize with password changes; the credential is re-checked under lock.
      await tx.$queryRaw`SELECT id FROM "User" WHERE id=${user.id}::uuid FOR UPDATE`;
      const current = await tx.user.findUniqueOrThrow({
        where: { id: user.id },
      });
      requireRule(
        current.status === "ACTIVE" &&
          current.passwordHash === user.passwordHash,
        "INVALID_CREDENTIALS",
        "Incorrect email or password.",
        401,
      );
      if (user.role === "ADMIN") {
        requireRule(
          user.mfaSecret,
          "MFA_REQUIRED",
          "Two-step verification is required.",
          401,
        );
        requireRule(
          otp && /^\d{6}$/.test(otp),
          "MFA_REQUIRED",
          "Enter the code from your authenticator app.",
          401,
        );
        const step = matchTotp(
          decryptSecret(user.mfaSecret),
          otp,
          user.lastTotpStep,
        );
        requireRule(
          step !== undefined,
          "INVALID_MFA",
          "Invalid or already used code.",
          401,
        );
        const claimed = await tx.user.updateMany({
          where: { id: user.id, lastTotpStep: { lt: step } },
          data: { lastTotpStep: step },
        });
        requireRule(
          claimed.count === 1,
          "INVALID_MFA",
          "Code already used.",
          401,
        );
      }
      await tx.session.create({
        data: { userId: user.id, tokenHash: tokenHash(token), expiresAt },
      });
    });
    return {
      token,
      expiresAt: expiresAt.toISOString(),
      me: await this.me(user.id),
    };
  }

  /**
   * Registers the phone behind this session for Apple push alerts. A token moves to whoever
   * signs in on that phone last; a person keeps at most ten phones.
   */
  async registerPushDevice(
    actor: Actor,
    device: { token: string; platform: "IOS"; sandbox: boolean },
  ) {
    requireRule(
      actor.sessionId,
      "SESSION_EXPIRED",
      "Please sign in again.",
      401,
    );
    await this.db.run("SYSTEM", async (tx) => {
      await tx.$executeRaw`INSERT INTO "PushDevice" (token, "userId", "sessionId", platform, sandbox)
        VALUES (${device.token}, ${actor.id}::uuid, ${actor.sessionId}::uuid, ${device.platform}, ${device.sandbox})
        ON CONFLICT (token) DO UPDATE SET "userId" = EXCLUDED."userId", "sessionId" = EXCLUDED."sessionId",
          sandbox = EXCLUDED.sandbox, "updatedAt" = CURRENT_TIMESTAMP`;
      await tx.$executeRaw`DELETE FROM "PushDevice" WHERE "userId" = ${actor.id}::uuid AND token NOT IN (
        SELECT token FROM "PushDevice" WHERE "userId" = ${actor.id}::uuid ORDER BY "updatedAt" DESC LIMIT 10)`;
    });
    return { push: pushConfigured() };
  }

  /** Resolve a bearer token to the person making the request. */
  async authenticate(token: string): Promise<Actor> {
    requireRule(
      token.length >= 32 && token.length <= 256,
      "SESSION_EXPIRED",
      "Please sign in again.",
      401,
    );
    // Who is calling is decided before any security context exists, so this lookup is trusted server code.
    const [row] = await this.db.run(
      "SYSTEM",
      (tx) => tx.$queryRaw<
        {
          id: string;
          name: string;
          email: string;
          role: Actor["role"];
          locale: string;
          regionId: string | null;
          pdvId: string | null;
          status: string;
          sessionId: string;
        }[]
      >`SELECT u.id,u.name,u.email,u.role,u.locale,u."regionId",u."pdvId",u.status,s.id AS "sessionId"
      FROM "Session" s JOIN "User" u ON u.id=s."userId"
      WHERE s."tokenHash"=${tokenHash(token)} AND s."revokedAt" IS NULL
        AND s."expiresAt">(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`,
    );
    requireRule(row, "SESSION_EXPIRED", "Please sign in again.", 401);
    requireRule(
      row.status === "ACTIVE",
      "ACCESS_DISABLED",
      "Your account is not active.",
      403,
    );
    return {
      id: row.id,
      name: row.name,
      email: row.email,
      role: row.role,
      regionId: row.regionId,
      pdvId: row.pdvId,
      locale: row.locale === "en" ? "en" : "fr",
      sessionId: row.sessionId,
    };
  }

  async me(userId: string): Promise<Me> {
    return this.db.run("SYSTEM", async (tx) => {
      const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
      const [region, pdv] = await Promise.all([
        user.regionId
          ? tx.region.findUnique({ where: { id: user.regionId } })
          : null,
        user.pdvId
          ? tx.pdv.findUnique({
              where: { id: user.pdvId },
              select: { id: true, name: true },
            })
          : null,
      ]);
      return {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        locale: user.locale === "en" ? "en" : "fr",
        region: region && {
          id: region.id,
          code: region.code,
          name: region.name,
        },
        pdv: pdv && { id: pdv.id, name: pdv.name },
      };
    });
  }

  async updateProfile(
    actor: Actor,
    input: { name?: string; phone?: string | null; locale?: "fr" | "en" },
  ) {
    await this.db.user.update({
      where: { id: actor.id },
      data: {
        ...(input.name !== undefined && { name: input.name }),
        ...(input.phone !== undefined && { phone: input.phone }),
        ...(input.locale !== undefined && { locale: input.locale }),
      },
    });
    return this.me(actor.id);
  }

  async logout(token: string) {
    await this.db.session.updateMany({
      where: { tokenHash: tokenHash(token), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  }

  async changePassword(actor: Actor, current: string, next: string) {
    await this.throttle(`password:${actor.id}`, 8);
    const user = await this.db.user.findUniqueOrThrow({
      where: { id: actor.id },
    });
    requireRule(
      user.passwordHash &&
        (await this.passwords.verify(user.passwordHash, current)),
      "INVALID_CREDENTIALS",
      "Your current password is incorrect.",
      401,
    );
    const passwordHash = await this.passwords.hash(next);
    await this.db.run("SYSTEM", async (tx) => {
      await tx.user.update({ where: { id: actor.id }, data: { passwordHash } });
      await tx.session.updateMany({
        where: {
          userId: actor.id,
          revokedAt: null,
          id: { not: actor.sessionId },
        },
        data: { revokedAt: new Date() },
      });
      await this.queuePasswordChanged(tx, actor.id);
      await audit(tx, actor, "auth.password_changed", "User", actor.id);
    });
    return { ok: true };
  }

  /**
   * A person deletes their own account. What identifies them is erased at once — name, email,
   * phone, password, two-step secret, sessions, codes, notifications and training progress (the
   * sign-in attempt counters hold only a hash of the email and expire on their own) — and
   * the account can never sign in again. The business records they took part in (sales, stock
   * counts, deliveries, rewards paid) are kept for the accounts, under "Compte supprimé".
   * Payout requests still waiting are cancelled. The last admin cannot leave the network
   * without an admin.
   */
  async deleteAccount(actor: Actor, password: string) {
    await this.throttle(`delete:${actor.id}`, 5);
    const user = await this.db.user.findUniqueOrThrow({
      where: { id: actor.id },
    });
    requireRule(
      user.passwordHash &&
        (await this.passwords.verify(user.passwordHash, password)),
      "INVALID_CREDENTIALS",
      "Your password is incorrect.",
      401,
    );
    await this.db.run("SYSTEM", async (tx) => {
      // The same lock as payouts and sale corrections: nothing changes the wallet meanwhile.
      await this.db.lock(tx, "User", user.id);
      if (user.role === "ADMIN") {
        const others = await tx.user.count({
          where: { role: "ADMIN", status: "ACTIVE", id: { not: user.id } },
        });
        requireRule(
          others > 0,
          "LAST_ADMIN",
          "Another admin must exist before this account can be deleted.",
          409,
        );
      }
      const tag = user.id.slice(0, 4).toUpperCase();
      await tx.payoutRequest.updateMany({
        where: { userId: user.id, status: "PENDING" },
        data: {
          status: "CANCELLED",
          decidedAt: new Date(),
          decisionNote: "Account deleted",
        },
      });
      await tx.session.deleteMany({ where: { userId: user.id } });
      await tx.accessToken.deleteMany({ where: { userId: user.id } });
      await tx.notification.deleteMany({ where: { userId: user.id } });
      await tx.lessonProgress.deleteMany({ where: { userId: user.id } });
      await tx.user.update({
        where: { id: user.id },
        data: {
          name: `Compte supprimé #${tag}`,
          email: deletedEmail(user.id),
          phone: null,
          passwordHash: null,
          mfaSecret: null,
          status: "SUSPENDED",
          decisionNote: "Deleted by its owner",
        },
      });
      await audit(tx, actor, "auth.account_deleted", "User", user.id, {
        role: user.role,
      });
      await notifyAdmins(tx, {
        key: "account.deleted",
        params: { name: user.name, role: user.role },
        entityType: "User",
        entityId: user.id,
      });
    });
    return { ok: true };
  }

  /** The invited person sets their password with the code from their email. */
  async activate(
    email: string,
    code: string,
    name: string | undefined,
    password: string,
    ip: string,
  ) {
    await this.throttle(`account-ip:${tokenHash(ip)}`, 40);
    await this.throttle(`account:${tokenHash(email)}`);
    const passwordHash = await this.passwords.hash(password);
    await this.db.run("SYSTEM", async (tx) => {
      const user = await this.useCode(tx, email, code, "invite");
      requireRule(
        user.status === "ACTIVE",
        "NOT_APPROVED",
        "This account is not approved yet.",
        409,
      );
      await tx.user.update({
        where: { id: user.id },
        data: { passwordHash, ...(name ? { name } : {}) },
      });
      await audit(tx, null, "auth.activated", "User", user.id);
    });
    return { ok: true };
  }

  async forgot(email: string, ip: string) {
    await this.throttle(`reset-ip:${tokenHash(ip)}`, 20);
    await this.throttle(`reset:${tokenHash(email)}`, 3);
    await this.db.run("SYSTEM", async (tx) => {
      const user = await tx.user.findUnique({ where: { email } });
      if (user && user.status === "ACTIVE" && user.passwordHash)
        await issueCode(tx, user.id, "reset");
    });
    // Same answer whether or not the account exists.
    return { ok: true };
  }

  async reset(email: string, code: string, password: string, ip: string) {
    await this.throttle(`account-ip:${tokenHash(ip)}`, 40);
    await this.throttle(`reset-code:${tokenHash(email)}`);
    const passwordHash = await this.passwords.hash(password);
    await this.db.run("SYSTEM", async (tx) => {
      const user = await this.useCode(tx, email, code, "reset");
      await tx.user.update({ where: { id: user.id }, data: { passwordHash } });
      await tx.session.updateMany({
        where: { userId: user.id },
        data: { revokedAt: new Date() },
      });
      await this.queuePasswordChanged(tx, user.id);
      await audit(tx, null, "auth.password_reset", "User", user.id);
    });
    return { ok: true };
  }

  /** Consume a single-use code that belongs to this email. */
  private async useCode(
    tx: Tx,
    email: string,
    code: string,
    purpose: "invite" | "reset",
  ) {
    const invalid = new DomainError(
      "INVALID_CODE",
      "This code is invalid or has expired.",
      422,
    );
    const user = await tx.user.findUnique({ where: { email } });
    if (!user) throw invalid;
    const used = await tx.accessToken.updateMany({
      where: {
        userId: user.id,
        purpose,
        tokenHash: hashCode(normalizeCode(code)),
        usedAt: null,
        expiresAt: { gt: new Date() },
      },
      data: { usedAt: new Date() },
    });
    if (used.count !== 1) throw invalid;
    return user;
  }

  private async queuePasswordChanged(tx: Tx, userId: string) {
    const changedAt = new Date();
    await tx.job.create({
      data: {
        kind: "email",
        key: `password-changed:${userId}:${changedAt.getTime()}`,
        payload: {
          template: "password-changed",
          userId,
          changedAt: changedAt.toISOString(),
        },
      },
    });
  }
}
