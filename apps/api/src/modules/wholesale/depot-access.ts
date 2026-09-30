import { Prisma } from "@prisma/client";
import { requireRule } from "../../shared/domain/errors";

/** The one rule for "this account is the responsible account of this depot".
 * BioBalance always passes; a grossiste passes only for its own, wholesale
 * organization, and (unless `allowInactive`) only while that group is active. */
export async function requireDepotAccess(
  tx: Prisma.TransactionClient,
  actor: { id: string; platformAdmin: boolean },
  organizationId: string,
  storeId: string,
  options: { allowInactive?: boolean; message?: string } = {},
) {
  const depot = await tx.store.findFirst({
    where: { id: storeId, organizationId },
  });
  const group = await tx.organization.findUnique({
    where: { id: organizationId },
  });
  const member = await tx.organizationMembership.findUnique({
    where: { organizationId_userId: { organizationId, userId: actor.id } },
  });
  requireRule(
    depot &&
      group?.kind === "wholesale" &&
      (actor.platformAdmin ||
        (member?.active &&
          (options.allowInactive || group.status === "active"))),
    "STORE_ACCESS_REVOKED",
    options.message ?? "Dépôt inaccessible.",
    403,
  );
  return { depot: depot!, group: group! };
}
