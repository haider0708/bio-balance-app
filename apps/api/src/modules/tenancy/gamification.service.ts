import { randomUUID } from "node:crypto";
import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { requireRule } from "../../shared/domain/errors";
import { Database, json } from "../../shared/infrastructure/database";
import { Actor } from "../operations/domain/contracts";
import { GamificationRequests, defaultsQuery } from "./gamification.contracts";

type Tx = Prisma.TransactionClient;
type Audience = "retail" | "wholesale";
type Place = { organizationId: string; storeId: string };

/**
 * Points and rewards have one default, set by BioBalance, for every store
 * (retail) or every grossiste depot (wholesale), and exceptions per place.
 * Defaults are copied into each place so that sales, claims, history and
 * row-level security keep working on the place's own rows; a place's own rate
 * (an exception) is left alone by later default changes.
 */
@Injectable()
export class GamificationService {
  constructor(private readonly db: Database) {}

  private admin(actor: Actor) {
    requireRule(
      actor.platformAdmin,
      "FORBIDDEN",
      "Les points et les récompenses sont gérés par BioBalance.",
      403,
    );
  }

  /** The default rate in force for each product of an audience. */
  private async pointsDefaults(
    tx: Tx,
    audience: Audience,
    productIds?: string[],
  ) {
    const rows = await tx.$queryRaw<
      { productId: string; pointsPerUnit: number }[]
    >(
      Prisma.sql`SELECT DISTINCT ON ("productId") "productId","pointsPerUnit"
        FROM "PointsDefault" WHERE audience=${audience}
        ${productIds?.length ? Prisma.sql`AND "productId" IN (${Prisma.join(productIds.map((id) => Prisma.sql`${id}::uuid`))})` : Prisma.empty}
        ORDER BY "productId","createdAt" DESC,id DESC`,
    );
    return new Map(rows.map((r) => [r.productId, r.pointsPerUnit]));
  }

  /** Every active store or depot of an audience. */
  private places(actor: Actor, audience: Audience): Promise<Place[]> {
    return this.db.authenticated(
      actor,
      async (tx) => {
        await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
        const groups = await tx.organization.findMany({
          where: { kind: audience, status: { not: "archived" } },
          select: { id: true },
        });
        const stores = await tx.store.findMany({
          where: {
            organizationId: { in: groups.map((g) => g.id) },
            status: { not: "archived" },
          },
          select: { id: true, organizationId: true },
        });
        return stores.map((s) => ({
          organizationId: s.organizationId,
          storeId: s.id,
        }));
      },
      true,
    );
  }

  defaults(actor: Actor, raw: unknown) {
    const q = defaultsQuery.parse(raw);
    return this.db.authenticated(
      actor,
      async (tx) => {
        const points = await this.pointsDefaults(tx, q.audience);
        const rewards = await tx.rewardTemplate.findMany({
          where: { audience: q.audience },
          orderBy: [{ active: "desc" }, { cost: "asc" }],
        });
        return {
          points: [...points.entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([productId, pointsPerUnit]) => ({
              productId,
              pointsPerUnit,
            })),
          rewards,
        };
      },
      true,
    );
  }

  async setPointsDefault(
    actor: Actor,
    input: z.infer<typeof GamificationRequests.PointsDefault>,
  ) {
    await this.db.authenticated(
      actor,
      async (tx, current) => {
        requireRule(
          await tx.product.findUnique({ where: { id: input.productId } }),
          "PRODUCT_NOT_FOUND",
          "Produit introuvable.",
          404,
        );
        await tx.$executeRaw`SELECT set_config('app.gamification_admin','true',true)`;
        await tx.pointsDefault.create({
          data: {
            id: randomUUID(),
            audience: input.audience,
            productId: input.productId,
            pointsPerUnit: input.pointsPerUnit,
            reason: input.reason ?? null,
            createdBy: current.id,
          },
        });
        await tx.auditEntry.create({
          data: {
            actorId: current.id,
            action: "points.default",
            targetId: input.productId,
            details: json(input),
          },
        });
      },
      true,
    );
    const places = await this.places(actor, input.audience);
    for (const place of places)
      await this.applyDefaults(actor, place.organizationId, place.storeId, {
        productIds: [input.productId],
        rewards: false,
      });
    return { ...input, places: places.length };
  }

  async saveRewardTemplate(
    actor: Actor,
    input: z.infer<typeof GamificationRequests.RewardTemplate>,
  ) {
    const template = await this.db.authenticated(
      actor,
      async (tx, current) => {
        if (input.productId)
          requireRule(
            await tx.product.findUnique({ where: { id: input.productId } }),
            "PRODUCT_NOT_FOUND",
            "Produit introuvable.",
            404,
          );
        await tx.$executeRaw`SELECT set_config('app.gamification_admin','true',true)`;
        const { id, expectedVersion, ...data } = input;
        const fields = { ...data, productId: data.productId ?? null };
        let saved;
        if (id) {
          const old = await tx.rewardTemplate.findUnique({ where: { id } });
          requireRule(old, "NOT_FOUND", "Récompense introuvable.", 404);
          requireRule(
            old.version === expectedVersion,
            "VERSION_CONFLICT",
            "La récompense a changé.",
            409,
          );
          requireRule(
            old.audience === input.audience,
            "VALIDATION",
            "Une récompense par défaut garde son public.",
          );
          saved = await tx.rewardTemplate.update({
            where: { id },
            data: { ...fields, version: { increment: 1 } },
          });
        } else
          saved = await tx.rewardTemplate.create({
            data: { id: randomUUID(), ...fields, createdBy: current.id },
          });
        await tx.auditEntry.create({
          data: {
            actorId: current.id,
            action: "reward.default",
            targetId: saved.id,
            details: json(saved),
          },
        });
        return saved;
      },
      true,
    );
    const places = await this.places(actor, input.audience);
    for (const place of places)
      await this.applyDefaults(actor, place.organizationId, place.storeId, {
        productIds: [],
        rewards: true,
        templateId: template.id,
      });
    return template;
  }

  /**
   * Copies the defaults into one place: rates for products without an exception,
   * and the default rewards. Called for a new store or depot (everything) and
   * after a default changes (only what changed). Idempotent.
   */
  applyDefaults(
    actor: Actor,
    organizationId: string,
    storeId: string,
    only: {
      productIds?: string[];
      rewards?: boolean;
      templateId?: string;
    } = {},
  ) {
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      const audience: Audience = scope.wholesale ? "wholesale" : "retail";
      await tx.storeCursor.upsert({
        where: { storeId },
        create: { storeId, organizationId },
        update: {},
      });
      await tx.$queryRaw`SELECT "storeId" FROM "StoreCursor" WHERE "storeId"=${storeId}::uuid FOR UPDATE`;
      const changed = async (entity: string, entityId: string) => {
        const cursor = await tx.storeCursor.update({
          where: { storeId },
          data: { value: { increment: 1 } },
        });
        await tx.change.create({
          data: {
            storeId,
            organizationId,
            cursor: cursor.value,
            entity,
            entityId,
          },
        });
      };
      let rates = 0,
        rewards = 0;
      if (only.productIds === undefined || only.productIds.length) {
        const defaults = await this.pointsDefaults(
          tx,
          audience,
          only.productIds,
        );
        for (const [productId, points] of defaults) {
          const old = await tx.storeProduct.findUnique({
            where: { storeId_productId: { storeId, productId } },
          });
          if (old?.pointsException) continue;
          if (old?.pointsConfigured && old.pointsPerUnit === points) continue;
          await this.writeRate(tx, organizationId, storeId, productId, points, {
            exception: false,
            reason: "Barème par défaut",
            actorId: actor.id,
          });
          await changed("product.configure", productId);
          rates++;
        }
      }
      if (only.rewards !== false) {
        const templates = await tx.rewardTemplate.findMany({
          where: {
            audience,
            ...(only.templateId ? { id: only.templateId } : {}),
          },
        });
        for (const t of templates) {
          const copy = await tx.reward.findFirst({
            where: { storeId, templateId: t.id },
          });
          const fields = {
            title: t.title,
            description: t.description,
            cost: t.cost,
            productId: t.productId,
            quantity: t.quantity,
            active: t.active,
          };
          if (copy) {
            if (
              Object.entries(fields).every(
                ([k, v]) => copy[k as keyof typeof fields] === v,
              )
            )
              continue;
            await tx.reward.update({
              where: { id: copy.id },
              data: { ...fields, version: { increment: 1 } },
            });
          } else
            await tx.reward.create({
              data: { organizationId, storeId, templateId: t.id, ...fields },
            });
          await changed("reward.configure", t.id);
          rewards++;
        }
      }
      return { rates, rewards };
    });
  }

  /** Writes a rate into a place and its history, as a sale will read it. */
  private async writeRate(
    tx: Tx,
    organizationId: string,
    storeId: string,
    productId: string,
    points: number,
    meta: { exception: boolean; reason: string; actorId: string },
  ) {
    const data = {
      pointsPerUnit: points,
      pointsConfigured: true,
      zeroPointsConfirmed: points === 0,
      pointsException: meta.exception,
    };
    await tx.storeProduct.upsert({
      where: { storeId_productId: { storeId, productId } },
      create: { organizationId, storeId, productId, ...data },
      update: { ...data, version: { increment: 1 } },
    });
    await tx.pointsRateVersion.create({
      data: {
        id: randomUUID(),
        organizationId,
        storeId,
        productId,
        pointsPerUnit: points,
        reason: meta.reason,
        createdBy: meta.actorId,
      },
    });
  }

  /** A place's rates beside the defaults, for BioBalance. */
  storePoints(actor: Actor, organizationId: string, storeId: string) {
    this.admin(actor);
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      const defaults = await this.pointsDefaults(
        tx,
        scope.wholesale ? "wholesale" : "retail",
      );
      const rows = await tx.storeProduct.findMany({ where: { storeId } });
      const ids = new Set([
        ...defaults.keys(),
        ...rows.map((r) => r.productId),
      ]);
      return {
        items: [...ids].sort().map((productId) => {
          const row = rows.find((r) => r.productId === productId);
          return {
            productId,
            pointsPerUnit: row?.pointsConfigured
              ? row.pointsPerUnit
              : (defaults.get(productId) ?? null),
            defaultPointsPerUnit: defaults.get(productId) ?? null,
            exception: row?.pointsException === true,
          };
        }),
      };
    });
  }

  /** BioBalance gives a place its own rate, or returns it to the default. */
  setStorePoints(
    actor: Actor,
    organizationId: string,
    storeId: string,
    input: z.infer<typeof GamificationRequests.StorePoints>,
  ) {
    this.admin(actor);
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      const fallback = (
        await this.pointsDefaults(
          tx,
          scope.wholesale ? "wholesale" : "retail",
          [input.productId],
        )
      ).get(input.productId);
      if (input.reset)
        requireRule(
          fallback !== undefined,
          "NO_DEFAULT",
          "Ce produit n’a pas de barème par défaut.",
          409,
        );
      const points = input.reset ? fallback! : input.pointsPerUnit!;
      await tx.storeCursor.upsert({
        where: { storeId },
        create: { storeId, organizationId },
        update: {},
      });
      await this.writeRate(
        tx,
        organizationId,
        storeId,
        input.productId,
        points,
        {
          exception: !input.reset,
          reason: input.reset
            ? "Retour au barème par défaut"
            : "Barème particulier",
          actorId: actor.id,
        },
      );
      const cursor = await tx.storeCursor.update({
        where: { storeId },
        data: { value: { increment: 1 } },
      });
      await tx.change.create({
        data: {
          storeId,
          organizationId,
          cursor: cursor.value,
          entity: "product.configure",
          entityId: input.productId,
        },
      });
      await tx.auditEntry.create({
        data: {
          organizationId,
          storeId,
          actorId: actor.id,
          action: input.reset ? "points.reset" : "points.exception",
          targetId: input.productId,
          details: json({ ...input, pointsPerUnit: points }),
        },
      });
      return {
        productId: input.productId,
        pointsPerUnit: points,
        defaultPointsPerUnit: fallback ?? null,
        exception: !input.reset,
      };
    });
  }
}
