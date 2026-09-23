import { monthlyRanking } from "./monthly-ranking";
import { localDate } from "../../shared/domain/money";
import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { Database } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";
import { DashboardQuery } from "./dashboard.contracts";
import { orderFulfillment } from "../operations/infrastructure/order-fulfillment-query";
type Sum = { netMillimes: bigint; netUnits: bigint; saleCount: bigint };
const summed = (value: Sum): Sum => ({
  netMillimes: value.netMillimes,
  netUnits: value.netUnits,
  saleCount: value.saleCount,
});
const totalSql = Prisma.sql`COALESCE(SUM("netMillimes"),0)::bigint AS "netMillimes",COALESCE(SUM("netUnits"),0)::bigint AS "netUnits",COALESCE(SUM("saleCount"),0)::bigint AS "saleCount"`;
@Injectable()
export class DashboardService {
  constructor(private readonly db: Database) {}
  scope<T>(
    actor: Actor,
    q: DashboardQuery,
    work: (tx: Prisma.TransactionClient, current: Actor) => Promise<T>,
  ): Promise<T> {
    if (q.scope === "network")
      return this.db.authenticated(
        actor,
        async (tx, current) => {
          await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
          const result = await work(tx, current);
          await tx.auditEntry.create({
            data: {
              actorId: current.id,
              action: "dashboard.network.read",
              targetId: "network",
              details: { from: q.from, to: q.to },
            },
          });
          return result;
        },
        true,
      );
    if (q.scope === "group")
      return this.db.group(actor, q.organizationId!, work, false);
    return this.db.scopedSnapshot(
      actor,
      q.organizationId!,
      q.storeId!,
      async (tx, scope) => {
        requireRule(
          q.scope === "personal" || scope.permissions.includes("manage"),
          "FORBIDDEN",
          "Accès réservé au responsable.",
          403,
        );
        return work(tx, scope.actor);
      },
    );
  }
  where(q: DashboardQuery, actor: Actor) {
    return Prisma.join(
      [
        Prisma.sql`day>=${new Date(q.from)}::date AND day<=${new Date(q.to)}::date`,
        ...(q.organizationId
          ? [Prisma.sql`"organizationId"=${q.organizationId}::uuid`]
          : []),
        ...(q.storeId ? [Prisma.sql`"storeId"=${q.storeId}::uuid`] : []),
        ...(q.scope === "personal"
          ? [Prisma.sql`"sellerId"=${actor.id}::uuid`]
          : []),
      ],
      " AND ",
    );
  }
  sales(actor: Actor, q: DashboardQuery, after?: string) {
    return this.scope(actor, q, async (tx, current) => {
      const rows = await tx.salesContribution.findMany({
        where: {
          ...(q.organizationId ? { organizationId: q.organizationId } : {}),
          ...(q.storeId ? { storeId: q.storeId } : {}),
          ...(q.scope === "personal" ? { sellerId: current.id } : {}),
          day: { gte: new Date(q.from), lte: new Date(q.to) },
          ...(after ? { saleId: { gt: after } } : {}),
        },
        orderBy: { saleId: "asc" },
        take: 101,
      });
      const ids = rows.slice(0, 100).map((r) => r.saleId);
      const sales = await tx.sale.findMany({
        where: { id: { in: ids } },
        select: { id: true, occurredAt: true, version: true },
      });
      const stores = await tx.store.findMany({
        where: { id: { in: rows.map((r) => r.storeId) } },
        select: { id: true, name: true },
      });
      const users = await tx.user.findMany({
        where: { id: { in: rows.map((r) => r.sellerId) } },
        select: { id: true, name: true },
      });
      return {
        items: rows.slice(0, 100).map((r) => ({
          id: r.saleId,
          organizationId: r.organizationId,
          storeId: r.storeId,
          sellerId: r.sellerId,
          day: r.day.toISOString().slice(0, 10),
          occurredAt: sales.find((s) => s.id === r.saleId)!.occurredAt,
          version: r.version,
          netMillimes: r.netMillimes,
          netUnits: r.netUnits,
          storeName: stores.find((s) => s.id === r.storeId)!.name,
          sellerName: users.find((u) => u.id === r.sellerId)!.name,
        })),
        nextCursor: rows.length > 100 ? rows[99]!.saleId : null,
      };
    });
  }
  get(actor: Actor, q: DashboardQuery) {
    return this.scope(actor, q, async (tx, current) => {
      const where = this.where(q, current);
      const dimension =
        q.scope === "network"
          ? Prisma.sql`"organizationId"`
          : Prisma.sql`"storeId"`;
      // One authorized scan supplies totals, daily trend and contributions.
      const aggregate = await tx.$queryRaw<
        (Sum & { day: Date | null; id: string | null; grouping: number })[]
      >(
        Prisma.sql`SELECT day,${dimension} AS id,GROUPING(day,${dimension}) AS grouping,${totalSql}
        FROM "SalesDay" WHERE ${where} GROUP BY GROUPING SETS ((),(day),(${dimension}))`,
      );
      const totals = aggregate.filter((r) => r.grouping === 3).map(summed);
      const series = aggregate
        .filter((r) => r.grouping === 1)
        .map((r) => ({ ...summed(r), day: r.day! }))
        .sort((a, b) => a.day.getTime() - b.day.getTime());
      const comparisons = aggregate
        .filter((r) => r.grouping === 2)
        .map((r) => ({ ...summed(r), id: r.id! }))
        .sort((a, b) =>
          a.netMillimes === b.netMillimes
            ? a.id.localeCompare(b.id)
            : a.netMillimes > b.netMillimes
              ? -1
              : 1,
        )
        .slice(0, 20);
      const top = await tx.$queryRaw<
        { id: string; netUnits: bigint; netMillimes: bigint }[]
      >(
        Prisma.sql`SELECT "productId" AS id,COALESCE(SUM("netUnits"),0)::bigint AS "netUnits",COALESCE(SUM("netMillimes"),0)::bigint AS "netMillimes" FROM "SalesProductDay" WHERE ${where} GROUP BY "productId" HAVING SUM("netUnits")>0 ORDER BY "netUnits" DESC,"productId" LIMIT 5`,
      );
      const storeWhere = {
        ...(q.organizationId ? { organizationId: q.organizationId } : {}),
        ...(q.storeId ? { id: q.storeId } : {}),
      };
      const stores = await tx.store.findMany({
        where: storeWhere,
        select: { id: true, name: true, organizationId: true, status: true },
      });
      const organizations = await tx.organization.findMany({
        where: q.organizationId ? { id: q.organizationId } : {},
        select: { id: true, name: true, status: true },
      });
      const products = await tx.product.findMany({
        where: { id: { in: top.map((p) => p.id) } },
        select: { id: true, name: true, imageId: true },
      });
      const operational = {
        ...(q.organizationId ? { organizationId: q.organizationId } : {}),
        ...(q.storeId ? { storeId: q.storeId } : {}),
      };
      const personal = q.scope === "personal";
      const today = new Date(localDate(new Date(), "Africa/Tunis"));
      const soon = new Date(today.getTime() + 30 * 86400000);
      const alerts = personal
        ? []
        : await tx.alert.findMany({
            where: { ...operational, active: true },
            orderBy: { createdAt: "desc" },
            take: 30,
          });
      const orders = personal
        ? 0
        : await tx.replenishmentOrder.count({
            where: {
              ...operational,
              status: { notIn: ["received", "cancelled", "closed_partial"] },
            },
          });
      const deliveries = personal
        ? 0
        : await tx.delivery.count({
            where: { ...operational, status: "dispatched" },
          });
      const claims = await tx.rewardClaim.count({
        where: {
          ...operational,
          status: "requested",
          ...(personal ? { userId: current.id } : {}),
        },
      });
      const account = personal
        ? await tx.pointsAccount.findUnique({
            where: {
              storeId_userId: { storeId: q.storeId!, userId: current.id },
            },
          })
        : null;
      const ranking = personal
        ? await monthlyRanking(tx, q.storeId!, "Africa/Tunis", current.id)
        : null;
      const recentSales = personal
        ? await tx.$queryRaw<
            {
              id: string;
              occurredAt: Date;
              netMillimes: bigint;
              netUnits: bigint;
            }[]
          >`
          SELECT s.id,s."occurredAt",c."netMillimes",c."netUnits"
          FROM "Sale" s JOIN "SalesContribution" c ON c."saleId"=s.id
          WHERE s."storeId"=${q.storeId}::uuid AND s."sellerId"=${current.id}::uuid
          ORDER BY s."occurredAt" DESC,s.id DESC LIMIT 3`
        : [];
      const expiredLots = personal
        ? 0
        : await tx.inventoryLot.count({
            where: {
              ...operational,
              expiry: { lt: today },
              sellable: { gt: 0 },
            },
          });
      const expiringLots = personal
        ? 0
        : await tx.inventoryLot.count({
            where: {
              ...operational,
              expiry: { gte: today, lte: soon },
              sellable: { gt: 0 },
            },
          });
      const lowStock = personal
        ? 0
        : await tx.alert.count({
            where: {
              ...operational,
              active: true,
              kind: { in: ["low", "zero"] },
            },
          });
      return {
        scope: q.scope,
        organizationId: q.organizationId ?? null,
        storeId: q.storeId ?? null,
        from: q.from,
        to: q.to,
        generatedAt: new Date().toISOString(),
        ...totals[0]!,
        groupCount: organizations.filter((g) => g.status === "active").length,
        storeCount: stores.filter(
          (s) =>
            s.status === "active" &&
            organizations.some(
              (g) => g.id === s.organizationId && g.status === "active",
            ),
        ).length,
        series: series.map((s) => ({
          ...s,
          day: s.day.toISOString().slice(0, 10),
        })),
        comparisons: comparisons.map((s) => ({
          ...s,
          name:
            (q.scope === "network" ? organizations : stores).find(
              (v) => v.id === s.id,
            )?.name ?? "Magasin",
        })),
        products: top.map((p) => ({
          ...p,
          name: products.find((v) => v.id === p.id)?.name ?? "Produit",
          imageId: products.find((v) => v.id === p.id)?.imageId ?? null,
        })),
        recentSales,
        ranking: ranking
          ? {
              month: ranking.month,
              rank: ranking.scores[0]?.rank ?? null,
              score: ranking.scores[0]?.score ?? 0n,
            }
          : null,
        current: {
          pendingOrders: orders,
          pendingDeliveries: deliveries,
          pendingClaims: claims,
          expiredLots,
          expiringLots,
          lowStock,
          availablePoints: account
            ? account.balance - account.reserved
            : personal
              ? 0n
              : null,
          reservedPoints: account?.reserved ?? (personal ? 0n : null),
        },
        alerts: alerts.map((a) => ({
          id: a.id,
          organizationId: a.organizationId,
          storeId: a.storeId,
          productId: a.productId,
          kind: a.kind,
          message: a.message,
          storeName: stores.find((s) => s.id === a.storeId)?.name ?? "Magasin",
        })),
      };
    });
  }
  attention(
    actor: Actor,
    q: DashboardQuery,
    kind: "low_stock" | "expired" | "deliveries" | "rewards",
    after?: string,
  ) {
    return this.scope(actor, q, async (tx, current) => {
      requireRule(
        q.scope !== "personal" || kind === "deliveries" || kind === "rewards",
        "FORBIDDEN",
        "Accès réservé au responsable.",
        403,
      );
      const where = {
        ...(q.organizationId ? { organizationId: q.organizationId } : {}),
        ...(q.storeId ? { storeId: q.storeId } : {}),
        ...(after ? { id: { gt: after } } : {}),
      };
      let rows: {
        id: string;
        organizationId: string;
        storeId: string;
        productId: string | null;
        title: string;
        detail: string;
      }[] = [];
      if (kind === "low_stock")
        rows = (
          await tx.alert.findMany({
            where: { ...where, active: true, kind: { in: ["low", "zero"] } },
            orderBy: { id: "asc" },
            take: 51,
          })
        ).map((a) => ({ ...a, title: a.message, detail: "Stock à vérifier" }));
      if (kind === "expired")
        rows = (
          await tx.inventoryLot.findMany({
            where: {
              ...where,
              expiry: { lt: new Date(localDate(new Date(), "Africa/Tunis")) },
              sellable: { gt: 0 },
            },
            orderBy: { id: "asc" },
            take: 51,
          })
        ).map((l) => ({
          ...l,
          title: `Lot ${l.batch}`,
          detail: `${l.sellable} unité(s) · expiration ${l.expiry.toISOString().slice(0, 10)}`,
        }));
      if (kind === "deliveries")
        rows = (
          await tx.delivery.findMany({
            where: { ...where, status: "dispatched" },
            orderBy: { id: "asc" },
            take: 51,
          })
        ).map((d) => ({
          ...d,
          productId: null,
          title: `Livraison ${d.id.slice(0, 8).toUpperCase()}`,
          detail: "À réceptionner",
        }));
      if (kind === "rewards")
        rows = (
          await tx.rewardClaim.findMany({
            where: {
              ...where,
              status: "requested",
              ...(q.scope === "personal" ? { userId: current.id } : {}),
            },
            orderBy: { id: "asc" },
            take: 51,
          })
        ).map((c) => ({
          ...c,
          productId: null,
          title: `Demande ${c.id.slice(0, 8).toUpperCase()}`,
          detail: "Récompense à remettre",
        }));
      const stores = await tx.store.findMany({
        where: { id: { in: rows.map((r) => r.storeId) } },
        select: { id: true, name: true },
      });
      return {
        items: rows.slice(0, 50).map((r) => ({
          id: r.id,
          organizationId: r.organizationId,
          storeId: r.storeId,
          productId: r.productId,
          kind,
          title: r.title,
          detail: r.detail,
          storeName: stores.find((s) => s.id === r.storeId)!.name,
        })),
        nextCursor: rows.length > 50 ? rows[49]!.id : null,
      };
    });
  }
  orders(
    actor: Actor,
    q: DashboardQuery,
    after?: string,
    phase?: "all" | "preparation" | "transit" | "issues" | "complete",
  ) {
    return this.scope(actor, q, async (tx) => {
      requireRule(
        q.scope !== "personal",
        "FORBIDDEN",
        "Accès réservé au responsable.",
        403,
      );
      const selectedOrders =
        phase === "transit"
          ? (
              await tx.delivery.groupBy({
                by: ["orderId"],
                where: {
                  ...(q.organizationId
                    ? { organizationId: q.organizationId }
                    : {}),
                  ...(q.storeId ? { storeId: q.storeId } : {}),
                  status: "dispatched",
                  ...(after ? { orderId: { gt: after } } : {}),
                },
                orderBy: { orderId: "asc" },
                take: 51,
              })
            ).map((d) => d.orderId)
          : phase === "issues"
            ? (
                await tx.deliveryIssue.groupBy({
                  by: ["orderId"],
                  where: {
                    ...(q.organizationId
                      ? { organizationId: q.organizationId }
                      : {}),
                    ...(q.storeId ? { storeId: q.storeId } : {}),
                    status: { not: "resolved" },
                    ...(after ? { orderId: { gt: after } } : {}),
                  },
                  orderBy: { orderId: "asc" },
                  take: 51,
                })
              ).map((i) => i.orderId)
            : undefined;
      const items = await tx.replenishmentOrder.findMany({
        where: {
          ...(phase &&
          phase !== "all" &&
          phase !== "issues" &&
          phase !== "transit"
            ? {
                status: {
                  in:
                    phase === "preparation"
                      ? ["requested", "preparing", "partial"]
                      : ["received", "cancelled", "closed_partial"],
                },
              }
            : {}),
          ...(q.organizationId ? { organizationId: q.organizationId } : {}),
          ...(q.storeId ? { storeId: q.storeId } : {}),
          ...(after || selectedOrders
            ? {
                id: {
                  ...(after ? { gt: after } : {}),
                  ...(selectedOrders ? { in: selectedOrders } : {}),
                },
              }
            : {}),
        },
        orderBy: { id: "asc" },
        take: 51,
      });
      const stores = await tx.store.findMany({
        where: { id: { in: items.map((o) => o.storeId) } },
        select: { id: true, name: true },
      });
      const groups = await tx.organization.findMany({
        where: { id: { in: items.map((o) => o.organizationId) } },
        select: { id: true, name: true },
      });
      return {
        items: items.slice(0, 50).map((o) => ({
          ...o,
          storeName: stores.find((s) => s.id === o.storeId)!.name,
          groupName: groups.find((g) => g.id === o.organizationId)!.name,
        })),
        nextCursor: items.length > 50 ? items[49]!.id : null,
      };
    });
  }
  alert(actor: Actor, organizationId: string, storeId: string, id: string) {
    return this.db.scopedSnapshot(
      actor,
      organizationId,
      storeId,
      async (tx, scope) => {
        requireRule(
          scope.permissions.includes("manage"),
          "FORBIDDEN",
          "Accès réservé au responsable.",
          403,
        );
        const alert = await tx.alert.findFirst({
          where: { id, organizationId, storeId },
        });
        requireRule(alert, "NOT_FOUND", "Alerte introuvable.", 404);
        const store = await tx.store.findUniqueOrThrow({
          where: { id: storeId },
        });
        const group = await tx.organization.findUniqueOrThrow({
          where: { id: organizationId },
        });
        const issue =
          alert.kind === "delivery_issue"
            ? await tx.deliveryIssue.findFirst({
                where: {
                  organizationId,
                  storeId,
                  deliveryId: alert.key.slice("delivery:".length),
                },
              })
            : null;
        return {
          ...alert,
          storeName: store.name,
          groupName: group.name,
          orderId: issue?.orderId ?? null,
        };
      },
    );
  }
  order(actor: Actor, organizationId: string, storeId: string, id: string) {
    return this.db.scopedSnapshot(
      actor,
      organizationId,
      storeId,
      async (tx, scope) => {
        requireRule(
          scope.permissions.includes("manage"),
          "FORBIDDEN",
          "Commande inaccessible.",
          403,
        );
        const order = await tx.replenishmentOrder.findFirst({
          where: { id, organizationId, storeId },
        });
        requireRule(order, "NOT_FOUND", "Commande introuvable.", 404);
        const store = await tx.store.findUniqueOrThrow({
          where: { id: storeId },
        });
        const group = await tx.organization.findUniqueOrThrow({
          where: { id: organizationId },
        });
        const deliveries = await tx.delivery.findMany({
          where: { orderId: id, storeId },
          orderBy: { id: "asc" },
        });
        const receipts = await tx.deliveryReceipt.findMany({
          where: {
            storeId,
            organizationId,
            deliveryId: { in: deliveries.map((d) => d.id) },
          },
          orderBy: { createdAt: "asc" },
        });
        const fulfillment =
          (await orderFulfillment(tx, organizationId, storeId, [order])).get(
            id,
          ) ?? [];
        return {
          order: { ...order, storeName: store.name, groupName: group.name },
          deliveries,
          receipts,
          fulfillment,
          issues: await tx.deliveryIssue.findMany({
            where: { organizationId, storeId, orderId: id },
            orderBy: { createdAt: "asc" },
          }),
          history: await tx.auditEntry.findMany({
            where: {
              organizationId,
              storeId,
              OR: [
                { targetId: id },
                { targetId: { in: deliveries.map((d) => d.id) } },
              ],
            },
            select: {
              id: true,
              action: true,
              actorId: true,
              createdAt: true,
              details: true,
            },
            orderBy: { createdAt: "asc" },
            take: 200,
          }),
        };
      },
    );
  }
}
