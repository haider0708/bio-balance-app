import { Controller, Get, Param, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Injectable } from "@nestjs/common";
import { z } from "zod";
import { Database } from "../../../shared/infrastructure/database";
import { requireRule } from "../../../shared/domain/errors";
import { AuthRequest } from "../../../shared/infrastructure/http";
import { ticketPayload } from "../../../shared/domain/delivery-ticket";
import { requireDepotAccess } from "../../wholesale/depot-access";
import { Actor, DispatchedLine } from "../domain/contracts";

const ticketQuery = z.object({
  // A grossiste names its depot; BioBalance needs neither.
  organizationId: z.uuid().optional(),
  supplierStoreId: z.uuid().optional(),
});

@Injectable()
export class TicketService {
  constructor(private readonly db: Database) {}

  /** The ticket, with its QR, goes to the shipper alone: BioBalance, or the
   * grossiste that shipped. The receiving store never sees the QR. */
  ticket(actor: Actor, id: string, raw: unknown) {
    const q = ticketQuery.parse(raw);
    return this.db.authenticated(actor, async (tx, current) => {
      if (current.platformAdmin) {
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
      } else {
        requireRule(
          q.organizationId && q.supplierStoreId,
          "FORBIDDEN",
          "Bon réservé à l’expéditeur.",
          403,
        );
        await requireDepotAccess(
          tx,
          current,
          q.organizationId!,
          q.supplierStoreId!,
          {
            allowInactive: true,
            message: "Bon réservé à l’expéditeur.",
          },
        );
        await tx.$executeRaw`SELECT set_config('app.supplier_store',${q.supplierStoreId!},true)`;
      }
      const delivery = await tx.delivery.findFirst({
        where: {
          id,
          ...(current.platformAdmin
            ? {}
            : { sourceStoreId: q.supplierStoreId }),
        },
      });
      requireRule(delivery, "NOT_FOUND", "Bon de livraison introuvable.", 404);
      const store = await tx.store.findUniqueOrThrow({
        where: { id: delivery.storeId },
      });
      const group = await tx.organization.findUniqueOrThrow({
        where: { id: delivery.organizationId },
      });
      const source = delivery.sourceStoreId
        ? await tx.store.findUnique({ where: { id: delivery.sourceStoreId } })
        : null;
      const lines = delivery.lines as unknown as DispatchedLine[];
      const total = lines.reduce(
        (sum, l) =>
          l.unitPriceMillimes == null
            ? sum
            : sum + BigInt(l.unitPriceMillimes) * BigInt(l.quantity),
        0n,
      );
      return {
        deliveryId: delivery.id,
        deliveryVersion: delivery.version,
        organizationId: delivery.organizationId,
        storeId: delivery.storeId,
        number: delivery.ticketNumber,
        version: delivery.ticketVersion,
        status: delivery.status,
        qr: ticketPayload(delivery.id, delivery.ticketVersion),
        storeName: store.name,
        groupName: group.name,
        supplierName: source?.name ?? null,
        dispatchedAt: delivery.dispatchedAt,
        lines: lines.map((l) => ({
          productId: l.productId,
          quantity: l.quantity,
          unitPriceMillimes: l.unitPriceMillimes ?? null,
          allocations: (l.allocations ?? []).map((a) => ({
            batch: a.batch,
            expiry: a.expiry,
            quantity: a.quantity,
          })),
        })),
        totalMillimes: lines.some((l) => l.unitPriceMillimes != null)
          ? total
          : null,
      };
    });
  }
}

@ApiTags("deliveries")
@ApiBearerAuth()
@Controller("v1/tickets")
export class TicketController {
  constructor(private readonly service: TicketService) {}
  @Get(":id") get(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Query() q: unknown,
  ) {
    return this.service.ticket(r.actor, z.uuid().parse(id), q);
  }
}
