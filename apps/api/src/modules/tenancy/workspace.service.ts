import { SnapshotPages } from "./infrastructure/snapshot-pages";
import { decodeHistoryCursor } from "../../shared/domain/pagination";
import { StoreReadQueries } from "./infrastructure/store-read-queries";
import {
  orderFulfillment,
  outstandingSupply,
} from "../operations/infrastructure/order-fulfillment-query";
import { onboardingProgress } from "./onboarding";
import { requireImage } from "../training/media-authorization";
import { Injectable } from "@nestjs/common";
import { Database, json } from "../../shared/infrastructure/database";
import { Actor, Scope } from "../operations/domain/contracts";
import { Prisma } from "@prisma/client";
import { requireRule } from "../../shared/domain/errors";
import { localDate } from "../../shared/domain/money";
import { PrismaLedger } from "../operations/infrastructure/prisma-ledger";
@Injectable()
export class WorkspaceService {
  constructor(private readonly db: Database) {}
  async fulfillment(actor: Actor, org: string, store: string, orderId: string) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      requireRule(
        scope.permissions.includes("manage"),
        "FORBIDDEN",
        "Action réservée au responsable.",
        403,
      );
      const order = await tx.replenishmentOrder.findFirst({
        where: { id: orderId, storeId: store, organizationId: org },
      });
      requireRule(order, "NOT_FOUND", "Commande introuvable.", 404);
      const result = await orderFulfillment(tx, org, store, [order]);
      return {
        orderId: order.id,
        version: order.version,
        status: order.status,
        lines: result.get(order.id)!,
      };
    });
  }
  async organizations(actor: Actor) {
    return this.db.authenticated(actor, async (tx, actor) => {
      if (actor.platformAdmin)
        return tx.organization.findMany({
          orderBy: { name: "asc" },
          take: 500,
        });
      const memberships = await tx.organizationMembership.findMany({
        where: { userId: actor.id, active: true },
      });
      return tx.organization.findMany({
        where: { id: { in: memberships.map((m) => m.organizationId) } },
        orderBy: { name: "asc" },
        take: 500,
      });
    });
  }
  stores(actor: Actor) {
    return this.db.authenticated(actor, (tx, current) =>
      this.storesInTransaction(tx, current),
    );
  }
  async storesInTransaction(tx: Prisma.TransactionClient, actor: Actor) {
    const owners = await tx.organizationMembership.findMany({
      where: { userId: actor.id, active: true },
    });
    const members = await tx.membership.findMany({
      where: { userId: actor.id, active: true },
    });
    const stores = await tx.store.findMany({
      where: actor.platformAdmin
        ? {}
        : {
            OR: [
              { organizationId: { in: owners.map((m) => m.organizationId) } },
              { id: { in: members.map((m) => m.storeId) } },
            ],
          },
      orderBy: { name: "asc" },
      take: 1000,
    });
    const organizations = await tx.organization.findMany({
      where: { id: { in: [...new Set(stores.map((s) => s.organizationId))] } },
    });
    return stores.map((s) => ({
      ...s,
      organizationName: organizations.find((o) => o.id === s.organizationId)
        ?.name,
      permissions:
        actor.platformAdmin ||
        owners.some((o) => o.organizationId === s.organizationId)
          ? ["manage", "sell", "receive"]
          : members.find((m) => m.storeId === s.id)!.permissions,
    }));
  }
  async createStore(
    actor: Actor,
    input: {
      organizationId: string;
      name: string;
      address: string;
      city: string;
      phone?: string;
    },
  ) {
    return this.db.authenticated(actor, async (tx, actor) => {
      const owner = await tx.organizationMembership.findUnique({
        where: {
          organizationId_userId: {
            organizationId: input.organizationId,
            userId: actor.id,
          },
        },
      });
      requireRule(
        actor.platformAdmin || owner?.active,
        "FORBIDDEN",
        "Vous ne pouvez pas créer un magasin dans cette organisation.",
        403,
      );
      const store = await tx.store.create({ data: input });
      await tx.membership.create({
        data: {
          organizationId: store.organizationId,
          storeId: store.id,
          userId: actor.id,
          permissions: ["manage", "sell", "receive"],
        },
      });
      await tx.auditEntry.create({
        data: {
          organizationId: store.organizationId,
          storeId: store.id,
          actorId: actor.id,
          action: "store.create",
          targetId: store.id,
          details: json(input),
        },
      });
      return store;
    });
  }
  private manager(scope: Scope) {
    requireRule(
      scope.actor.platformAdmin || scope.permissions.includes("manage"),
      "FORBIDDEN",
      "Accès réservé au responsable.",
      403,
    );
  }
  async mutate<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    action: string,
    targetId: string,
    work: (tx: Prisma.TransactionClient, scope: Scope) => Promise<T>,
  ) {
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      this.manager(scope);
      await tx.storeCursor.upsert({
        where: { storeId },
        create: { storeId, organizationId },
        update: {},
      });
      await tx.$queryRaw`SELECT "storeId" FROM "StoreCursor" WHERE "storeId"=${storeId}::uuid FOR UPDATE`;
      const result = await work(tx, scope);
      await tx.auditEntry.create({
        data: {
          organizationId,
          storeId,
          actorId: actor.id,
          action,
          targetId,
          details: json(result),
        },
      });
      const cursor = await tx.storeCursor.update({
        where: { storeId },
        data: { value: { increment: 1 } },
      });
      await tx.change.create({
        data: {
          storeId,
          organizationId,
          cursor: cursor.value,
          entity: action,
          entityId: targetId,
        },
      });
      return result;
    });
  }
  configureProduct(
    actor: Actor,
    org: string,
    store: string,
    productId: string,
    input: {
      priceMillimes: string;
      threshold: number;
      pointsPerUnit: number;
      zeroPointsConfirmed?: boolean;
      expectedVersion?: number;
    },
  ) {
    return this.mutate(
      actor,
      org,
      store,
      "product.configure",
      productId,
      async (tx, scope) => {
        const old = await tx.storeProduct.findUnique({
          where: { storeId_productId: { storeId: store, productId } },
        });
        requireRule(
          !old || old.version === input.expectedVersion,
          "VERSION_CONFLICT",
          "La configuration a changé.",
          409,
        );
        requireRule(
          input.pointsPerUnit > 0 || input.zeroPointsConfirmed === true,
          "ZERO_POINTS_CONFIRMATION",
          "Confirmez que ce produit ne rapporte aucun point.",
        );
        const data = {
          zeroPointsConfirmed:
            input.pointsPerUnit === 0 && input.zeroPointsConfirmed === true,
          priceMillimes: BigInt(input.priceMillimes),
          threshold: input.threshold,
          pointsPerUnit: input.pointsPerUnit,
          pointsConfigured: true,
        };
        const result = await tx.storeProduct.upsert({
          where: { storeId_productId: { storeId: store, productId } },
          create: { organizationId: org, storeId: store, productId, ...data },
          update: { ...data, version: { increment: 1 } },
        });
        await new PrismaLedger(tx, scope).alerts([productId]);
        return result;
      },
    );
  }
  setMember(
    actor: Actor,
    org: string,
    store: string,
    userId: string,
    input: { active: boolean; permissions: string[] },
  ) {
    return this.mutate(
      actor,
      org,
      store,
      "membership.update",
      userId,
      async (tx) => {
        requireRule(
          userId !== actor.id,
          "SELF_ACCESS_CHANGE",
          "Un autre responsable doit modifier votre propre accès.",
        );
        return tx.membership.update({
          where: { storeId_userId: { storeId: store, userId } },
          data: input,
        });
      },
    );
  }
  updateStore(
    actor: Actor,
    org: string,
    store: string,
    input: {
      name: string;
      address: string;
      city: string;
      phone?: string | null;
      imageId?: string | null;
      expectedVersion: number;
    },
  ) {
    return this.mutate(actor, org, store, "store.update", store, async (tx) => {
      const old = await tx.store.findUniqueOrThrow({ where: { id: store } });
      requireRule(
        old.version === input.expectedVersion,
        "VERSION_CONFLICT",
        "Le magasin a été modifié.",
        409,
      );
      await requireImage(tx, input.imageId, "store", store);
      const { expectedVersion, ...data } = input;
      return tx.store.update({
        where: { id: store },
        data: { ...data, version: { increment: 1 } },
      });
    });
  }
  onboarding(
    actor: Actor,
    org: string,
    store: string,
    input: {
      step?: number;
      workingAlone?: boolean;
      noOpeningStock?: boolean;
      expectedVersion?: number;
    },
  ) {
    return this.mutate(
      actor,
      org,
      store,
      "onboarding.update",
      store,
      async (tx) => {
        const old = await tx.store.findUniqueOrThrow({ where: { id: store } });
        const changes =
          input.workingAlone !== undefined ||
          input.noOpeningStock !== undefined;
        requireRule(
          !changes || old.version === input.expectedVersion,
          "VERSION_CONFLICT",
          "Le magasin a été modifié.",
          409,
        );
        await tx.store.update({
          where: { id: store },
          data: {
            workingAlone: input.workingAlone,
            noOpeningStock: input.noOpeningStock,
            version: { increment: 1 },
          },
        });
        const progress = await onboardingProgress(tx, store);
        requireRule(
          input.step !== 5 || progress.complete,
          "SETUP_INCOMPLETE",
          "Complétez les étapes ou confirmez vos choix avant de terminer.",
        );
        const step = progress.complete
          ? 5
          : !progress.profile
            ? 1
            : !progress.team
              ? 2
              : !progress.stock
                ? 3
                : 4;
        const updated = await tx.store.update({
          where: { id: store },
          data: { onboardingStep: step },
        });
        return { store: updated, onboarding: progress };
      },
    );
  }
  reward(
    actor: Actor,
    org: string,
    store: string,
    input: {
      id?: string;
      title: string;
      description: string;
      cost: number;
      productId?: string | null;
      imageId?: string | null;
      quantity: number;
      active: boolean;
      expectedVersion?: number;
    },
  ) {
    return this.mutate(
      actor,
      org,
      store,
      "reward.configure",
      input.id ?? store,
      async (tx) => {
        const { expectedVersion, id, ...data } = input;
        await requireImage(tx, input.imageId, "reward", store);
        if (input.productId)
          requireRule(
            await tx.product.findUnique({ where: { id: input.productId } }),
            "PRODUCT_NOT_FOUND",
            "Produit introuvable.",
          );
        if (id) {
          const old = await tx.reward.findFirst({
            where: { id, storeId: store },
          });
          requireRule(
            old && old.version === expectedVersion,
            "VERSION_CONFLICT",
            "La récompense a changé.",
            409,
          );
          return tx.reward.update({
            where: { id },
            data: { ...data, version: { increment: 1 } },
          });
        }
        return tx.reward.create({
          data: { organizationId: org, storeId: store, ...data },
        });
      },
    );
  }
  async snapshot(
    actor: Actor,
    org: string,
    store: string,
    since?: { cursor: string; catalogRevision: string },
    protocol = 2,
    acknowledgmentIds: string[] = [],
  ) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      const manage =
        scope.permissions.includes("manage") || scope.actor.platformAdmin;
      const currentCursor = await tx.storeCursor.findUnique({
        where: { storeId: store },
      });
      const catalog = await tx.product.aggregate({
        _count: true,
        _sum: { version: true },
      });
      const catalogRevision = `${catalog._count}:${catalog._sum.version ?? 0}`;
      const changes = since
        ? await tx.change.findMany({
            where: { storeId: store, cursor: { gt: BigInt(since.cursor) } },
            orderBy: { cursor: "asc" },
            take: 201,
          })
        : [];
      // A bounded delta merges changed lots/configuration into the existing
      // cache. Large backlogs or catalog changes receive a fresh snapshot.
      const delta =
        !!since &&
        BigInt(since.cursor) <= (currentCursor?.value ?? 0n) &&
        changes.length <= 200 &&
        since.catalogRevision === catalogRevision;
      const accepted = acknowledgmentIds.length
        ? await tx.processedOperation.findMany({
            where: {
              storeId: store,
              actorId: actor.id,
              id: { in: acknowledgmentIds },
            },
            select: { id: true, result: true },
          })
        : [];
      const movements =
        delta && (changes.length > 0 || accepted.length > 0)
          ? await tx.stockMovement.findMany({
              where: {
                storeId: store,
                operationId: {
                  in: [
                    ...changes.map((c) => c.id),
                    ...accepted.map((a) => a.id),
                  ],
                },
              },
              select: { lotId: true },
              distinct: ["lotId"],
              take: 1501,
            })
          : [];
      const useDelta = delta && movements.length <= 1500;
      const changedLots = movements.map((m) => m.lotId);
      const changedProducts = changes
        .filter((c) => c.entity === "product.configure")
        .map((c) => c.entityId);
      const config = await (useDelta && changedProducts.length === 0
        ? Promise.resolve([])
        : tx.storeProduct.findMany({
            where: {
              storeId: store,
              ...(useDelta ? { productId: { in: changedProducts } } : {}),
            },
            orderBy: { id: "asc" },
            take: 1000,
          }));
      const lots = await (useDelta && changedLots.length === 0
        ? Promise.resolve([])
        : tx.inventoryLot.findMany({
            where: {
              storeId: store,
              ...(useDelta ? { id: { in: changedLots } } : {}),
            },
            orderBy: { id: "asc" },
            take: useDelta ? 1500 : 500,
          }));
      const sales = await new StoreReadQueries(tx, scope).recentSales();
      const alerts = await (manage
        ? tx.alert.findMany({
            where: { storeId: store, active: true },
            orderBy: { createdAt: "desc" },
            take: 200,
          })
        : Promise.resolve([]));
      const collections = await new StoreReadQueries(
        tx,
        scope,
      ).snapshotCollections();
      const memberships = await (manage
        ? tx.membership.findMany({ where: { storeId: store }, take: 200 })
        : Promise.resolve([]));
      const storeData = await tx.store.findUniqueOrThrow({
        where: { id: store },
      });
      const { points, rewards, claims, orders, deliveries } = collections;
      const cursor = currentCursor;
      const fulfillment = await orderFulfillment(tx, org, store, orders);
      const supply = await outstandingSupply(tx, org, store);
      const onboarding = manage ? await onboardingProgress(tx, store) : null;
      const users = memberships.length
        ? await tx.user.findMany({
            where: { id: { in: memberships.map((m) => m.userId) } },
            select: { id: true, name: true, email: true },
          })
        : [];
      const invitations = manage
        ? await tx.accessToken.findMany({
            where: {
              storeId: store,
              purpose: "invite",
              usedAt: null,
              expiresAt: { gt: new Date() },
            },
            select: { id: true, email: true, expiresAt: true },
            take: 200,
          })
        : [];
      const summaryRows = await tx.$queryRaw<
        { count: bigint; total: bigint }[]
      >`SELECT COUNT(*)::bigint AS count,COALESCE(SUM("totalMillimes"),0)::bigint AS total FROM "Sale" WHERE "storeId"=${store}::uuid AND (${manage} OR "sellerId"=${actor.id}::uuid) AND "occurredAt">=((date_trunc('day', now() AT TIME ZONE ${scope.timezone}) AT TIME ZONE ${scope.timezone}) AT TIME ZONE 'UTC')`;
      const products = useDelta
        ? []
        : await tx.product.findMany({
            orderBy: { id: "asc" },
            take: 1000,
          });
      const acknowledgedSaleIds = accepted.flatMap((a) => {
        const result = a.result as unknown as { data?: { id?: string } };
        return result.data?.id ? [result.data.id] : [];
      });
      const acknowledgedSales = acknowledgedSaleIds.length
        ? await tx.sale.findMany({
            where: {
              storeId: store,
              id: { in: acknowledgedSaleIds },
              ...(!manage ? { sellerId: actor.id } : {}),
            },
          })
        : [];
      for (const sale of acknowledgedSales) {
        if (!sales.some((s) => s.id === sale.id)) sales.push(sale);
      }
      const snapshotPages: Record<string, string | null> = {};
      const expiresAt = new Date(Date.now() + 5 * 60_000);
      if (protocol >= 3) {
        await tx.syncSnapshotPage.deleteMany({
          where: {
            storeId: store,
            actorId: actor.id,
            expiresAt: { lte: new Date() },
          },
        });
      }
      const pages = new SnapshotPages(
        tx,
        scope,
        (cursor?.value ?? 0n).toString(),
        expiresAt,
      );
      if (protocol >= 3 && !useDelta) {
        for (const [resource, initial, limit] of [
          ["lots", lots, 500],
          ["products", products, 1000],
          ["config", config, 1000],
        ] as const) {
          snapshotPages[resource] = await pages.materialize(
            resource,
            initial.length === limit ? initial.at(-1)?.id : undefined,
            async (after) => {
              const options = { orderBy: { id: "asc" as const }, take: 200 };
              if (resource === "lots")
                return tx.inventoryLot.findMany({
                  where: { storeId: store, id: { gt: after } },
                  ...options,
                });
              if (resource === "config")
                return tx.storeProduct.findMany({
                  where: { storeId: store, id: { gt: after } },
                  ...options,
                });
              return tx.product.findMany({
                where: { id: { gt: after } },
                ...options,
              });
            },
          );
        }
      }
      // Page operational lists even in a delta; no unresolved work is truncated.
      if (protocol >= 3) {
        const queries = new StoreReadQueries(tx, scope);
        for (const [resource, initial] of [
          ["rewards", rewards],
          ["claims", claims],
          ["orders", orders],
          ["deliveries", deliveries],
        ] as const) {
          snapshotPages[resource] = await pages.materialize(
            resource,
            initial.length === 200 ? initial.at(-1)?.id : undefined,
            async (after) => {
              const items = await queries.operationalPage(resource, after);
              if (resource !== "orders") return items;
              const fulfillment = await orderFulfillment(
                tx,
                org,
                store,
                items as import("@prisma/client").ReplenishmentOrder[],
              );
              return items.map((item) => ({
                ...item,
                fulfillment: fulfillment.get(item.id),
              }));
            },
          );
        }
      }
      return {
        syncProtocol: protocol >= 3 ? 3 : 2,
        snapshotPages,
        snapshotExpiresAt: expiresAt.toISOString(),
        appliedOperationIds: accepted.map((a) => a.id),
        catalogRevision,
        mode: useDelta ? "delta" : "snapshot",
        mergeResources: useDelta ? ["lots", "config", "products"] : [],
        // Replacing authorized collections also removes disabled memberships,
        // archived rewards and received deliveries from their active lists.
        summary: {
          saleCount: summaryRows[0]?.count ?? 0n,
          totalMillimes: summaryRows[0]?.total ?? 0n,
        },
        store: storeData,
        onboarding,
        permissions: scope.permissions,
        products,
        config,
        lots,
        sales,
        alerts: manage ? alerts : [],
        points: points ?? { balance: 0n, reserved: 0n },
        rewards,
        claims,
        orders: orders.map((order) => ({
          ...order,
          fulfillment: fulfillment.get(order.id),
        })),
        outstandingSupply: supply,
        deliveries,
        team: memberships.map((m) => ({
          ...m,
          ...users.find((u) => u.id === m.userId),
          membershipId: m.id,
        })),
        invitations,
        cursor: (cursor?.value ?? 0n).toString(),
        serverTime: new Date().toISOString(),
        pagination: {
          lots: !useDelta && lots.length === 500 ? lots.at(-1)!.id : null,
          products: products.length === 1000 ? products.at(-1)!.id : null,
          config:
            !useDelta && config.length === 1000 ? config.at(-1)!.id : null,
        },
      };
    });
  }
  snapshotPage(actor: Actor, org: string, store: string, pageId: string) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      const page = await tx.syncSnapshotPage.findFirst({
        where: {
          id: pageId,
          organizationId: org,
          storeId: store,
          actorId: actor.id,
        },
      });
      requireRule(
        page &&
          page.expiresAt > new Date() &&
          page.permissions === JSON.stringify([...scope.permissions].sort()),
        "SNAPSHOT_EXPIRED",
        "La copie du magasin a expiré. Recommencez la synchronisation.",
        410,
      );
      return page.payload;
    });
  }
  async list(
    actor: Actor,
    org: string,
    store: string,
    resource: string,
    after?: string,
  ) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      const base = { storeId: store, ...(after ? { id: { gt: after } } : {}) };
      const options = { orderBy: { id: "asc" as const }, take: 200 };
      if (resource === "lots")
        return new StoreReadQueries(tx, scope).lots(after);
      if (resource === "config")
        return tx.storeProduct.findMany({ where: base, ...options });
      if (resource === "products")
        return tx.product.findMany({
          where: after ? { id: { gt: after } } : {},
          ...options,
        });
      if (resource === "sales")
        return tx.sale.findMany({
          where: {
            ...base,
            ...(scope.permissions.includes("manage") ||
            scope.actor.platformAdmin
              ? {}
              : { sellerId: actor.id }),
          },
          ...options,
        });
      if (resource === "points")
        return tx.pointsEntry.findMany({
          where: { ...base, userId: actor.id },
          ...options,
        });
      if (resource === "audit") {
        this.manager(scope);
        return tx.auditEntry.findMany({ where: base, ...options });
      }
      requireRule(false, "RESOURCE_NOT_FOUND", "Ressource introuvable.", 404);
    });
  }
  history(
    actor: Actor,
    org: string,
    store: string,
    resource: string,
    productId?: string,
    before?: string,
  ) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      if (resource === "movements" || resource === "audit") this.manager(scope);
      let cursor: { id: string; date: Date } | undefined;
      if (before) {
        cursor = decodeHistoryCursor(before);
      }
      const dateKey = resource === "sales" ? "occurredAt" : "createdAt";
      const options = {
        orderBy: [{ [dateKey]: "desc" as const }, { id: "desc" as const }],
        take: 100,
      };
      const base = {
        storeId: store,
        ...(cursor
          ? {
              OR: [
                { [dateKey]: { lt: cursor.date } },
                { [dateKey]: cursor.date, id: { lt: cursor.id } },
              ],
            }
          : {}),
      };
      let items: Record<string, any>[];
      if (resource === "sales")
        items = await new StoreReadQueries(tx, scope).recentSales(
          cursor,
          productId,
        );
      else if (resource === "points")
        items = await tx.pointsEntry.findMany({
          ...options,
          where: { ...base, userId: actor.id },
        });
      else if (resource === "movements") {
        const lots = productId
          ? await tx.inventoryLot.findMany({
              where: { storeId: store, productId },
              select: { id: true },
            })
          : null;
        items = await tx.stockMovement.findMany({
          ...options,
          where: {
            ...base,
            ...(lots ? { lotId: { in: lots.map((l) => l.id) } } : {}),
          },
        });
      } else if (resource === "audit")
        items = await tx.auditEntry.findMany({ ...options, where: base });
      else {
        requireRule(
          false,
          "RESOURCE_NOT_FOUND",
          "Historique introuvable.",
          404,
        );
      }
      const last = items.at(-1);
      const people = await tx.user.findMany({
        where: {
          id: {
            in: [
              ...new Set(
                items
                  .map((r) => r.actorId ?? r.sellerId ?? r.userId)
                  .filter(Boolean),
              ),
            ],
          },
        },
        select: { id: true, name: true },
      });
      return {
        items,
        people,
        nextCursor:
          items.length === 100 && last
            ? Buffer.from(
                JSON.stringify({ id: last.id, date: last[dateKey] }),
              ).toString("base64url")
            : null,
      };
    });
  }
  saleDetails(actor: Actor, org: string, store: string, saleId: string) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      const sale = await tx.sale.findFirst({
        where: { id: saleId, storeId: store },
      });
      requireRule(sale, "NOT_FOUND", "Vente introuvable.", 404);
      requireRule(
        sale.sellerId === actor.id ||
          scope.actor.platformAdmin ||
          scope.permissions.includes("manage"),
        "FORBIDDEN",
        "Accès refusé.",
        403,
      );
      const revisions = await tx.saleRevision.findMany({
        where: { saleId },
        orderBy: { version: "asc" },
        take: 500,
      });
      const people = await tx.user.findMany({
        where: {
          id: { in: [sale.sellerId, ...revisions.map((r) => r.editorId)] },
        },
        select: { id: true, name: true },
      });
      return { sale, revisions, people };
    });
  }
  changes(actor: Actor, org: string, store: string, after: string) {
    return this.db.scoped(actor, org, store, async (tx) => {
      const changes = await tx.change.findMany({
        where: { storeId: store, cursor: { gt: BigInt(after) } },
        orderBy: { cursor: "asc" },
        take: 200,
      });
      return {
        changes,
        cursor: (changes.at(-1)?.cursor ?? BigInt(after)).toString(),
        hasMore: changes.length === 200,
      };
    });
  }
  ranking(actor: Actor, org: string, store: string) {
    return this.db.scoped(actor, org, store, async (tx, scope) => {
      const month = localDate(new Date(), scope.timezone).slice(0, 7);
      const scores = await tx.$queryRaw<
        { userId: string; name: string; score: bigint; rank: bigint }[]
      >`SELECT p."userId",u.name,SUM(p.amount)::bigint AS score,
          DENSE_RANK() OVER(ORDER BY SUM(p.amount) DESC)::bigint AS rank
        FROM "PointsEntry" p JOIN "User" u ON u.id=p."userId"
        WHERE p."storeId"=${store}::uuid AND p.kind='earned'
          AND p."createdAt">=(${month + "-01"}::timestamp AT TIME ZONE ${scope.timezone} AT TIME ZONE 'UTC')
          AND p."createdAt"<((${month + "-01"}::timestamp + interval '1 month') AT TIME ZONE ${scope.timezone} AT TIME ZONE 'UTC')
        GROUP BY p."userId",u.name ORDER BY score DESC,u.name LIMIT 200`;
      return { month, scores };
    });
  }
}
