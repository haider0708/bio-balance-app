import { AccessToken, Prisma } from "@prisma/client";

/** The same deferred-grant policy applies before delivery and activation. */
export async function invitationIsAuthorized(
  tx: Prisma.TransactionClient,
  invitation: AccessToken,
) {
  const issuer = invitation.createdBy
    ? await tx.user.findUnique({ where: { id: invitation.createdBy } })
    : null;
  if (!issuer || issuer.disabled) return false;
  if (invitation.kind === "new_group")
    return issuer.platformAdmin && !invitation.organizationId;
  if (!invitation.organizationId) return false;
  const organization = await tx.organization.findUnique({
    where: { id: invitation.organizationId },
  });
  if (!organization || organization.status !== "active") return false;
  if (invitation.kind === "responsible" || invitation.kind === "salesperson") {
    if (
      invitation.kind === "salesperson" &&
      (invitation.storeIds.length !== 1 ||
        (await tx.store.count({
          where: {
            id: { in: invitation.storeIds },
            organizationId: invitation.organizationId,
            status: "active",
          },
        })) !== invitation.storeIds.length)
    )
      return false;
    if (issuer.platformAdmin) return true;
    const groupMember = await tx.organizationMembership.findUnique({
      where: {
        organizationId_userId: {
          organizationId: invitation.organizationId,
          userId: issuer.id,
        },
      },
    });
    return groupMember?.active === true;
  }
  if (!invitation.storeId) return issuer.platformAdmin;
  const store = await tx.store.findUnique({
    where: { id: invitation.storeId },
  });
  if (
    !store ||
    store.status !== "active" ||
    store.organizationId !== invitation.organizationId
  )
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
