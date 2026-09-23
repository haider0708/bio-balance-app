import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient, Prisma } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Actor, Scope } from "../../modules/operations/domain/contracts";
import { DomainError, requireRule } from "../domain/errors";
function isRetryableTransaction(error: unknown): boolean {
  // The pg adapter can expose commit-time serialization failures directly,
  // while statement failures are wrapped by Prisma.
  if (error instanceof Error && error.name === "DriverAdapterError") {
    const cause = error.cause as { originalCode?: string } | undefined;
    return ["40001", "40P01"].includes(cause?.originalCode ?? "");
  }
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) return false;
  if (["P2034", "P2002"].includes(error.code)) return true;
  const cause = error.meta?.driverAdapterError as
    { cause?: { originalCode?: string } } | undefined;
  return (
    error.code === "P2010" &&
    ["40001", "40P01"].includes(
      String(error.meta?.code ?? cause?.cause?.originalCode),
    )
  );
}
export function json(value: unknown): Prisma.InputJsonValue {
  return JSON.parse(
    JSON.stringify(value, (_k, v) =>
      typeof v === "bigint" ? v.toString() : v,
    ),
  );
}
@Injectable()
export class Database extends PrismaClient implements OnModuleDestroy {
  constructor() {
    super({
      adapter: new PrismaPg({
        connectionString: process.env.DATABASE_URL,
        max: 12,
      }),
    });
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
  async verifySession(tx: Prisma.TransactionClient, actor: Actor) {
    if (!actor.sessionId) return; // Internal jobs/tests carry explicit server actors.
    const session = await tx.session.findFirst({
      where: {
        id: actor.sessionId,
        userId: actor.id,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
    });
    requireRule(
      session,
      "SESSION_EXPIRED",
      "Votre session a expiré. Vos opérations locales sont conservées.",
      401,
    );
  }
  async scoped<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    fn: (tx: Prisma.TransactionClient, scope: Scope) => Promise<T>,
  ): Promise<T> {
    return this.withScope(actor, organizationId, storeId, fn, "Serializable");
  }

  /** A consistent read view without retaining SSI predicate locks. Only
   * pagination metadata may be persisted here; business writes use scoped(). */
  scopedSnapshot<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    fn: (tx: Prisma.TransactionClient, scope: Scope) => Promise<T>,
  ): Promise<T> {
    return this.withScope(actor, organizationId, storeId, fn, "RepeatableRead");
  }

  private withScope<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    fn: (tx: Prisma.TransactionClient, scope: Scope) => Promise<T>,
    isolationLevel: Prisma.TransactionIsolationLevel,
  ): Promise<T> {
    return this.transaction(async (tx) => {
      // Resolve current identity, session and membership in the same
      // transaction as the operation, with one indexed read.
      const [access] = await tx.$queryRaw<
        {
          storeId: string | null;
          storeStatus: string | null;
          groupStatus: string | null;
          userId: string | null;
          timezone: string | null;
          disabled: boolean | null;
          platformAdmin: boolean | null;
          memberActive: boolean;
          ownerActive: boolean;
          permissions: string[];
          sessionValid: boolean;
        }[]
      >`SELECT s.id AS "storeId",s.status AS "storeStatus",g.status AS "groupStatus",s.timezone,u.id AS "userId",u.disabled,u."platformAdmin",
              COALESCE(m.active,false) AS "memberActive",COALESCE(o.active,false) AS "ownerActive",
              COALESCE(m.permissions,'{}'::text[]) AS permissions,
              (${actor.sessionId ?? null}::uuid IS NULL OR EXISTS(
                SELECT 1 FROM "Session" ss WHERE ss.id=${actor.sessionId ?? null}::uuid
                AND ss."userId"=${actor.id}::uuid AND ss."revokedAt" IS NULL
                AND ss."expiresAt">(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'))) AS "sessionValid"
              FROM (SELECT 1) anchor
              LEFT JOIN "Store" s ON s.id=${storeId}::uuid AND s."organizationId"=${organizationId}::uuid
              LEFT JOIN "Organization" g ON g.id=s."organizationId"
              LEFT JOIN "User" u ON u.id=${actor.id}::uuid
              LEFT JOIN "Membership" m ON m."storeId"=s.id AND m."userId"=u.id
              LEFT JOIN "OrganizationMembership" o ON o."organizationId"=s."organizationId" AND o."userId"=u.id`;
      requireRule(
        access,
        "INTERNAL_ERROR",
        "Vérification d’accès indisponible.",
        500,
      );
      requireRule(
        access.sessionValid,
        "SESSION_EXPIRED",
        "Votre session a expiré. Vos opérations locales sont conservées.",
        401,
      );
      requireRule(
        access.storeId,
        "STORE_ACCESS_REVOKED",
        "Magasin inaccessible.",
        403,
      );
      requireRule(
        access.userId && !access.disabled,
        "ACCESS_DISABLED",
        "Votre accès a été désactivé.",
        403,
      );
      requireRule(
        access.platformAdmin || access.memberActive || access.ownerActive,
        "STORE_ACCESS_REVOKED",
        "Magasin inaccessible.",
        403,
      );
      requireRule(
        access.platformAdmin ||
          (access.storeStatus === "active" && access.groupStatus === "active"),
        "STORE_ACCESS_REVOKED",
        "Ce magasin ou son groupe est suspendu ou archivé. Vos opérations locales sont conservées.",
        403,
      );
      requireRule(
        isolationLevel !== "Serializable" ||
          (access.storeStatus !== "archived" &&
            access.groupStatus !== "archived"),
        "WORKSPACE_ARCHIVED",
        "Cet espace est archivé. Son historique reste consultable, mais aucune nouvelle opération n’est autorisée.",
        409,
      );
      const permissions =
        access.platformAdmin || access.ownerActive
          ? ["manage", "sell", "receive"]
          : access.permissions.filter(
              (p) => p !== "receive" || access.permissions.includes("manage"),
            );
      await tx.$executeRaw`SELECT set_config('app.organization_id',${organizationId},true), set_config('app.store_id',${storeId},true), set_config('app.actor_id',${actor.id},true)`;
      const scope: Scope = {
        actor: { ...actor, platformAdmin: access.platformAdmin! },
        organizationId,
        storeId,
        timezone: access.timezone!,
        permissions,
      };
      return fn(tx, scope);
    }, isolationLevel);
  }

  /** Database-only callbacks may be retried; external effects belong in jobs. */
  async transaction<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
    isolationLevel: Prisma.TransactionIsolationLevel = "Serializable",
  ): Promise<T> {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        return await this.$transaction(work, {
          isolationLevel,
          maxWait: 5000,
          timeout: 15000,
        });
      } catch (error) {
        if (isRetryableTransaction(error) && attempt < 3) {
          await new Promise((r) =>
            setTimeout(r, 20 * 2 ** attempt + Math.random() * 20),
          );
          continue;
        }
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2002"
        )
          throw new DomainError(
            "DUPLICATE_RESOURCE",
            "Cet enregistrement existe déjà.",
            409,
          );
        if (isRetryableTransaction(error))
          throw new DomainError(
            "RETRY_LATER",
            "Opération occupée. Réessayez.",
            503,
          );
        throw error;
      }
    }
    throw new DomainError("RETRY_LATER", "Opération occupée. Réessayez.", 503);
  }

  async currentActor(
    tx: Prisma.TransactionClient,
    actor: Actor,
  ): Promise<Actor> {
    const [user] = await tx.$queryRaw<
      (Actor & { disabled: boolean; sessionValid: boolean })[]
    >`
      SELECT u.id,u.name,u.email,u."platformAdmin",u.disabled,
        (${actor.sessionId ?? null}::uuid IS NULL OR EXISTS(SELECT 1 FROM "Session" s
          WHERE s.id=${actor.sessionId ?? null}::uuid AND s."userId"=u.id AND s."revokedAt" IS NULL
            AND s."expiresAt">(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'))) AS "sessionValid",
        set_config('app.actor_id',${actor.id},true)
      FROM "User" u WHERE u.id=${actor.id}::uuid`;
    requireRule(
      user?.sessionValid,
      "SESSION_EXPIRED",
      "Votre session a expiré. Vos opérations locales sont conservées.",
      401,
    );
    requireRule(
      !user.disabled,
      "ACCESS_DISABLED",
      "Votre accès a été désactivé.",
      403,
    );
    return {
      id: user.id,
      name: user.name,
      email: user.email,
      platformAdmin: user.platformAdmin,
      sessionId: actor.sessionId,
    };
  }

  /** Global endpoints use current identity in the same transaction as their work. */
  group<T>(
    actor: Actor,
    organizationId: string,
    work: (tx: Prisma.TransactionClient, current: Actor) => Promise<T>,
    lock = true,
  ): Promise<T> {
    return this.authenticated(actor, async (tx, current) => {
      // Serializes membership changes, including concurrent last-manager removals.
      const groups = await tx.$queryRaw<{ id: string; status: string }[]>(
        Prisma.sql`SELECT id,status FROM "Organization" WHERE id=${organizationId}::uuid ${lock ? Prisma.sql`FOR UPDATE` : Prisma.empty}`,
      );
      const membership = await tx.organizationMembership.findUnique({
        where: {
          organizationId_userId: { organizationId, userId: current.id },
        },
      });
      requireRule(
        groups.length === 1 &&
          (current.platformAdmin ||
            (membership?.active && groups[0]!.status === "active")),
        "GROUP_ACCESS_REVOKED",
        "Ce groupe n’est plus accessible.",
        403,
      );
      await tx.$executeRaw`SELECT set_config('app.organization_id',${organizationId},true),set_config('app.group_read','true',true)`;
      if (current.platformAdmin)
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
      return work(tx, current);
    });
  }

  authenticated<T>(
    actor: Actor,
    work: (tx: Prisma.TransactionClient, current: Actor) => Promise<T>,
    admin = false,
  ): Promise<T> {
    return this.transaction(async (tx) => {
      const current = await this.currentActor(tx, actor);
      requireRule(
        !admin || current.platformAdmin,
        "FORBIDDEN",
        "Accès réservé à BioBalance.",
        403,
      );
      return work(tx, current);
    });
  }
}
