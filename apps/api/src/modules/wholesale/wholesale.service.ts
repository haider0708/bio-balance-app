import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";
import { issueInvitation } from "../identity/issue-invitation";
import {
  orderFulfillment,
  supplierNames,
} from "../operations/infrastructure/order-fulfillment-query";
import {
  WholesaleRequests,
  supplierOrdersQuery,
  supplierOrderQuery,
} from "./wholesale.contracts";

const closed = ["received", "cancelled", "closed_partial"];

@Injectable()
export class WholesaleService {
  constructor(private readonly db: Database) {}

  /** A grossiste is a wholesale organization with one depot store and one
   * responsible account, invited by BioBalance. */
  create(actor: Actor, input: z.infer<typeof WholesaleRequests.Create>) {
    return this.db.authenticated(
      actor,
      async (tx, current) => {
        const previous = await tx.auditEntry.findFirst({
          where: { operationId: input.operationId },
        });
        if (previous) {
          const saved = previous.details as {
            fingerprint?: string;
            result?: Record<string, unknown>;
          };
          requireRule(
            previous.actorId === current.id &&
              previous.action === "wholesaler.create" &&
              saved.fingerprint === JSON.stringify(input) &&
              saved.result,
            "OPERATION_REUSED",
            "Identifiant d’opération déjà utilisé.",
            409,
          );
          return this.view(tx, saved.result!.organizationId as string);
        }
        requireRule(
          !(await tx.user.findUnique({ where: { email: input.email } })),
          "EMAIL_IN_USE",
          "Cette adresse email appartient déjà à un compte BioBalance.",
          409,
        );
        // A retry with a fresh operation id must not create a second grossiste.
        requireRule(
          !(await tx.accessToken.findFirst({
            where: {
              email: input.email,
              kind: "wholesaler",
              usedAt: null,
              expiresAt: { gt: new Date() },
            },
          })),
          "INVITATION_PENDING",
          "Une invitation est déjà en attente pour cette adresse. Renvoyez-la depuis la fiche du grossiste.",
          409,
        );
        const organization = await tx.organization.create({
          data: { name: input.name, kind: "wholesale", phone: input.phone },
        });
        // The depot needs no setup guide: its profile is complete by creation.
        const store = await tx.store.create({
          data: {
            organizationId: organization.id,
            name: input.name,
            address: input.address,
            city: input.city,
            phone: input.phone,
            onboardingStep: 5,
          },
        });
        await issueInvitation(tx, current, {
          email: input.email,
          organizationId: organization.id,
          kind: "wholesaler",
          storeIds: [],
          permissions: ["manage", "receive"],
        });
        const result = { organizationId: organization.id, storeId: store.id };
        await tx.auditEntry.create({
          data: {
            organizationId: organization.id,
            storeId: store.id,
            actorId: current.id,
            operationId: input.operationId,
            action: "wholesaler.create",
            targetId: organization.id,
            details: json({ fingerprint: JSON.stringify(input), result }),
          },
        });
        return this.view(tx, organization.id);
      },
      true,
    );
  }

  list(actor: Actor) {
    return this.db.authenticated(
      actor,
      async (tx) => {
        const rows = await tx.organization.findMany({
          where: { kind: "wholesale" },
          orderBy: { name: "asc" },
          take: 500,
        });
        return Promise.all(rows.map((row) => this.view(tx, row.id)));
      },
      true,
    );
  }

  private async view(tx: Prisma.TransactionClient, organizationId: string) {
    const organization = await tx.organization.findUniqueOrThrow({
      where: { id: organizationId },
    });
    const store = await tx.store.findFirstOrThrow({
      where: { organizationId },
      orderBy: { createdAt: "asc" },
    });
    const member = await tx.organizationMembership.findFirst({
      where: { organizationId, active: true },
    });
    const user = member
      ? await tx.user.findUnique({ where: { id: member.userId } })
      : null;
    const invitation = user
      ? null
      : await tx.accessToken.findFirst({
          where: { organizationId, purpose: "invite", kind: "wholesaler" },
          orderBy: { createdAt: "desc" },
        });
    return {
      id: organization.id,
      storeId: store.id,
      name: organization.name,
      address: store.address,
      city: store.city,
      phone: organization.phone,
      status: organization.status,
      version: organization.version,
      createdAt: organization.createdAt,
      contactName: user?.name ?? null,
      contactEmail: user?.email ?? invitation?.email ?? null,
      activated: !!user,
    };
  }

  /** The depot's responsible account, or BioBalance, reads orders assigned to it. */
  private async supplierRead<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ) {
    return this.db.authenticated(actor, async (tx, current) => {
      const depot = await tx.store.findFirst({
        where: { id: storeId, organizationId },
      });
      const group = await tx.organization.findUnique({
        where: { id: organizationId },
      });
      const member = await tx.organizationMembership.findUnique({
        where: {
          organizationId_userId: { organizationId, userId: current.id },
        },
      });
      requireRule(
        depot &&
          group?.kind === "wholesale" &&
          (current.platformAdmin ||
            (member?.active && group.status === "active")),
        "STORE_ACCESS_REVOKED",
        "Dépôt inaccessible.",
        403,
      );
      await tx.$executeRaw`SELECT set_config('app.supplier_store',${storeId},true)`;
      if (current.platformAdmin)
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
      return work(tx);
    });
  }

  private async names(tx: Prisma.TransactionClient, ids: string[]) {
    const stores = await tx.store.findMany({
      where: { id: { in: [...new Set(ids)] } },
      select: { id: true, name: true, organizationId: true },
    });
    const groups = await tx.organization.findMany({
      where: { id: { in: [...new Set(stores.map((s) => s.organizationId))] } },
      select: { id: true, name: true },
    });
    return { stores, groups };
  }

  orders(actor: Actor, raw: unknown) {
    const q = supplierOrdersQuery.parse(raw);
    return this.supplierRead(actor, q.organizationId, q.storeId, async (tx) => {
      const rows = await tx.replenishmentOrder.findMany({
        where: {
          supplierStoreId: q.storeId,
          ...(q.phase === "open"
            ? { status: { notIn: closed } }
            : q.phase === "complete"
              ? { status: { in: closed } }
              : {}),
          ...(q.after ? { id: { gt: q.after } } : {}),
        },
        orderBy: { id: "asc" },
        take: 51,
      });
      const items = rows.slice(0, 50);
      const { stores, groups } = await this.names(
        tx,
        items.map((o) => o.storeId),
      );
      const supplierName = await supplierNames(tx, items);
      return {
        items: items.map((o) => {
          const store = stores.find((s) => s.id === o.storeId);
          return {
            ...o,
            supplierName: supplierName(o),
            storeName: store?.name ?? "Magasin",
            groupName:
              groups.find((g) => g.id === store?.organizationId)?.name ??
              "Groupe",
          };
        }),
        nextCursor: rows.length > 50 ? items.at(-1)!.id : null,
      };
    });
  }

  order(actor: Actor, id: string, raw: unknown) {
    const q = supplierOrderQuery.parse(raw);
    return this.supplierRead(actor, q.organizationId, q.storeId, async (tx) => {
      const order = await tx.replenishmentOrder.findFirst({
        where: { id, supplierStoreId: q.storeId },
      });
      requireRule(order, "NOT_FOUND", "Commande introuvable.", 404);
      const { stores, groups } = await this.names(tx, [order.storeId]);
      const store = stores[0];
      const deliveries = await tx.delivery.findMany({
        where: { orderId: id, sourceStoreId: q.storeId },
        orderBy: { id: "asc" },
      });
      const fulfillment =
        (
          await orderFulfillment(tx, order.organizationId, order.storeId, [
            order,
          ])
        ).get(id) ?? [];
      return {
        order: {
          ...order,
          supplierName: (await supplierNames(tx, [order]))(order),
          storeName: store?.name ?? "Magasin",
          groupName:
            groups.find((g) => g.id === store?.organizationId)?.name ??
            "Groupe",
        },
        deliveries,
        receipts: await tx.deliveryReceipt.findMany({
          where: { deliveryId: { in: deliveries.map((d) => d.id) } },
          orderBy: { createdAt: "asc" },
        }),
        issues: await tx.deliveryIssue.findMany({
          where: { orderId: id },
          orderBy: { createdAt: "asc" },
        }),
        fulfillment,
      };
    });
  }
}
