import {
  Injectable,
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AccessToken, Prisma } from "@prisma/client";
import { z } from "zod";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { AuthRequest } from "../../shared/infrastructure/http";
import { Actor } from "../operations/domain/contracts";
import { issueInvitation, invitationLock } from "./issue-invitation";
import { invitationIsAuthorized } from "./invitation-policy";

export const invitationAction = z
  .object({
    action: z.enum(["resend", "revoke", "archive"]),
    expectedVersion: z.number().int().positive(),
    operationId: z.uuid(),
  })
  .strict();
const listQuery = z.object({
  organizationId: z.uuid().optional(),
  after: z.uuid().optional(),
  includeArchived: z.enum(["true", "false"]).default("false"),
});

export function invitationStatus(row: AccessToken, now = new Date()) {
  if (row.archivedAt) return "archived";
  if (row.acceptedAt) return "accepted";
  if (row.closedReason === "revoked") return "revoked";
  if (row.closedReason === "replaced") return "replaced";
  if (row.usedAt) return "closed"; // Historical consumption did not distinguish replacement from acceptance.
  return row.expiresAt <= now ? "expired" : "pending";
}

@Injectable()
export class InvitationManagementService {
  constructor(private readonly db: Database) {}
  private scoped<T>(
    actor: Actor,
    group: string | undefined,
    work: (tx: Prisma.TransactionClient, current: Actor) => Promise<T>,
  ) {
    return group
      ? this.db.group(actor, group, work)
      : this.db.authenticated(actor, work, true);
  }
  list(actor: Actor, input: z.infer<typeof listQuery>) {
    return this.scoped(actor, input.organizationId, async (tx) => {
      const cursor = input.after
        ? await tx.accessToken.findFirst({
            where: {
              id: input.after,
              purpose: "invite",
              organizationId: input.organizationId ?? null,
            },
          })
        : null;
      requireRule(
        !input.after || cursor,
        "INVALID_CURSOR",
        "Actualisez la liste des invitations.",
      );
      const rows = await tx.accessToken.findMany({
        where: {
          purpose: "invite",
          organizationId: input.organizationId ?? null,
          ...(cursor
            ? {
                OR: [
                  { expiresAt: { lt: cursor.expiresAt } },
                  { expiresAt: cursor.expiresAt, id: { lt: cursor.id } },
                ],
              }
            : {}),
          ...(input.includeArchived === "true" ? {} : { archivedAt: null }),
        },
        orderBy: [{ expiresAt: "desc" }, { id: "desc" }],
        take: 51,
      });
      const items = rows.slice(0, 50).map((row) => ({
        id: row.id,
        email: row.email,
        organizationId: row.organizationId,
        kind: row.kind,
        storeIds: row.storeIds.length
          ? row.storeIds
          : row.storeId
            ? [row.storeId]
            : [],
        status: invitationStatus(row),
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        acceptedAt: row.acceptedAt,
        version: row.version,
      }));
      return { items, nextCursor: rows.length > 50 ? items.at(-1)!.id : null };
    });
  }
  async action(
    actor: Actor,
    id: string,
    input: z.infer<typeof invitationAction>,
  ) {
    const scope = await this.db.accessToken.findFirst({
      where: { id, purpose: "invite" },
      select: { organizationId: true },
    });
    requireRule(scope, "NOT_FOUND", "Invitation introuvable.", 404);
    return this.scoped(
      actor,
      scope.organizationId ?? undefined,
      async (tx, current) => {
        const fingerprint = JSON.stringify([
          id,
          input.action,
          input.expectedVersion,
        ]);
        const previous = await tx.auditEntry.findFirst({
          where: { operationId: input.operationId },
        });
        if (previous) {
          const saved = previous.details as {
            fingerprint?: string;
            result?: { ok: boolean; id: string };
          };
          requireRule(
            previous.actorId === current.id &&
              previous.action === "invitation.action" &&
              saved.fingerprint === fingerprint &&
              saved.result,
            "OPERATION_REUSED",
            "Identifiant d’opération déjà utilisé.",
            409,
          );
          return saved.result;
        }
        const row = await tx.accessToken.findUniqueOrThrow({ where: { id } });
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${invitationLock(row.email, row.organizationId)}, 0))`;
        requireRule(
          row.version === input.expectedVersion,
          "VERSION_CONFLICT",
          "Cette invitation a changé. Actualisez la liste.",
          409,
        );
        requireRule(
          !row.archivedAt,
          "INVITATION_CLOSED",
          "Cette invitation a été retirée de la liste.",
          409,
        );
        let resultId = id;
        if (input.action === "resend") {
          requireRule(
            ["pending", "expired", "revoked"].includes(invitationStatus(row)),
            "INVITATION_CLOSED",
            "Cette invitation est terminée. Gérez l’accès depuis l’équipe.",
            409,
          );
          requireRule(
            await invitationIsAuthorized(tx, { ...row, createdBy: current.id }),
            "FORBIDDEN",
            "Cet accès ne peut plus être accordé. Vérifiez le groupe et le magasin.",
            403,
          );
          const person = await tx.user.findUnique({
            where: { email: row.email },
            select: { id: true },
          });
          if (person && row.organizationId) {
            const member = await tx.organizationMembership.findFirst({
              where: { organizationId: row.organizationId, userId: person.id },
            });
            const seller = await tx.membership.findFirst({
              where: { organizationId: row.organizationId, userId: person.id },
            });
            requireRule(
              !member && !seller,
              "MEMBER_ALREADY_EXISTS",
              "Cette personne appartient déjà au groupe. Modifiez son accès depuis l’équipe.",
              409,
            );
          }
          const next = await issueInvitation(tx, current, {
            email: row.email,
            organizationId: row.organizationId ?? undefined,
            storeId: row.storeId ?? undefined,
            storeIds: row.storeIds,
            kind: row.kind,
            permissions: row.permissions,
          });
          resultId = next.id;
        } else {
          requireRule(
            input.action === "archive" || !row.usedAt,
            "INVITATION_CLOSED",
            "Cette invitation est terminée. Gérez l’accès depuis l’équipe.",
            409,
          );
          await tx.accessToken.update({
            where: { id },
            data: {
              usedAt: row.usedAt ?? new Date(),
              closedReason:
                row.closedReason ?? (row.acceptedAt ? null : "revoked"),
              ...(input.action === "archive" ? { archivedAt: new Date() } : {}),
              version: { increment: 1 },
            },
          });
        }
        const result = { ok: true, id: resultId };
        await tx.auditEntry.create({
          data: {
            organizationId: row.organizationId,
            actorId: current.id,
            operationId: input.operationId,
            action: "invitation.action",
            targetId: id,
            details: json({ fingerprint, action: input.action, result }),
          },
        });
        return result;
      },
    );
  }
}

@ApiTags("identity")
@ApiBearerAuth()
@Controller("v1/identity/invitations")
export class InvitationManagementController {
  constructor(private readonly service: InvitationManagementService) {}
  @Get() list(@Req() req: AuthRequest, @Query() query: unknown) {
    return this.service.list(req.actor, listQuery.parse(query));
  }
  @Post(":id/actions") action(
    @Req() req: AuthRequest,
    @Param("id") id: string,
    @Body() body: unknown,
  ) {
    return this.service.action(
      req.actor,
      z.uuid().parse(id),
      invitationAction.parse(body),
    );
  }
}
