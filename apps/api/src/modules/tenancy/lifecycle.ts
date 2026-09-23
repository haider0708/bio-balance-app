import { Prisma } from "@prisma/client";
import { z } from "zod";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";

export const lifecycleRequest = z
  .object({
    operationId: z.uuid(),
    expectedVersion: z.number().int().positive(),
    status: z.enum(["active", "suspended", "archived"]),
    reason: z.string().trim().min(3).max(500),
  })
  .strict();

export async function lifecycleImpact(
  tx: Prisma.TransactionClient,
  organizationId: string,
  storeId?: string,
) {
  const where = { organizationId, ...(storeId ? { storeId } : {}) };
  const [orders, deliveries, rewards, issues, stock] = await Promise.all([
    tx.replenishmentOrder.count({
      where: {
        ...where,
        status: { notIn: ["received", "cancelled", "closed_partial"] },
      },
    }),
    tx.delivery.count({ where: { ...where, status: "dispatched" } }),
    tx.rewardClaim.count({ where: { ...where, status: "requested" } }),
    tx.deliveryIssue.count({
      where: { ...where, status: { not: "resolved" } },
    }),
    tx.inventoryLot.count({
      where: {
        ...where,
        OR: [{ sellable: { not: 0 } }, { damaged: { not: 0 } }],
      },
    }),
  ]);
  return { orders, deliveries, rewards, issues, stockLots: stock };
}

/** Administrative lifecycle changes never rewrite membership choices or ledger history. */
export class WorkspaceLifecycle {
  constructor(private readonly db: Database) {}
  impact(actor: Actor, organizationId: string, storeId?: string) {
    return this.db.group(actor, organizationId, async (tx, current) => {
      requireRule(
        current.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      if (storeId)
        requireRule(
          await tx.store.findFirst({ where: { id: storeId, organizationId } }),
          "NOT_FOUND",
          "Magasin introuvable.",
          404,
        );
      return lifecycleImpact(tx, organizationId, storeId);
    });
  }
  change(
    actor: Actor,
    organizationId: string,
    storeId: string | undefined,
    input: z.infer<typeof lifecycleRequest>,
  ) {
    return this.db.group(actor, organizationId, async (tx, current) => {
      requireRule(
        current.platformAdmin,
        "FORBIDDEN",
        "Action réservée à BioBalance.",
        403,
      );
      const targetId = storeId ?? organizationId;
      const previous = await tx.auditEntry.findFirst({
        where: { operationId: input.operationId },
      });
      if (previous) {
        requireRule(
          previous.actorId === current.id &&
            previous.targetId === targetId &&
            Object.entries(input).every(
              ([key, value]) =>
                (previous.details as Record<string, unknown>)[key] === value,
            ),
          "SUBMISSION_REUSED",
          "Cet identifiant correspond à une autre action.",
          409,
        );
        return { ok: true };
      }
      const record = storeId
        ? await tx.store.findFirst({ where: { id: storeId, organizationId } })
        : await tx.organization.findUnique({ where: { id: organizationId } });
      requireRule(record, "NOT_FOUND", "Espace introuvable.", 404);
      requireRule(
        record.version === input.expectedVersion,
        "VERSION_CONFLICT",
        "Cet espace a changé. Actualisez avant de continuer.",
        409,
      );
      requireRule(
        record.status !== "archived" || input.status === "archived",
        "ARCHIVED",
        "Un espace archivé ne peut pas être réactivé.",
        409,
      );
      if (input.status === "archived") {
        const impact = await lifecycleImpact(tx, organizationId, storeId);
        requireRule(
          Object.values(impact).every((n) => n === 0),
          "OUTSTANDING_WORK",
          "Réglez les commandes, livraisons, récompenses, incidents et stocks avant l’archivage. La suspension reste possible.",
          409,
        );
      }
      if (input.status === "active") {
        const managers = await tx.$queryRaw<
          { count: bigint }[]
        >`SELECT COUNT(*)::bigint AS count FROM "OrganizationMembership" m JOIN "User" u ON u.id=m."userId" WHERE m."organizationId"=${organizationId}::uuid AND m.active AND NOT u.disabled`;
        requireRule(
          managers[0]!.count > 0n,
          "LAST_MANAGER",
          "Ajoutez un responsable actif avant la réactivation.",
          409,
        );
      }
      const data = {
        status: input.status,
        statusReason: input.reason,
        statusChangedAt: new Date(),
        statusChangedBy: current.id,
        version: { increment: 1 },
      };
      if (storeId) await tx.store.update({ where: { id: storeId }, data });
      else
        await tx.organization.update({ where: { id: organizationId }, data });
      await tx.auditEntry.create({
        data: {
          organizationId,
          storeId,
          actorId: current.id,
          operationId: input.operationId,
          action: storeId ? "store.lifecycle" : "group.lifecycle",
          targetId,
          details: json(input),
        },
      });
      return { ok: true };
    });
  }
}
