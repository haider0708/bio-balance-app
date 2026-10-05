import { Controller, Get, Injectable, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { Database } from "../../../shared/infrastructure/database";
import { requireRule } from "../../../shared/domain/errors";
import { AuthRequest } from "../../../shared/infrastructure/http";
import { Actor } from "../domain/contracts";

const qualityQuery = z.object({
  organizationId: z.uuid().optional(),
  storeId: z.uuid().optional(),
  status: z.enum(["open", "confirmed", "rejected", "all"]).default("open"),
});

@Injectable()
export class QualityService {
  constructor(private readonly db: Database) {}

  /** Flags of one store, of one group or depot, or BioBalance's whole network. */
  list(actor: Actor, raw: unknown) {
    const q = qualityQuery.parse(raw);
    if (q.storeId) {
      requireRule(q.organizationId, "VALIDATION", "Indiquez le groupe.");
      return this.db.scopedSnapshot(
        actor,
        q.organizationId!,
        q.storeId,
        async (tx, scope) => {
          requireRule(
            scope.permissions.includes("manage") || scope.actor.platformAdmin,
            "FORBIDDEN",
            "Accès réservé au responsable.",
            403,
          );
          return this.rows(tx, { storeId: q.storeId }, q.status);
        },
      );
    }
    if (q.organizationId)
      return this.db.group(
        actor,
        q.organizationId,
        (tx) => this.rows(tx, { organizationId: q.organizationId }, q.status),
        false,
      );
    return this.db.authenticated(
      actor,
      async (tx) => {
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
        return this.rows(tx, {}, q.status);
      },
      true,
    );
  }

  private async rows(
    tx: Prisma.TransactionClient,
    where: Prisma.QualityFlagWhereInput,
    status: string,
  ) {
    const flags = await tx.qualityFlag.findMany({
      where: { ...where, ...(status === "all" ? {} : { status }) },
      orderBy: [{ flaggedAt: "desc" }, { id: "desc" }],
      take: 200,
    });
    const deliveries = await tx.delivery.findMany({
      where: {
        id: {
          in: flags.flatMap((f) =>
            f.sourceDeliveryId ? [f.sourceDeliveryId] : [],
          ),
        },
      },
      select: { id: true, sourceStoreId: true },
    });
    const stores = await tx.store.findMany({
      where: {
        id: {
          in: [
            ...flags.map((f) => f.storeId),
            ...deliveries.flatMap((d) =>
              d.sourceStoreId ? [d.sourceStoreId] : [],
            ),
          ],
        },
      },
      select: { id: true, name: true, organizationId: true },
    });
    const groups = await tx.organization.findMany({
      where: { id: { in: [...new Set(flags.map((f) => f.organizationId))] } },
      select: { id: true, name: true },
    });
    const users = await tx.user.findMany({
      where: {
        id: {
          in: flags.flatMap((f) => [
            f.flaggedBy,
            ...(f.decidedBy ? [f.decidedBy] : []),
          ]),
        },
      },
      select: { id: true, name: true },
    });
    const products = await tx.product.findMany({
      where: { id: { in: [...new Set(flags.map((f) => f.productId))] } },
      select: { id: true, name: true },
    });
    const name = <T extends { id: string; name: string }>(
      rows: T[],
      id?: string | null,
    ) => (id ? (rows.find((r) => r.id === id)?.name ?? null) : null);
    return {
      items: flags.map((f) => {
        const source = deliveries.find((d) => d.id === f.sourceDeliveryId);
        return {
          id: f.id,
          organizationId: f.organizationId,
          storeId: f.storeId,
          storeName: name(stores, f.storeId) ?? "Magasin",
          groupName: name(groups, f.organizationId) ?? "Groupe",
          lotId: f.lotId,
          batch: f.batch,
          expiry: f.expiry.toISOString().slice(0, 10),
          productId: f.productId,
          productName: name(products, f.productId) ?? "Produit",
          quantity: f.quantity,
          kind: f.kind,
          note: f.note,
          status: f.status,
          flaggedBy: f.flaggedBy,
          flaggerName: name(users, f.flaggedBy),
          flaggedAt: f.flaggedAt,
          decidedBy: f.decidedBy,
          deciderName: name(users, f.decidedBy),
          decidedAt: f.decidedAt,
          decisionNote: f.decisionNote,
          sourceDeliveryId: f.sourceDeliveryId,
          sourceTicket: f.sourceTicket,
          supplierName: name(stores, source?.sourceStoreId),
          valueMillimes: f.valueMillimes,
          confirmedQuantity: f.confirmedQuantity,
          responsibility: f.responsibility,
          version: f.version,
        };
      }),
    };
  }
}

@ApiTags("quality")
@ApiBearerAuth()
@Controller("v1/quality-flags")
export class QualityController {
  constructor(private readonly service: QualityService) {}
  @Get() list(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.list(r.actor, q);
  }
}
