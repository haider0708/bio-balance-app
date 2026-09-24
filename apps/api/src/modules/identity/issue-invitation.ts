import { createHash, randomBytes } from "node:crypto";
import { Prisma } from "@prisma/client";
import { Actor } from "../operations/domain/contracts";
import { accountLink } from "./account-links";
import { EmailPayload } from "../../shared/email/email-delivery";
import { requireRule } from "../../shared/domain/errors";

export type InvitationGrant = {
  email: string;
  organizationId?: string;
  storeId?: string;
  kind?: string;
  storeIds?: string[];
  permissions: string[];
};
export const invitationLock = (email: string, group?: string | null) =>
  `invite:${group ?? "new-group"}:${email}`;

/** Issue and queue one capability inside the caller's authorized transaction. */
export async function issueInvitation(
  tx: Prisma.TransactionClient,
  actor: Actor,
  grant: InvitationGrant,
) {
  requireRule(
    actor.platformAdmin ||
      grant.email.toLowerCase() !== actor.email.toLowerCase(),
    "SELF_ACCESS_CHANGE",
    "Votre propre accès ne peut pas être modifié par une invitation. Adressez-vous à un autre responsable ou à BioBalance.",
    403,
  );
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${invitationLock(grant.email, grant.organizationId)}, 0))`;
  const token = randomBytes(32).toString("base64url");
  accountLink("invite", token);
  await tx.accessToken.updateMany({
    where: {
      email: grant.email,
      purpose: "invite",
      organizationId: grant.organizationId ?? null,
      usedAt: null,
    },
    data: {
      usedAt: new Date(),
      closedReason: "replaced",
      version: { increment: 1 },
    },
  });
  const invitation = await tx.accessToken.create({
    data: {
      ...grant,
      purpose: "invite",
      createdBy: actor.id,
      tokenHash: createHash("sha256").update(token).digest("hex"),
      expiresAt: new Date(Date.now() + 48 * 3600_000),
    },
  });
  await tx.job.create({
    data: {
      kind: "email",
      key: `invite:${invitation.id}`,
      payload: {
        version: "1",
        template: "invite",
        to: invitation.email,
        accessTokenId: invitation.id,
        token,
      } satisfies EmailPayload,
    },
  });
  await tx.auditEntry.create({
    data: {
      organizationId: grant.organizationId,
      actorId: actor.id,
      action: "identity.invite",
      targetId: invitation.id,
      details: {
        email: grant.email,
        kind: invitation.kind,
        storeIds: invitation.storeIds,
        storeId: grant.storeId ?? null,
      },
    },
  });
  return {
    id: invitation.id,
    email: invitation.email,
    status: "invited" as const,
    expiresAt: invitation.expiresAt,
  };
}
