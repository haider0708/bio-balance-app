import { Injectable } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";

export interface ProductInput {
  reference: string;
  name: string;
  barcode?: string | null;
  family: string;
  range?: string;
  packageSize?: string;
  description?: string;
  instructions?: string;
  ingredients?: string;
  precautions?: string;
  imageId?: string | null;
  active?: boolean;
}

@Injectable()
export class CatalogService {
  constructor(private readonly db: Database) {}

  /** Products everyone can pick from. Inactive ones are hidden from non-admins. */
  async list(
    actor: Actor,
    filter: { q?: string; family?: string; includeInactive?: boolean },
  ) {
    const where: Prisma.ProductWhereInput = {
      ...(actor.role === "ADMIN" && filter.includeInactive
        ? {}
        : { active: true }),
      ...(filter.family && { family: filter.family }),
      ...(filter.q && {
        OR: [
          { name: { contains: filter.q, mode: "insensitive" } },
          { reference: { contains: filter.q, mode: "insensitive" } },
          { barcode: { contains: filter.q } },
        ],
      }),
    };
    return this.db.product.findMany({
      where,
      orderBy: [{ family: "asc" }, { name: "asc" }],
      take: 1000,
    });
  }

  async families() {
    const rows = await this.db.product.groupBy({
      by: ["family"],
      where: { active: true },
      _count: { _all: true },
      orderBy: { family: "asc" },
    });
    return rows.map((r) => ({ family: r.family, count: r._count._all }));
  }

  async get(id: string) {
    const product = await this.db.product.findUnique({ where: { id } });
    if (!product) throw notFound("Product");
    return product;
  }

  /** Barcode lookup used by the sale screen. */
  async byBarcode(barcode: string) {
    const product = await this.db.product.findFirst({
      where: { barcode, active: true },
    });
    if (!product) throw notFound("Product");
    return product;
  }

  create(actor: Actor, input: ProductInput) {
    return this.db.run(actor, async (tx) => {
      await this.checkImage(tx, input.imageId);
      const product = await tx.product.create({
        data: this.data(input) as Prisma.ProductCreateInput,
      });
      await audit(tx, actor, "product.created", "Product", product.id, {
        reference: product.reference,
      });
      return product;
    });
  }

  update(actor: Actor, id: string, input: Partial<ProductInput>) {
    return this.db.run(actor, async (tx) => {
      await this.checkImage(tx, input.imageId);
      const existing = await tx.product.findUnique({ where: { id } });
      if (!existing) throw notFound("Product");
      const product = await tx.product.update({
        where: { id },
        data: this.data(input),
      });
      await audit(tx, actor, "product.updated", "Product", id, {
        fields: Object.keys(input),
      });
      return product;
    });
  }

  /** Add or refresh many products at once, matched by reference. */
  importMany(actor: Actor, items: ProductInput[]) {
    return this.db.run(actor, async (tx) => {
      let created = 0;
      let updated = 0;
      for (const item of items) {
        const existing = await tx.product.findUnique({
          where: { reference: item.reference },
          select: { id: true },
        });
        if (existing) {
          await tx.product.update({
            where: { id: existing.id },
            data: this.data(item),
          });
          updated++;
        } else {
          await tx.product.create({
            data: this.data(item) as Prisma.ProductCreateInput,
          });
          created++;
        }
      }
      await audit(
        tx,
        actor,
        "product.imported",
        "Product",
        "00000000-0000-0000-0000-000000000000",
        { created, updated },
      );
      return { created, updated };
    });
  }

  private async checkImage(
    tx: Prisma.TransactionClient,
    imageId?: string | null,
  ) {
    if (!imageId) return;
    const media = await tx.mediaAsset.findUnique({ where: { id: imageId } });
    requireRule(
      media?.purpose === "PRODUCT",
      "MEDIA_SCOPE",
      "Use an uploaded product image.",
      422,
    );
  }

  private data(input: Partial<ProductInput>): Prisma.ProductUpdateInput {
    const {
      reference,
      name,
      barcode,
      family,
      range,
      packageSize,
      description,
      instructions,
      ingredients,
      precautions,
      imageId,
      active,
    } = input;
    return {
      ...(reference !== undefined && { reference }),
      ...(name !== undefined && { name }),
      ...(barcode !== undefined && { barcode: barcode || null }),
      ...(family !== undefined && { family }),
      ...(range !== undefined && { range }),
      ...(packageSize !== undefined && { packageSize }),
      ...(description !== undefined && { description }),
      ...(instructions !== undefined && { instructions }),
      ...(ingredients !== undefined && { ingredients }),
      ...(precautions !== undefined && { precautions }),
      ...(imageId !== undefined && { imageId }),
      ...(active !== undefined && { active }),
    };
  }
}
