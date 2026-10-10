import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { dateToDay, dayToDate, tunisDay } from "../../core/dates";
import { Database, json, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { notify, responsableIds } from "../../core/notifier";
import { decodeCursor, page } from "../../core/pagination";
import { adjustStock, type Location } from "../stock/ledger";
import { unitRewards } from "../rewards/rules";
import { walletSummary } from "../rewards/wallet.queries";

export interface SaleLineInput {
  productId: string;
  quantity: number;
}

type SaleWithLines = Prisma.SaleGetPayload<{ include: { lines: true } }>;

const CORRECTION_WINDOW_MS = 48 * 3600_000;

@Injectable()
export class SalesService {
  constructor(private readonly db: Database) {}

  /**
   * Record a sale. The phone picks the id, so sending the same sale twice
   * (a retry after a dropped connection) never counts it twice.
   */
  create(
    actor: Actor,
    input: { id: string; occurredAt?: Date; lines: SaleLineInput[] },
  ) {
    requireRule(
      actor.role === "VENDEUR" && actor.pdvId && actor.regionId,
      "FORBIDDEN",
      "Only a team member records sales.",
      403,
    );
    const now = Date.now();
    const occurredAt = input.occurredAt ?? new Date(now);
    requireRule(
      occurredAt.getTime() <= now + 5 * 60_000,
      "INVALID_DATE",
      "The sale date is in the future.",
    );
    requireRule(
      occurredAt.getTime() >= now - 30 * 86400_000,
      "INVALID_DATE",
      "The sale is too old to be recorded.",
    );
    return this.record(actor, input, occurredAt).catch(async (error) => {
      // The same sale sent twice at once: the loser of the race gets the winner's receipt.
      if (error instanceof DomainError && error.code === "DUPLICATE")
        return this.db.run(actor, (tx) =>
          this.receipt(tx, actor, input.id, true),
        );
      throw error;
    });
  }

  private record(
    actor: Actor,
    input: { id: string; lines: SaleLineInput[] },
    occurredAt: Date,
  ) {
    return this.db.run(actor, async (tx) => {
      const existing = await tx.sale.findUnique({
        where: { id: input.id },
        include: { lines: true },
      });
      if (existing) return this.receipt(tx, actor, existing.id, true);

      const pdv = await tx.pdv.findUnique({ where: { id: actor.pdvId! } });
      requireRule(
        pdv?.status === "ACTIVE",
        "PDV_INACTIVE",
        "Your point of sale is not active.",
        403,
      );
      const products = await this.products(tx, input.lines);
      const day = dayToDate(tunisDay(occurredAt));
      const rewards = await unitRewards(tx, products, day);
      const lines = input.lines.map((l) => ({
        ...l,
        unit: rewards.get(l.productId) ?? 0n,
      }));
      const total = lines.reduce(
        (sum, l) => sum + l.unit * BigInt(l.quantity),
        0n,
      );
      const units = lines.reduce((sum, l) => sum + l.quantity, 0);

      await tx.sale.create({
        data: {
          id: input.id,
          pdvId: pdv.id,
          regionId: pdv.regionId,
          sellerId: actor.id,
          occurredAt,
          day,
          units,
          rewardMillimes: total,
          lines: {
            create: lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
              unitRewardMillimes: l.unit,
            })),
          },
        },
      });
      const location = this.location(pdv);
      for (const l of lines)
        await adjustStock(tx, location, l.productId, -l.quantity, {
          reason: "SALE",
          refType: "Sale",
          refId: input.id,
          actorId: actor.id,
        });
      if (total > 0n)
        await tx.walletEntry.createMany({
          data: [
            {
              userId: actor.id,
              kind: "SALE",
              amountMillimes: total,
              saleId: input.id,
            },
          ],
        });
      // The responsable of the region hears about every sale of their stores.
      await notify(tx, await responsableIds(tx, pdv.regionId), {
        key: "sale.recorded",
        params: {
          seller: actor.name,
          place: pdv.name,
          units,
          amountMillimes: total,
        },
        entityType: "Sale",
        entityId: input.id,
      });
      await audit(
        tx,
        actor,
        "sale.created",
        "Sale",
        input.id,
        { units, rewardMillimes: total },
        pdv.regionId,
      );
      return this.receipt(tx, actor, input.id, false);
    });
  }

  /**
   * Fix a sale: new quantities, or no lines at all to cancel it. Stock and the
   * seller's wallet follow, and the change is kept in the sale's history.
   */
  correct(
    actor: Actor,
    id: string,
    input: { reason: string; lines: SaleLineInput[] },
  ) {
    return this.db.run(actor, async (tx) => {
      const visible = await tx.sale.findUnique({
        where: { id },
        select: { id: true },
      });
      if (!visible) throw notFound("Sale");
      await this.db.lock(tx, "Sale", id);
      const sale = await tx.sale.findUniqueOrThrow({
        where: { id },
        include: { lines: true },
      });
      requireRule(
        sale.status === "ACTIVE",
        "INVALID_STATE",
        "This sale was cancelled.",
        409,
      );
      requireRule(
        actor.role !== "VENDEUR" ||
          Date.now() - sale.createdAt.getTime() <= CORRECTION_WINDOW_MS,
        "CORRECTION_WINDOW_CLOSED",
        "A sale can be corrected for 48 hours. Ask your responsable.",
        403,
      );
      requireRule(
        ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
        "FORBIDDEN",
        "Not allowed.",
        403,
      );
      await this.db.lock(tx, "User", sale.sellerId);

      const products = await this.products(tx, input.lines, true);
      const fresh = await unitRewards(tx, products, sale.day);
      const oldUnit = new Map(
        sale.lines.map((l) => [l.productId, l.unitRewardMillimes]),
      );
      // A product already in the sale keeps the reward it earned; new products use today's rules for the sale day.
      const next = input.lines.map((l) => ({
        ...l,
        unit: oldUnit.get(l.productId) ?? fresh.get(l.productId) ?? 0n,
      }));
      const total = next.reduce(
        (sum, l) => sum + l.unit * BigInt(l.quantity),
        0n,
      );
      const units = next.reduce((sum, l) => sum + l.quantity, 0);
      const before = sale.lines.map((l) => ({
        productId: l.productId,
        quantity: l.quantity,
      }));

      const pdv = await tx.pdv.findUniqueOrThrow({ where: { id: sale.pdvId } });
      const location = this.location(pdv);
      const oldQty = new Map(sale.lines.map((l) => [l.productId, l.quantity]));
      const newQty = new Map(next.map((l) => [l.productId, l.quantity]));
      for (const productId of new Set([...oldQty.keys(), ...newQty.keys()])) {
        const delta =
          (oldQty.get(productId) ?? 0) - (newQty.get(productId) ?? 0); // goods come back when fewer were sold
        await adjustStock(tx, location, productId, delta, {
          reason: "SALE_CORRECTION",
          refType: "Sale",
          refId: id,
          actorId: actor.id,
        });
      }
      await tx.saleLine.deleteMany({ where: { saleId: id } });
      await tx.saleLine.createMany({
        data: next.map((l) => ({
          saleId: id,
          productId: l.productId,
          quantity: l.quantity,
          unitRewardMillimes: l.unit,
        })),
      });
      const version = sale.version + 1;
      await tx.sale.update({
        where: { id },
        data: {
          units,
          rewardMillimes: total,
          version,
          status: next.length ? "ACTIVE" : "VOIDED",
        },
      });
      await tx.saleRevision.createMany({
        data: [
          {
            saleId: id,
            version,
            editorId: actor.id,
            reason: input.reason,
            before: json(before),
            after: json(input.lines),
          },
        ],
      });
      const difference = total - sale.rewardMillimes;
      if (difference !== 0n)
        await tx.walletEntry.createMany({
          data: [
            {
              userId: sale.sellerId,
              kind: "CORRECTION",
              amountMillimes: difference,
              saleId: id,
              note: input.reason,
            },
          ],
        });
      await audit(
        tx,
        actor,
        next.length ? "sale.corrected" : "sale.voided",
        "Sale",
        id,
        { reason: input.reason, units },
        sale.regionId,
      );
      if (sale.sellerId !== actor.id)
        await notify(tx, [sale.sellerId], {
          key: next.length ? "sale.corrected" : "sale.voided",
          params: { by: actor.name, reason: input.reason },
          entityType: "Sale",
          entityId: id,
        });
      return this.receipt(tx, actor, id, false);
    });
  }

  async list(
    actor: Actor,
    filter: {
      from?: string;
      to?: string;
      pdvId?: string;
      sellerId?: string;
      regionId?: string;
      groupId?: string;
      productId?: string;
      family?: string;
      status?: "ACTIVE" | "VOIDED";
      limit: number;
      cursor?: string;
    },
  ) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const after = decodeCursor(filter.cursor);
      // A family is its products, a group its stores; a product or a store named as well narrows further.
      const products = filter.productId
        ? [filter.productId]
        : filter.family
          ? (
              await tx.product.findMany({
                where: { family: filter.family },
                select: { id: true },
              })
            ).map((p) => p.id)
          : null;
      const stores = filter.pdvId
        ? [filter.pdvId]
        : filter.groupId
          ? (
              await tx.pdv.findMany({
                where: { groupId: filter.groupId },
                select: { id: true },
              })
            ).map((p) => p.id)
          : null;
      const rows = await tx.sale.findMany({
        where: {
          ...((filter.from || filter.to) && {
            day: {
              ...(filter.from && { gte: dayToDate(filter.from) }),
              ...(filter.to && { lte: dayToDate(filter.to) }),
            },
          }),
          ...(products && { lines: { some: { productId: { in: products } } } }),
          ...(stores && { pdvId: { in: stores } }),
          ...(filter.status && { status: filter.status }),
          // The database already hides what is not theirs; naming it lets it use the indexes.
          ...(actor.role === "VENDEUR" && { sellerId: actor.id }),
          ...(actor.role === "RESPONSABLE" &&
            actor.regionId && { regionId: actor.regionId }),
          ...(filter.sellerId && { sellerId: filter.sellerId }),
          ...(actor.role === "ADMIN" &&
            filter.regionId && { regionId: filter.regionId }),
          ...(after && {
            OR: [
              { createdAt: { lt: after.createdAt } },
              { createdAt: after.createdAt, id: { lt: after.id } },
            ],
          }),
        },
        include: { lines: true },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: filter.limit + 1,
      });
      const result = page(rows, filter.limit);
      return {
        items: await this.present(tx, result.items),
        nextCursor: result.nextCursor,
      };
    });
  }

  /**
   * One row per day with its totals: the overview of a long history. A team
   * member sees their own days, a responsable their region's, the admin all.
   */
  days(
    actor: Actor,
    filter: { from: string; to: string; pdvId?: string; sellerId?: string },
  ) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rows = await tx.$queryRaw<
        {
          day: string;
          sales: number;
          units: number;
          rewardMillimes: bigint;
        }[]
      >`
        SELECT to_char(s.day,'YYYY-MM-DD') AS day, COUNT(*)::int AS sales, SUM(s.units)::int AS units, SUM(s."rewardMillimes")::bigint AS "rewardMillimes"
        FROM "Sale" s
        WHERE s.status='ACTIVE' AND s.day BETWEEN ${dayToDate(filter.from)}::date AND ${dayToDate(filter.to)}::date
          ${filter.pdvId ? Prisma.sql`AND s."pdvId" = ${filter.pdvId}::uuid` : Prisma.empty}
          ${actor.role === "VENDEUR" ? Prisma.sql`AND s."sellerId" = ${actor.id}::uuid` : Prisma.empty}
          ${actor.role === "RESPONSABLE" && actor.regionId ? Prisma.sql`AND s."regionId" = ${actor.regionId}::uuid` : Prisma.empty}
          ${filter.sellerId ? Prisma.sql`AND s."sellerId" = ${filter.sellerId}::uuid` : Prisma.empty}
        GROUP BY 1 ORDER BY 1 DESC LIMIT 400`;
      return rows;
    });
  }

  get(actor: Actor, id: string) {
    requireRule(
      ["VENDEUR", "RESPONSABLE", "ADMIN"].includes(actor.role),
      "FORBIDDEN",
      "Not allowed.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const sale = await tx.sale.findUnique({
        where: { id },
        include: { lines: true },
      });
      if (!sale) throw notFound("Sale");
      const [detail] = await this.present(tx, [sale]);
      const revisions = await tx.saleRevision.findMany({
        where: { saleId: id },
        orderBy: { version: "asc" },
      });
      return { ...detail!, revisions };
    });
  }

  // ───────────────────────── Helpers ─────────────────────────

  private location(pdv: {
    id: string;
    regionId: string;
  }): Pick<Location, "id" | "kind" | "regionId"> {
    return { id: pdv.id, kind: "PDV", regionId: pdv.regionId };
  }

  private async products(tx: Tx, lines: SaleLineInput[], allowEmpty = false) {
    requireRule(
      allowEmpty || lines.length > 0,
      "NO_LINES",
      "Add at least one product.",
    );
    const ids = lines.map((l) => l.productId);
    requireRule(
      new Set(ids).size === ids.length,
      "DUPLICATE_PRODUCT",
      "A product appears twice.",
    );
    const products = await tx.product.findMany({
      where: { id: { in: ids } },
      select: { id: true, family: true, active: true },
    });
    requireRule(
      products.length === ids.length,
      "PRODUCT_NOT_FOUND",
      "Unknown product.",
      404,
    );
    return products;
  }

  /** What the phone shows right after a sale: the reward, and the new totals for the celebration screen. */
  private async receipt(tx: Tx, actor: Actor, id: string, replay: boolean) {
    const sale = await tx.sale.findUniqueOrThrow({
      where: { id },
      include: { lines: true },
    });
    const [detail] = await this.present(tx, [sale]);
    const wallet =
      sale.sellerId === actor.id ? await walletSummary(tx, actor.id) : null;
    return { ...detail!, replay, wallet };
  }

  private async present(tx: Tx, sales: SaleWithLines[]) {
    if (!sales.length) return [];
    const productIds = [
      ...new Set(sales.flatMap((s) => s.lines.map((l) => l.productId))),
    ];
    const [products, sellers, pdvs] = await Promise.all([
      tx.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, name: true, imageId: true },
      }),
      tx.user.findMany({
        where: { id: { in: [...new Set(sales.map((s) => s.sellerId))] } },
        select: { id: true, name: true },
      }),
      tx.pdv.findMany({
        where: { id: { in: [...new Set(sales.map((s) => s.pdvId))] } },
        select: { id: true, name: true },
      }),
    ]);
    const product = new Map(products.map((p) => [p.id, p]));
    const seller = new Map(sellers.map((u) => [u.id, u.name]));
    const place = new Map(pdvs.map((p) => [p.id, p.name]));
    return sales.map((s) => ({
      id: s.id,
      status: s.status,
      version: s.version,
      occurredAt: s.occurredAt,
      day: dateToDay(s.day),
      createdAt: s.createdAt,
      units: s.units,
      rewardMillimes: s.rewardMillimes,
      seller: { id: s.sellerId, name: seller.get(s.sellerId) ?? "" },
      pdv: { id: s.pdvId, name: place.get(s.pdvId) ?? "" },
      lines: s.lines.map((l) => ({
        productId: l.productId,
        name: product.get(l.productId)?.name ?? "",
        imageId: product.get(l.productId)?.imageId ?? null,
        quantity: l.quantity,
        rewardMillimes: l.unitRewardMillimes * BigInt(l.quantity),
      })),
    }));
  }
}
