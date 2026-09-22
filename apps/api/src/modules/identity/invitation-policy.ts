import { AccessToken, Prisma } from "@prisma/client";

/** The same deferred-grant policy applies before delivery and activation. */
export async function invitationIsAuthorized(
  tx: Prisma.TransactionClient,
  invitation: AccessToken,
) {
  const issuer = invitation.createdBy
    ? await tx.user.findUnique({ where: { id: invitation.createdBy } })
    : null;
  if (!issuer || issuer.disabled || !invitation.organizationId) return false;
  const organization = await tx.organization.findUnique({
    where: { id: invitation.organizationId },
  });
  if (!organization) return false;
  if (!invitation.storeId) return issuer.platformAdmin;
  const store = await tx.store.findUnique({
    where: { id: invitation.storeId },
  });
  if (!store || store.organizationId !== invitation.organizationId)
    return false;
  if (issuer.platformAdmin) return true;
  const owner = await tx.organizationMembership.findUnique({
    where: {
      organizationId_userId: {
        organizationId: invitation.organizationId,
        userId: issuer.id,
      },
    },
  });
  if (owner?.active) return true;
  const member = await tx.membership.findUnique({
    where: {
      storeId_userId: { storeId: invitation.storeId, userId: issuer.id },
    },
  });
  return member?.active === true && member.permissions.includes("manage");
}
