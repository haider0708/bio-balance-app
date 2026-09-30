import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { Actor } from "../operations/domain/contracts";
import {
  PricingRequests,
  currentPricesQuery,
  priceHistoryQuery,
} from "./pricing.contracts";

export type PriceLevel = "wholesale" | "store_supply" | "retail";
type Tx = Prisma.TransactionClient;
type Row = { productId: string; priceMillimes: bigint; createdAt: Date };

/** Supply and wholesale prices are readable only inside this window. */
export async function withPriceAccess<T>(tx: Tx, work: () => Promise<T>) {
  await tx.$executeRaw`SELECT set_config('app.price_access','true',true)`;
  const result = await work();
  await tx.$executeRaw`SELECT set_config('app.price_access','false',true)`;
  return result;
}

/** The latest price per product. A specific scope beats the default, whatever its age. */
export async function latestPrices(
  tx: Tx,
  level: PriceLevel,
  scope: { organizationId?: string | null; storeId?: string | null },
  productIds?: string[],
  // The price in force at that moment; omitted means now.
  at?: Date,
): Promise<Map<string, bigint>> {
  const products = productIds?.length
    ? Prisma.sql`AND "productId" IN (${Prisma.join(productIds.map((id) => Prisma.sql`${id}::uuid`))})`
    : Prisma.empty;
  const until = at ? Prisma.sql`AND "createdAt"<=${at}` : Prisma.empty;
  const match =
    level === "retail"
      ? Prisma.sql`"storeId"=${scope.storeId}::uuid`
      : level === "store_supply"
        ? Prisma.sql`("storeId" IS NULL OR "storeId"=${scope.storeId ?? null}::uuid)`
        : Prisma.sql`("organizationId" IS NULL OR "organizationId"=${scope.organizationId ?? null}::uuid)`;
  const specific =
    level === "wholesale"
      ? Prisma.sql`("organizationId" IS NULL)`
      : Prisma.sql`("storeId" IS NULL)`;
  const rows = await tx.$queryRaw<Row[]>(
    Prisma.sql`SELECT DISTINCT ON ("productId") "productId","priceMillimes","createdAt"
      FROM "PriceVersion" WHERE level=${level} AND ${match} ${products} ${until}
      ORDER BY "productId",${specific} ASC,"createdAt" DESC,id DESC`,
  );
  return new Map(rows.map((r) => [r.productId, r.priceMillimes]));
}

@Injectable()
export class PricingService {
  constructor(private readonly db: Database) {}

  /** BioBalance alone sets wholesale and store-supply prices. */
  set(actor: Actor, input: z.infer<typeof PricingRequests.Set>) {
    return this.db.authenticated(
      actor,
      async (tx, current) => {
        const payload = JSON.stringify([
          input.level,
          input.productId,
          input.organizationId ?? null,
          input.storeId ?? null,
          input.priceMillimes,
        ]);
        await tx.$executeRaw`SELECT set_config('app.price_access','true',true)`;
        const prior = await tx.priceVersion.findUnique({
          where: { operationId: input.operationId },
        });
        if (prior) {
          requireRule(
            prior.createdBy === current.id &&
              JSON.stringify([
                prior.level,
                prior.productId,
                prior.organizationId,
                prior.storeId,
                prior.priceMillimes.toString(),
              ]) === payload,
            "OPERATION_REUSED",
            "Identifiant d’opération déjà utilisé.",
            409,
          );
          return this.entry(prior, await this.authors(tx, [prior], true));
        }
        requireRule(
          await tx.product.findUnique({ where: { id: input.productId } }),
          "PRODUCT_NOT_FOUND",
          "Produit introuvable.",
          404,
        );
        if (input.level === "wholesale") {
          requireRule(
            !input.storeId,
            "VALIDATION",
            "Un prix de gros se définit par grossiste, pas par magasin.",
          );
          if (input.organizationId)
            requireRule(
              (
                await tx.organization.findUnique({
                  where: { id: input.organizationId },
                })
              )?.kind === "wholesale",
              "VALIDATION",
              "Ce prix de gros vise un grossiste existant.",
            );
        } else {
          requireRule(
            !!input.organizationId === !!input.storeId,
            "VALIDATION",
            "Indiquez le magasin de l’exception, ou aucun pour le prix par défaut.",
          );
          if (input.storeId) {
            const store = await tx.store.findFirst({
              where: {
                id: input.storeId,
                organizationId: input.organizationId,
              },
            });
            requireRule(store, "NOT_FOUND", "Magasin introuvable.", 404);
            requireRule(
              (
                await tx.organization.findUnique({
                  where: { id: store.organizationId },
                })
              )?.kind === "retail",
              "VALIDATION",
              "Un dépôt de grossiste n’a pas de prix d’approvisionnement.",
            );
          }
        }
        const scope =
          input.level === "store_supply"
            ? { storeId: input.storeId ?? null }
            : { organizationId: input.organizationId ?? null };
        const existing = await latestPrices(tx, input.level, scope, [
          input.productId,
        ]);
        requireRule(
          existing.get(input.productId) !== BigInt(input.priceMillimes),
          "PRICE_UNCHANGED",
          "Ce prix est déjà en vigueur.",
          409,
        );
        const row = await tx.priceVersion.create({
          data: {
            id: crypto.randomUUID(),
            level: input.level,
            productId: input.productId,
            organizationId: input.organizationId ?? null,
            storeId: input.storeId ?? null,
            priceMillimes: BigInt(input.priceMillimes),
            reason: input.reason ?? null,
            operationId: input.operationId,
            createdBy: current.id,
          },
        });
        await tx.auditEntry.create({
          data: {
            organizationId: input.organizationId ?? null,
            storeId: input.storeId ?? null,
            actorId: current.id,
            action: "price.set",
            targetId: row.id,
            operationId: input.operationId,
            details: json({
              level: input.level,
              productId: input.productId,
              priceMillimes: input.priceMillimes,
              previous: existing.get(input.productId)?.toString() ?? null,
              reason: input.reason ?? null,
            }),
          },
        });
        return this.entry(row, await this.authors(tx, [row], true));
      },
      true,
    );
  }

  /** Who the caller is for a store: decides which price levels are visible. */
  private async viewer(
    tx: Tx,
    current: Actor,
    organizationId: string,
    storeId: string,
  ) {
    const store = await tx.store.findFirst({
      where: { id: storeId, organizationId },
    });
    requireRule(store, "NOT_FOUND", "Magasin introuvable.", 404);
    const group = await tx.organization.findUniqueOrThrow({
      where: { id: organizationId },
    });
    const owner = await tx.organizationMembership.findUnique({
      where: { organizationId_userId: { organizationId, userId: current.id } },
    });
    const member = await tx.membership.findUnique({
      where: { storeId_userId: { storeId, userId: current.id } },
    });
    const admin = current.platformAdmin;
    const responsible = !!owner?.active;
    const manager =
      admin ||
      responsible ||
      (!!member?.active && member.permissions.includes("manage"));
    requireRule(
      admin || responsible || member?.active,
      "STORE_ACCESS_REVOKED",
      "Magasin inaccessible.",
      403,
    );
    return {
      admin,
      wholesale: group.kind === "wholesale",
      // A retail store's manager reads retail (own) and store-supply prices.
      retail: !(group.kind === "wholesale"),
      supply: manager,
      wholesalePrice: group.kind === "wholesale" && (admin || responsible),
    };
  }

  /** Current prices, limited to the levels this caller may see. */
  current(actor: Actor, raw: unknown) {
    const q = currentPricesQuery.parse(raw);
    return this.db.authenticated(actor, async (tx, current) => {
      const v = await this.viewer(tx, current, q.organizationId, q.storeId);
      await tx.$executeRaw`SELECT set_config('app.price_access','true',true)`;
      const retail = v.retail
        ? await latestPrices(tx, "retail", { storeId: q.storeId })
        : new Map<string, bigint>();
      const supply = v.supply
        ? await latestPrices(tx, "store_supply", { storeId: q.storeId })
        : v.wholesalePrice
          ? await latestPrices(tx, "store_supply", {})
          : new Map<string, bigint>();
      const wholesale = v.wholesalePrice
        ? await latestPrices(tx, "wholesale", {
            organizationId: q.organizationId,
          })
        : new Map<string, bigint>();
      const ids = new Set([
        ...retail.keys(),
        ...supply.keys(),
        ...wholesale.keys(),
      ]);
      return {
        items: [...ids].sort().map((productId) => ({
          productId,
          retailMillimes: retail.get(productId) ?? null,
          supplyMillimes: supply.get(productId) ?? null,
          wholesaleMillimes: wholesale.get(productId) ?? null,
        })),
      };
    });
  }

  /** Price history, limited to the levels and scopes this caller may see. */
  history(actor: Actor, raw: unknown) {
    const q = priceHistoryQuery.parse(raw);
    return this.db.authenticated(actor, async (tx, current) => {
      const where: Prisma.PriceVersionWhereInput[] = [];
      let admin = current.platformAdmin;
      if (q.storeId || q.organizationId) {
        requireRule(
          q.storeId && q.organizationId,
          "VALIDATION",
          "Indiquez le groupe et le magasin.",
        );
        const v = await this.viewer(tx, current, q.organizationId!, q.storeId!);
        // A seller reads the current retail price only, never the history.
        requireRule(
          v.supply || v.wholesalePrice,
          "FORBIDDEN",
          "Historique réservé au responsable.",
          403,
        );
        admin = v.admin;
        if (v.retail) {
          where.push({ level: "retail", storeId: q.storeId });
        }
        if (v.supply) {
          where.push({
            level: "store_supply",
            OR: [{ storeId: null }, { storeId: q.storeId }],
          });
        } else if (v.wholesalePrice) {
          where.push({ level: "store_supply", storeId: null });
        }
        if (v.wholesalePrice) {
          where.push({
            level: "wholesale",
            OR: [
              { organizationId: null },
              { organizationId: q.organizationId },
            ],
          });
        }
      } else {
        requireRule(
          admin,
          "FORBIDDEN",
          "Indiquez le groupe et le magasin.",
          403,
        );
        for (const level of ["wholesale", "store_supply", "retail"] as const) {
          where.push({ level });
        }
      }
      await tx.$executeRaw`SELECT set_config('app.price_access','true',true)`;
      const rows = await tx.priceVersion.findMany({
        where: {
          productId: q.productId,
          ...(q.level ? { level: q.level } : {}),
          OR: where.length
            ? where
            : [{ id: "00000000-0000-0000-0000-000000000000" }],
        },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: 200,
      });
      const authors = await this.authors(tx, rows, admin);
      return { items: rows.map((row) => this.entry(row, authors)) };
    });
  }

  /** One lookup for every author, instead of one per entry. */
  private async authors(
    tx: Tx,
    rows: { createdBy: string | null }[],
    show: boolean,
  ) {
    const ids = show
      ? [...new Set(rows.flatMap((r) => (r.createdBy ? [r.createdBy] : [])))]
      : [];
    const users = ids.length
      ? await tx.user.findMany({
          where: { id: { in: ids } },
          select: { id: true, name: true },
        })
      : [];
    return new Map(users.map((u) => [u.id, u.name]));
  }

  private entry(
    row: {
      id: string;
      level: string;
      productId: string;
      organizationId: string | null;
      storeId: string | null;
      priceMillimes: bigint;
      reason: string | null;
      createdBy: string | null;
      seeded: boolean;
      createdAt: Date;
    },
    authors: Map<string, string>,
  ) {
    return {
      id: row.id,
      level: row.level,
      productId: row.productId,
      organizationId: row.organizationId,
      storeId: row.storeId,
      priceMillimes: row.priceMillimes,
      reason: row.reason,
      author: row.createdBy ? (authors.get(row.createdBy) ?? null) : null,
      seeded: row.seeded,
      createdAt: row.createdAt,
    };
  }
}
