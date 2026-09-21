import { TOTP, Secret } from "otpauth";
import { Injectable } from "@nestjs/common";
import {
  createHash,
  randomBytes,
  createCipheriv,
  createDecipheriv,
  timingSafeEqual,
} from "node:crypto";
import * as argon2 from "argon2";
import { Database } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";
export const tokenHash = (token: string) =>
  createHash("sha256").update(token).digest("hex");
export function encryptSecret(secret: string): string {
  const key = Buffer.from(process.env.MFA_ENCRYPTION_KEY ?? "", "base64");
  requireRule(
    key.length === 32,
    "MFA_CONFIGURATION",
    "Configuration MFA manquante.",
    503,
  );
  const iv = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", key, iv);
  return Buffer.concat([
    iv,
    cipher.update(secret, "utf8"),
    cipher.final(),
    cipher.getAuthTag(),
  ]).toString("base64");
}
export function decryptSecret(secret: string): string {
  const raw = Buffer.from(secret, "base64");
  const cipher = createDecipheriv(
    "aes-256-gcm",
    Buffer.from(process.env.MFA_ENCRYPTION_KEY ?? "", "base64"),
    raw.subarray(0, 12),
  );
  cipher.setAuthTag(raw.subarray(-16));
  return Buffer.concat([
    cipher.update(raw.subarray(12, -16)),
    cipher.final(),
  ]).toString("utf8");
}
// RFC 6238, SHA-1 / six digits / 30 seconds. Secrets are stored as hexadecimal bytes.
export function totp(secretHex: string, step: bigint): string {
  return new TOTP({
    secret: Secret.fromHex(secretHex),
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  }).generate({ timestamp: Number(step) * 30000 });
}
@Injectable()
export class IdentityService {
  constructor(private readonly db: Database) {}
  async throttle(key: string, limit = 10) {
    const now = new Date(),
      start = new Date(now.getTime() - 900_000);
    const row = await this.db.loginAttempt.upsert({
      where: { key },
      create: { key, count: 1 },
      update: { count: { increment: 1 } },
    });
    if (row.windowStart < start) {
      await this.db.loginAttempt.update({
        where: { key },
        data: { count: 1, windowStart: now },
      });
      return;
    }
    requireRule(
      row.count <= limit,
      "TOO_MANY_ATTEMPTS",
      "Trop de tentatives. Réessayez dans 15 minutes.",
      429,
    );
  }
  async login(
    email: string,
    password: string,
    otp: string | undefined,
    ip: string,
  ) {
    await this.throttle(`ip:${tokenHash(ip)}`, 50);
    await this.throttle(`email:${tokenHash(email)}`);
    const user = await this.db.user.findUnique({ where: { email } });
    // Always perform a password hash operation to avoid a cheap account-enumeration timing path.
    const valid = user
      ? await argon2.verify(user.passwordHash, password)
      : await argon2.hash(password).then(() => false);
    requireRule(
      user && valid && !user.disabled,
      "INVALID_CREDENTIALS",
      "Email ou mot de passe incorrect.",
      401,
    );
    if (user.platformAdmin) {
      requireRule(
        user.mfaSecret,
        "MFA_REQUIRED",
        "La configuration MFA administrateur est obligatoire.",
        401,
      );
      requireRule(
        otp && /^\d{6}$/.test(otp),
        "MFA_REQUIRED",
        "Saisissez le code de votre application d’authentification.",
        401,
      );
      const step = BigInt(Math.floor(Date.now() / 30_000)),
        secret = decryptSecret(user.mfaSecret);
      const matched = [step - 1n, step, step + 1n].find(
        (s) =>
          s > user.lastTotpStep &&
          timingSafeEqual(Buffer.from(totp(secret, s)), Buffer.from(otp)),
      );
      requireRule(
        matched !== undefined,
        "INVALID_MFA",
        "Code MFA invalide ou déjà utilisé.",
        401,
      );
      const claimed = await this.db.user.updateMany({
        where: { id: user.id, lastTotpStep: { lt: matched } },
        data: { lastTotpStep: matched },
      });
      requireRule(
        claimed.count === 1,
        "INVALID_MFA",
        "Code MFA déjà utilisé.",
        401,
      );
    }
    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(Date.now() + 12 * 3600_000);
    await this.db.session.create({
      data: { userId: user.id, tokenHash: tokenHash(token), expiresAt },
    });
    return {
      token,
      expiresAt: expiresAt.toISOString(),
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        platformAdmin: user.platformAdmin,
      },
    };
  }
  async authenticate(token: string): Promise<Actor> {
    requireRule(
      token.length >= 32 && token.length <= 256,
      "SESSION_EXPIRED",
      "Veuillez vous reconnecter.",
      401,
    );
    const session = await this.db.session.findUnique({
      where: { tokenHash: tokenHash(token) },
    });
    requireRule(
      session && !session.revokedAt && session.expiresAt > new Date(),
      "SESSION_EXPIRED",
      "Votre session a expiré. Vos opérations locales sont conservées.",
      401,
    );
    const user = await this.db.user.findUnique({
      where: { id: session.userId },
    });
    requireRule(
      user && !user.disabled,
      "ACCESS_DISABLED",
      "Votre accès est désactivé.",
      403,
    );
    return {
      id: user.id,
      sessionId:session.id,
      email: user.email,
      name: user.name,
      platformAdmin: user.platformAdmin,
    };
  }
  async logout(token: string) {
    await this.db.session.updateMany({
      where: { tokenHash: tokenHash(token) },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  }
  async invite(
    actor: Actor,
    input: {
      email: string;
      organizationId?: string;
      organizationName?: string;
      storeId?: string;
      permissions: string[];
    },
  ) {
    let organizationId = input.organizationId;
    if (input.storeId) {
      requireRule(organizationId, "VALIDATION", "Organisation requise.");
      await this.db.scoped(
        actor,
        organizationId,
        input.storeId,
        async (_tx, scope) => {
          requireRule(
            scope.actor.platformAdmin || scope.permissions.includes("manage"),
            "FORBIDDEN",
            "Accès réservé au responsable.",
            403,
          );
        },
      );
      requireRule(
        input.permissions.every((p) =>
          ["sell", "receive", "manage"].includes(p),
        ),
        "VALIDATION",
        "Permission invalide.",
      );
    } else
      requireRule(
        actor.platformAdmin,
        "FORBIDDEN",
        "Seul BioBalance peut inviter un responsable.",
        403,
      );
    const token = randomBytes(32).toString("base64url");
    return this.db.$transaction(async (tx) => {
      if (!organizationId)
        organizationId = (
          await tx.organization.create({
            data: { name: input.organizationName ?? input.email },
          })
        ).id;
      const invitation = await tx.accessToken.create({
        data: {
          email: input.email,
          tokenHash: tokenHash(token),
          purpose: "invite",
          organizationId,
          storeId: input.storeId,
          permissions: input.permissions,
          createdBy: actor.id,
          expiresAt: new Date(Date.now() + 48 * 3600_000),
        },
      });
      await tx.job.create({
        data: {
          kind: "email",
          key: `invite:${invitation.id}`,
          payload: {
            to: input.email,
            subject: "Votre invitation BioBalance",
            text: `Vous êtes invité sur BioBalance. Ouvrez ${process.env.ACTIVATION_URL ?? "biobalance://activate"}?token=${encodeURIComponent(token)} ou saisissez ce code dans l’application : ${token}. Cette invitation expire dans 48 heures.`,
          },
        },
      });
      await tx.auditEntry.create({
        data: {
          actorId: actor.id,
          organizationId,
          action: "identity.invite",
          targetId: invitation.id,
          details: { email: input.email, storeId: input.storeId ?? null },
        },
      });
      return {
        id: invitation.id,
        email: input.email,
        status: "invited",
        expiresAt: invitation.expiresAt,
      };
    });
  }
  async activate(token: string, name: string, password: string) {
    const hash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 65536,
      timeCost: 3,
    });
    return this.db.$transaction(
      async (tx) => {
        const invite = await tx.accessToken.findUnique({
          where: { tokenHash: tokenHash(token) },
        });
        requireRule(
          invite &&
            invite.purpose === "invite" &&
            !invite.usedAt &&
            invite.expiresAt > new Date(),
          "INVITATION_EXPIRED",
          "Invitation invalide ou expirée. Demandez une nouvelle invitation.",
        );
        const used = await tx.accessToken.updateMany({
          where: { id: invite.id, usedAt: null },
          data: { usedAt: new Date() },
        });
        requireRule(
          used.count === 1,
          "INVITATION_EXPIRED",
          "Invitation déjà utilisée.",
        );
        let user = await tx.user.findUnique({ where: { email: invite.email } });
        if (user) {
          requireRule(
            !user.disabled &&
              (await argon2.verify(user.passwordHash, password)),
            "EXISTING_ACCOUNT",
            "Pour rejoindre ce magasin, saisissez le mot de passe de votre compte existant.",
            401,
          );
        } else
          user = await tx.user.create({
            data: { email: invite.email, name, passwordHash: hash },
          });
        if (invite.storeId) {
          const store = await tx.store.findUniqueOrThrow({
            where: { id: invite.storeId },
          });
          requireRule(
            store.organizationId === invite.organizationId,
            "INVITATION_INVALID",
            "Invitation incohérente.",
          );
          await tx.membership.upsert({
            where: { storeId_userId: { storeId: store.id, userId: user.id } },
            create: {
              organizationId: store.organizationId,
              storeId: store.id,
              userId: user.id,
              permissions: invite.permissions,
            },
            update: { active: true, permissions: invite.permissions },
          });
        } else
          await tx.organizationMembership.upsert({
            where: {
              organizationId_userId: {
                organizationId: invite.organizationId!,
                userId: user.id,
              },
            },
            create: { organizationId: invite.organizationId!, userId: user.id },
            update: { active: true },
          });
        return { ok: true, email: invite.email };
      },
      { timeout: 15000 },
    );
  }
  async forgot(email: string, ip: string) {
    await this.throttle(`reset:${tokenHash(ip)}`, 10);
    const user = await this.db.user.findUnique({ where: { email } });
    if (user && !user.disabled) {
      const token = randomBytes(32).toString("base64url");
      await this.db.$transaction(async (tx) => {
        const reset = await tx.accessToken.create({
          data: {
            email,
            purpose: "reset",
            tokenHash: tokenHash(token),
            permissions: [],
            expiresAt: new Date(Date.now() + 1800_000),
          },
        });
        await tx.job.create({
          data: {
            kind: "email",
            key: `reset:${reset.id}`,
            payload: {
              to: email,
              subject: "Réinitialiser votre mot de passe BioBalance",
              text: `Votre code de réinitialisation : ${token}. Valable 30 minutes. Si vous n’avez pas demandé ce changement, ignorez ce message.`,
            },
          },
        });
      });
    }
    return {
      message: "Si un compte existe, un email de récupération a été envoyé.",
    };
  }
  async reset(token: string, password: string) {
    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 65536,
      timeCost: 3,
    });
    return this.db.$transaction(async (tx) => {
      const reset = await tx.accessToken.findUnique({
        where: { tokenHash: tokenHash(token) },
      });
      requireRule(
        reset &&
          reset.purpose === "reset" &&
          !reset.usedAt &&
          reset.expiresAt > new Date(),
        "RESET_EXPIRED",
        "Code invalide ou expiré.",
      );
      const used = await tx.accessToken.updateMany({
        where: { id: reset.id, usedAt: null },
        data: { usedAt: new Date() },
      });
      requireRule(used.count === 1, "RESET_EXPIRED", "Code déjà utilisé.");
      const user = await tx.user.update({
        where: { email: reset.email },
        data: { passwordHash },
      });
      await tx.session.updateMany({
        where: { userId: user.id },
        data: { revokedAt: new Date() },
      });
      return { ok: true };
    });
  }
}
