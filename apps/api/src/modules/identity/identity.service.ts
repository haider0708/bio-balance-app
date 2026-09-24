import { issueInvitation } from "./issue-invitation";
import { accountLink } from "./account-links";
import { invitationIsAuthorized } from "./invitation-policy";
import type { EmailPayload } from "../../shared/email/email-delivery";
import { Prisma } from "@prisma/client";
import { TOTP, Secret } from "otpauth";
import { Injectable } from "@nestjs/common";
import { recoveryCode, normalizeRecoveryCode } from "./recovery-code";
import {
  createHash,
  randomBytes,
  createCipheriv,
  createDecipheriv,
  timingSafeEqual,
} from "node:crypto";
import { PasswordHasher } from "./password-hasher";
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
  constructor(
    private readonly db: Database,
    private readonly passwords: PasswordHasher = new PasswordHasher(),
  ) {}
  async throttle(key: string, limit = 10) {
    const now = new Date(),
      start = new Date(now.getTime() - 900_000);
    const [row] = await this.db.$queryRaw<{ count: number }[]>`
      INSERT INTO "LoginAttempt" (key, count, "windowStart") VALUES (${key}, 1, ${now})
      ON CONFLICT (key) DO UPDATE SET
        count = CASE WHEN "LoginAttempt"."windowStart" <= ${start} THEN 1 ELSE LEAST("LoginAttempt".count + 1, 1000000) END,
        "windowStart" = CASE WHEN "LoginAttempt"."windowStart" <= ${start} THEN ${now} ELSE "LoginAttempt"."windowStart" END
      RETURNING count`;
    requireRule(
      row!.count <= limit,
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
      ? await this.passwords.verify(user.passwordHash, password)
      : await this.passwords.hash(password).then(() => false);
    requireRule(
      user && valid && !user.disabled,
      "INVALID_CREDENTIALS",
      "Email ou mot de passe incorrect.",
      401,
    );
    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(Date.now() + 12 * 3600_000);
    await this.db.transaction(async (tx) => {
      // Serialize session issuance with password replacement. Hashing stays outside
      // the transaction, and the credential snapshot is checked again under lock.
      await tx.$queryRaw`SELECT id FROM "User" WHERE id=${user.id}::uuid FOR UPDATE`;
      const current = await tx.user.findUniqueOrThrow({
        where: { id: user.id },
      });
      requireRule(
        !current.disabled &&
          current.passwordHash === user.passwordHash &&
          current.platformAdmin === user.platformAdmin &&
          current.mfaSecret === user.mfaSecret,
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
        const claimed = await tx.user.updateMany({
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

      await tx.session.create({
        data: { userId: user.id, tokenHash: tokenHash(token), expiresAt },
      });
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
    const [user] = await this.db.$queryRaw<(Actor & { disabled: boolean })[]>`
      SELECT u.id,u.email,u.name,u."platformAdmin",u.disabled,s.id AS "sessionId"
      FROM "Session" s JOIN "User" u ON u.id=s."userId"
      WHERE s."tokenHash"=${tokenHash(token)} AND s."revokedAt" IS NULL
        AND s."expiresAt">(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')`;
    requireRule(
      user,
      "SESSION_EXPIRED",
      "Votre session a expiré. Vos opérations locales sont conservées.",
      401,
    );
    requireRule(
      !user.disabled,
      "ACCESS_DISABLED",
      "Votre accès est désactivé.",
      403,
    );
    return {
      id: user.id,
      sessionId: user.sessionId,
      email: user.email,
      name: user.name,
      platformAdmin: user.platformAdmin,
    };
  }

  async logout(token: string) {
    await this.db.transaction(async (tx) => {
      const session = await tx.session.findUnique({
        where: { tokenHash: tokenHash(token) },
      });
      if (!session) return;
      await tx.session.update({
        where: { id: session.id },
        data: { revokedAt: new Date() },
      });
      await tx.deviceToken.deleteMany({ where: { sessionId: session.id } });
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
      kind?: "new_group" | "responsible" | "salesperson";
      storeIds?: string[];
    },
  ) {
    if (input.kind)
      return this.inviteGroupAccess(
        actor,
        input as typeof input & {
          kind: "new_group" | "responsible" | "salesperson";
        },
      );
    const organizationId = input.organizationId;
    if (input.storeId) {
      requireRule(organizationId, "VALIDATION", "Organisation requise.");
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
    const create = async (tx: Prisma.TransactionClient) => {
      const targetOrganization =
        organizationId ??
        (
          await tx.organization.create({
            data: { name: input.organizationName ?? input.email },
          })
        ).id;
      return issueInvitation(tx, actor, {
        email: input.email,
        organizationId: targetOrganization,
        storeId: input.storeId,
        permissions: input.permissions,
      });
    };
    if (input.storeId) {
      return this.db.scoped(
        actor,
        organizationId!,
        input.storeId,
        async (tx, scope) => {
          requireRule(
            scope.actor.platformAdmin || scope.permissions.includes("manage"),
            "FORBIDDEN",
            "Accès réservé au responsable.",
            403,
          );
          return create(tx);
        },
      );
    }
    return this.db.authenticated(actor, (tx) => create(tx), true);
  }

  private inviteGroupAccess(
    actor: Actor,
    input: {
      email: string;
      kind: "new_group" | "responsible" | "salesperson";
      organizationId?: string;
      storeIds?: string[];
    },
  ) {
    requireRule(
      input.kind === "new_group" || input.organizationId,
      "VALIDATION",
      "Groupe requis.",
    );
    const create = async (tx: Prisma.TransactionClient) => {
      // Serializes simultaneous invitations for the same person and group.
      // Replaced capabilities remain in history, but can no longer activate.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`invite:${input.organizationId ?? "new-group"}:${input.email}`}, 0))`;
      if (input.organizationId) {
        const member = await tx.user.findUnique({
          where: { email: input.email },
          select: { id: true },
        });
        if (member) {
          const [responsible, seller] = await Promise.all([
            tx.organizationMembership.findFirst({
              where: {
                organizationId: input.organizationId,
                userId: member.id,
              },
            }),
            tx.membership.findFirst({
              where: {
                organizationId: input.organizationId,
                userId: member.id,
              },
            }),
          ]);
          requireRule(
            !responsible && !seller,
            "MEMBER_ALREADY_EXISTS",
            "Cette personne appartient déjà au groupe. Modifiez son accès depuis l’équipe.",
            409,
          );
        }
      }
      if (input.organizationId) {
        const group = await tx.organization.findUnique({
          where: { id: input.organizationId },
        });
        requireRule(
          group?.status === "active",
          "GROUP_ACCESS_REVOKED",
          "Ce groupe n’est pas actif. Réactivez-le avant d’inviter une personne.",
          403,
        );
      }
      const storeIds = [...new Set(input.storeIds ?? [])];
      if (input.kind === "new_group")
        requireRule(
          !input.organizationId && !storeIds.length,
          "VALIDATION",
          "Une invitation de groupe ne sélectionne pas de magasin.",
        );
      else {
        requireRule(input.organizationId, "VALIDATION", "Groupe requis.");
        requireRule(
          input.kind !== "salesperson" || storeIds.length === 1,
          "STORE_REQUIRED",
          "Choisissez un seul magasin pour ce vendeur.",
        );
        const count = await tx.store.count({
          where: {
            organizationId: input.organizationId,
            id: { in: storeIds },
            status: "active",
          },
        });
        requireRule(
          count === storeIds.length,
          "STORE_SCOPE",
          "Magasin extérieur au groupe.",
        );
      }
      return issueInvitation(tx, actor, {
        email: input.email,
        kind: input.kind,
        organizationId: input.organizationId,
        storeIds,
        permissions:
          input.kind === "salesperson"
            ? ["sell"]
            : ["manage", "sell", "receive"],
      });
    };
    return input.kind === "new_group"
      ? this.db.authenticated(actor, create, true)
      : this.db.group(actor, input.organizationId!, create);
  }

  private async validToken(
    token: string,
    purpose: "invite" | "reset",
    ip: string,
  ) {
    await this.throttle(`account-flow:${tokenHash(ip)}`, 30);
    await this.throttle(`account-token:${tokenHash(token)}`, 10);
    const row = await this.db.accessToken.findUnique({
      where: { tokenHash: tokenHash(token) },
    });
    requireRule(
      row &&
        row.purpose === purpose &&
        !row.usedAt &&
        row.expiresAt > new Date(),
      purpose === "invite" ? "INVITATION_EXPIRED" : "RESET_EXPIRED",
      "Code invalide ou expiré.",
    );
    return row;
  }

  async activate(
    token: string,
    name: string,
    password: string,
    ip = "internal",
  ) {
    const invitation = await this.validToken(token, "invite", ip);
    const existing = await this.db.user.findUnique({
      where: { email: invitation.email },
    });
    const validExisting = existing
      ? await this.passwords.verify(existing.passwordHash, password)
      : false;
    requireRule(
      !existing || (!existing.disabled && validExisting),
      "EXISTING_ACCOUNT",
      "Pour rejoindre ce magasin, saisissez le mot de passe de votre compte existant.",
      401,
    );
    const hash =
      existing?.passwordHash ?? (await this.passwords.hash(password));
    return this.db.transaction(async (tx) => {
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
      requireRule(
        await invitationIsAuthorized(tx, invite),
        "INVITATION_EXPIRED",
        "Cette invitation n’est plus autorisée. Demandez une nouvelle invitation.",
      );
      const used = await tx.accessToken.updateMany({
        where: { id: invite.id, usedAt: null, expiresAt: { gt: new Date() } },
        data: {
          usedAt: new Date(),
          acceptedAt: new Date(),
          version: { increment: 1 },
        },
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
            existing?.id === user.id &&
            user.passwordHash === existing.passwordHash,
          "EXISTING_ACCOUNT",
          "Pour rejoindre ce magasin, saisissez le mot de passe de votre compte existant.",
          401,
        );
      } else
        user = await tx.user.create({
          data: { email: invite.email, name, passwordHash: hash },
        });
      if (invite.kind === "new_group") {
        await tx.groupCreationGrant.create({
          data: {
            id: invite.id,
            userId: user.id,
            createdBy: invite.createdBy!,
          },
        });
      } else if (invite.kind === "salesperson") {
        for (const storeId of invite.storeIds) {
          await tx.$executeRaw`SELECT set_config('app.organization_id',${invite.organizationId!},true),set_config('app.store_id',${storeId},true),set_config('app.actor_id',${user.id},true)`;
          await tx.membership.upsert({
            where: { storeId_userId: { storeId, userId: user.id } },
            create: {
              organizationId: invite.organizationId!,
              storeId,
              userId: user.id,
              permissions: ["sell"],
            },
            update: { active: true, permissions: ["sell"] },
          });
        }
      } else if (invite.storeId) {
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
            permissions: invite.permissions.filter(
              (p) => p !== "receive" || invite.permissions.includes("manage"),
            ),
          },
          update: {
            active: true,
            permissions: invite.permissions.filter(
              (p) => p !== "receive" || invite.permissions.includes("manage"),
            ),
          },
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
    });
  }
  async forgot(email: string, ip: string) {
    await this.throttle(`reset:${tokenHash(ip)}`, 10);
    await this.throttle(`reset-address:${tokenHash(email)}`, 3);
    const user = await this.db.user.findUnique({ where: { email } });
    if (user && !user.disabled) {
      // Serialize replacement requests per account. A rare short-code collision
      // rolls back and generates a fresh code without invalidating the old one.
      for (let attempt = 0; ; attempt++) {
        try {
          const token = recoveryCode();
          accountLink("reset", token);
          await this.db.$transaction(async (tx) => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`password-reset:${email}`},0))`;
            await tx.accessToken.updateMany({
              where: { email, purpose: "reset", usedAt: null },
              data: { usedAt: new Date() },
            });
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
                  version: "1",
                  template: "reset",
                  to: email,
                  accessTokenId: reset.id,
                  token,
                } satisfies EmailPayload,
              },
            });
          });
          break;
        } catch (error) {
          if (
            !(error instanceof Prisma.PrismaClientKnownRequestError) ||
            error.code !== "P2002" ||
            attempt >= 2
          )
            throw error;
        }
      }
    }
    return {
      message: "Si un compte existe, un email de récupération a été envoyé.",
    };
  }
  async reset(token: string, password: string, ip = "internal") {
    token = normalizeRecoveryCode(token);
    await this.validToken(token, "reset", ip);
    const passwordHash = await this.passwords.hash(password);
    return this.db.transaction(async (tx) => {
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
      const current = await tx.user.findUnique({
        where: { email: reset.email },
      });
      requireRule(
        current && !current.disabled,
        "RESET_EXPIRED",
        "Code invalide ou expiré.",
      );
      const used = await tx.accessToken.updateMany({
        where: { id: reset.id, usedAt: null, expiresAt: { gt: new Date() } },
        data: { usedAt: new Date() },
      });
      requireRule(used.count === 1, "RESET_EXPIRED", "Code déjà utilisé.");
      const user = await tx.user.update({
        where: { email: reset.email },
        data: { passwordHash },
      });
      await tx.accessToken.updateMany({
        where: { email: user.email, purpose: "reset", usedAt: null },
        data: { usedAt: new Date() },
      });
      const changedAt = new Date();
      await tx.session.updateMany({
        where: { userId: user.id },
        data: { revokedAt: changedAt },
      });
      await tx.job.create({
        data: {
          kind: "email",
          key: `password-changed:${reset.id}`,
          payload: {
            version: "1",
            template: "password-changed",
            to: user.email,
            userId: user.id,
            changedAt: changedAt.toISOString(),
          } satisfies EmailPayload,
        },
      });
      return { ok: true };
    });
  }
}
