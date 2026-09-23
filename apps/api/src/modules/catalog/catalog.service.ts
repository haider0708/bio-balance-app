import { requireImage } from "../training/media-authorization";
import { Injectable } from "@nestjs/common";
import { Database, json } from "../../shared/infrastructure/database";
import { Actor } from "../operations/domain/contracts";
import { requireRule } from "../../shared/domain/errors";
export interface ProductInput {
  id?: string;
  reference: string;
  name: string;
  barcode?: string;
  imageId?: string | null;
  description: string;
  active: boolean;
  expectedVersion?: number;
  category?: string;
  range?: string;
  packageSize?: string;
  instructions?: string;
  ingredients?: string;
  precautions?: string;
  referencePriceMillimes?: string | null;
  priceStatus?: "missing" | "verified" | "sample";
  sourceUrls?: string[];
}
@Injectable()
export class CatalogService {
  constructor(private readonly db: Database) {}
  private validatePrice(price: bigint | null, status: string) {
    requireRule(
      (price === null) === (status === "missing"),
      "INVALID_REFERENCE_PRICE",
      "Indiquez le prix de référence et son origine, ou choisissez Prix manquant.",
    );
  }
  list(actor: Actor, after?: string) {
    return this.db.authenticated(actor, async (tx, current) => {
      const items = await tx.product.findMany({
        where: {
          ...(after ? { id: { gt: after } } : {}),
          ...(!current.platformAdmin ? { active: true } : {}),
        },
        orderBy: { id: "asc" },
        take: 101,
      });
      return {
        items: items.slice(0, 100),
        nextCursor: items.length > 100 ? items[99]!.id : null,
      };
    });
  }
  async save(actor: Actor, input: ProductInput) {
    requireRule(
      actor.platformAdmin,
      "FORBIDDEN",
      "Accès réservé à BioBalance.",
      403,
    );
    return this.db.authenticated(
      actor,
      async (tx, actor) => {
        await requireImage(tx, input.imageId, "catalog");
        const { id, expectedVersion, referencePriceMillimes, ...fields } =
          input;
        const data = {
          ...fields,
          ...(referencePriceMillimes !== undefined
            ? {
                referencePriceMillimes:
                  referencePriceMillimes === null
                    ? null
                    : BigInt(referencePriceMillimes),
              }
            : {}),
        };
        const old = id ? await tx.product.findUnique({ where: { id } }) : null;
        requireRule(
          !id || old?.version === expectedVersion,
          "VERSION_CONFLICT",
          "Le produit a changé.",
          409,
        );
        this.validatePrice(
          referencePriceMillimes === undefined
            ? (old?.referencePriceMillimes ?? null)
            : referencePriceMillimes === null
              ? null
              : BigInt(referencePriceMillimes),
          input.priceStatus ?? old?.priceStatus ?? "missing",
        );
        const product = id
          ? await tx.product.update({
              where: { id },
              data: { ...data, version: { increment: 1 } },
            })
          : await tx.product.create({ data });
        await tx.auditEntry.create({
          data: {
            actorId: actor.id,
            action: "catalog.save",
            targetId: product.id,
            details: json(product),
          },
        });
        return product;
      },
      true,
    );
  }
  async import(actor: Actor, rows: ProductInput[], commit: boolean) {
    requireRule(
      actor.platformAdmin,
      "FORBIDDEN",
      "Accès réservé à BioBalance.",
      403,
    );
    requireRule(
      new Set(rows.map((r) => r.reference)).size === rows.length,
      "DUPLICATE_REFERENCE",
      "Référence répétée dans le fichier.",
    );
    const codes = rows.filter((r) => r.barcode).map((r) => r.barcode);
    requireRule(
      new Set(codes).size === codes.length,
      "DUPLICATE_BARCODE",
      "Code-barres répété dans le fichier.",
    );
    return this.db.authenticated(
      actor,
      async (tx, actor) => {
        const existing = await tx.product.findMany({
          where: {
            OR: [
              { reference: { in: rows.map((r) => r.reference) } },
              { barcode: { in: codes as string[] } },
            ],
          },
        });
        requireRule(
          existing.length === 0,
          "CATALOG_CONFLICT",
          "Des références ou codes-barres existent déjà. Modifiez ces produits individuellement.",
          409,
        );
        for (const row of rows)
          this.validatePrice(
            row.referencePriceMillimes == null
              ? null
              : BigInt(row.referencePriceMillimes),
            row.priceStatus ?? "missing",
          );
        if (!commit) return { valid: true, count: rows.length, rows };
        for (const row of rows) await requireImage(tx, row.imageId, "catalog");
        const result = await tx.product.createMany({
          data: rows.map(
            ({ id, expectedVersion, referencePriceMillimes, ...row }) => ({
              ...row,
              ...(referencePriceMillimes !== undefined
                ? {
                    referencePriceMillimes:
                      referencePriceMillimes === null
                        ? null
                        : BigInt(referencePriceMillimes),
                  }
                : {}),
            }),
          ),
        });
        await tx.auditEntry.create({
          data: {
            actorId: actor.id,
            action: "catalog.import",
            targetId: "catalog",
            details: { count: result.count },
          },
        });
        return result;
      },
      true,
    );
  }
}
