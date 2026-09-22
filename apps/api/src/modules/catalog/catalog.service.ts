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
}
@Injectable()
export class CatalogService {
  constructor(private readonly db: Database) {}
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
        const { id, expectedVersion, ...data } = input;
        const old = id ? await tx.product.findUnique({ where: { id } }) : null;
        requireRule(
          !id || old?.version === expectedVersion,
          "VERSION_CONFLICT",
          "Le produit a changé.",
          409,
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
        if (!commit) return { valid: true, count: rows.length, rows };
        for (const row of rows) await requireImage(tx, row.imageId, "catalog");
        const result = await tx.product.createMany({
          data: rows.map(({ id, expectedVersion, ...row }) => row),
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
