import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient, Prisma } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Actor, Scope } from "../../modules/operations/domain/contracts";
import { DomainError, requireRule } from "../domain/errors";
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
    const session = await tx.session.findFirst({where:{id:actor.sessionId,userId:actor.id,revokedAt:null,expiresAt:{gt:new Date()}}});
    requireRule(session, "SESSION_EXPIRED", "Votre session a expiré. Vos opérations locales sont conservées.", 401);
  }
  async scoped<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    fn: (tx: Prisma.TransactionClient, scope: Scope) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        return await this.$transaction(
          async (tx) => {
            await this.verifySession(tx, actor);
            const store = await tx.store.findFirst({
              where: { id: storeId, organizationId },
            });
            requireRule(store, "STORE_ACCESS_REVOKED", "Magasin inaccessible.", 403);
            const user = await tx.user.findUnique({ where: { id: actor.id } });
            requireRule(
              user && !user.disabled,
              "ACCESS_DISABLED",
              "Votre accès a été désactivé.",
              403,
            );
            const member = await tx.membership.findUnique({
              where: { storeId_userId: { storeId, userId: actor.id } },
            });
            const owner = await tx.organizationMembership.findUnique({
              where: {
                organizationId_userId: { organizationId, userId: actor.id },
              },
            });
            requireRule(
              user.platformAdmin || member?.active || owner?.active,
              "STORE_ACCESS_REVOKED",
              "Magasin inaccessible.",
              403,
            );
            const permissions =
              user.platformAdmin || owner?.active
                ? ["manage", "sell", "receive"]
                : member!.permissions;
            await tx.$executeRaw`SELECT set_config('app.organization_id',${organizationId},true), set_config('app.store_id',${storeId},true), set_config('app.actor_id',${actor.id},true)`;
            const scope: Scope = {
              actor: { ...actor, platformAdmin: user.platformAdmin },
              organizationId,
              storeId,
              timezone: store.timezone,
              permissions,
            };
            return fn(tx, scope);
          },
          { isolationLevel: "Serializable", maxWait: 5000, timeout: 15000 },
        );
      } catch (error) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          (["P2034", "P2002"].includes(error.code) ||
            (error.code === "P2010" &&
              ["40001", "40P01"].includes(
                String(
                  error.meta?.code ??
                    (
                      error.meta?.driverAdapterError as
                        { cause?: { originalCode?: string } } | undefined
                    )?.cause?.originalCode,
                ),
              ))) &&
          attempt < 3
        ) {
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
        throw error;
      }
    }
    throw new DomainError("RETRY_LATER", "Opération occupée. Réessayez.", 503);
  }
}
