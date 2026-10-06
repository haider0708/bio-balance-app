import { Injectable } from "@nestjs/common";
import type { RewardRule, RuleScope } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, type Tx } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { MAX_MILLIMES } from "../../core/money";
import { addDays, dateToDay, dayToDate, tunisDay } from "../../core/dates";
import { unitRewards } from "./rules";

export interface RuleInput {
  scope: RuleScope;
  productId?: string;
  family?: string;
  amountMillimes: number;
  startsOn: string;
  endsOn?: string | null;
  note?: string;
  /** End or cancel the rules already covering these days, instead of refusing. */
  replaceOverlap?: boolean;
}

/** What each product or family pays per unit sold, set by the admin for a period. */
@Injectable()
export class RewardsService {
  constructor(private readonly db: Database) {}

  create(actor: Actor, input: RuleInput) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sets rewards.",
      403,
    );
    requireRule(
      BigInt(input.amountMillimes) <= MAX_MILLIMES,
      "AMOUNT_TOO_LARGE",
      "This amount is too large.",
    );
    requireRule(
      !input.endsOn || input.endsOn >= input.startsOn,
      "INVALID_PERIOD",
      "The end date is before the start date.",
    );
    return this.db.run(actor, async (tx) => {
      let targetKey: string;
      if (input.scope === "PRODUCT") {
        requireRule(input.productId, "TARGET_REQUIRED", "Choose a product.");
        requireRule(
          await tx.product.findUnique({ where: { id: input.productId } }),
          "PRODUCT_NOT_FOUND",
          "Unknown product.",
          404,
        );
        targetKey = `P:${input.productId}`;
      } else {
        requireRule(input.family, "TARGET_REQUIRED", "Choose a family.");
        requireRule(
          await tx.product.findFirst({ where: { family: input.family } }),
          "FAMILY_NOT_FOUND",
          "Unknown family.",
          404,
        );
        targetKey = `F:${input.family}`;
      }
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`rule:${targetKey}`}, 0))`;
      const starts = dayToDate(input.startsOn);
      const ends = input.endsOn ? dayToDate(input.endsOn) : null;
      const overlapping = await tx.rewardRule.findMany({
        where: {
          targetKey,
          cancelledAt: null,
          startsOn: ends ? { lte: ends } : undefined,
          OR: [{ endsOn: null }, { endsOn: { gte: starts } }],
        },
      });
      if (overlapping.length && !input.replaceOverlap)
        throw new DomainError(
          "RULE_OVERLAP",
          "Another value already covers some of these days.",
          409,
          {
            existing: overlapping.map((r) => ({
              id: r.id,
              startsOn: dateToDay(r.startsOn),
              endsOn: r.endsOn && dateToDay(r.endsOn),
              amountMillimes: r.amountMillimes,
            })),
          },
        );
      for (const old of overlapping) {
        // An earlier rule ends the day before; one that starts inside the new period is replaced.
        if (old.startsOn < starts)
          await tx.rewardRule.update({
            where: { id: old.id },
            data: { endsOn: dayToDate(addDays(input.startsOn, -1)) },
          });
        else
          await tx.rewardRule.update({
            where: { id: old.id },
            data: { cancelledAt: new Date(), cancelledById: actor.id },
          });
      }
      const rule = await tx.rewardRule.create({
        data: {
          scope: input.scope,
          productId: input.productId ?? null,
          family: input.family ?? null,
          targetKey,
          amountMillimes: BigInt(input.amountMillimes),
          startsOn: starts,
          endsOn: ends,
          note: input.note?.trim() || null,
          createdById: actor.id,
        },
      });
      await audit(tx, actor, "reward.rule_created", "RewardRule", rule.id, {
        targetKey,
        amountMillimes: input.amountMillimes,
        startsOn: input.startsOn,
        endsOn: input.endsOn ?? null,
      });
      return this.present(tx, [rule]).then((r) => r[0]!);
    });
  }

  cancel(actor: Actor, id: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sets rewards.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const rule = await tx.rewardRule.findUnique({ where: { id } });
      if (!rule) throw notFound("Reward rule");
      requireRule(
        !rule.cancelledAt,
        "INVALID_STATE",
        "This rule is already cancelled.",
        409,
      );
      const updated = await tx.rewardRule.update({
        where: { id },
        data: { cancelledAt: new Date(), cancelledById: actor.id },
      });
      await audit(tx, actor, "reward.rule_cancelled", "RewardRule", id, {
        targetKey: rule.targetKey,
      });
      return (await this.present(tx, [updated]))[0]!;
    });
  }

  /** Rules, newest period first. `when` filters to current, upcoming or past rules. */
  list(
    actor: Actor,
    filter: {
      when?: "current" | "upcoming" | "past";
      scope?: RuleScope;
      includeCancelled?: boolean;
    },
  ) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sees rewards.",
      403,
    );
    const today = dayToDate(tunisDay(new Date()));
    return this.db.run(actor, async (tx) => {
      const rules = await tx.rewardRule.findMany({
        where: {
          ...(filter.includeCancelled ? {} : { cancelledAt: null }),
          ...(filter.scope && { scope: filter.scope }),
          ...(filter.when === "current" && {
            startsOn: { lte: today },
            OR: [{ endsOn: null }, { endsOn: { gte: today } }],
          }),
          ...(filter.when === "upcoming" && { startsOn: { gt: today } }),
          ...(filter.when === "past" && { endsOn: { lt: today } }),
        },
        orderBy: [{ startsOn: "desc" }, { createdAt: "desc" }],
        take: 300,
      });
      return this.present(tx, rules);
    });
  }

  /** What every active product pays on a given day, and which rule decides it. */
  effective(actor: Actor, day: string) {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin sees rewards.",
      403,
    );
    return this.db.run(actor, async (tx) => {
      const products = await tx.product.findMany({
        where: { active: true },
        orderBy: [{ family: "asc" }, { name: "asc" }],
        select: { id: true, name: true, family: true },
      });
      const amounts = await unitRewards(tx, products, dayToDate(day));
      return products.map((p) => ({
        productId: p.id,
        name: p.name,
        family: p.family,
        amountMillimes: amounts.get(p.id) ?? 0n,
      }));
    });
  }

  private async present(tx: Tx, rules: RewardRule[]) {
    const productIds = rules
      .map((r) => r.productId)
      .filter((x): x is string => !!x);
    const products = await tx.product.findMany({
      where: { id: { in: productIds } },
      select: { id: true, name: true },
    });
    const name = new Map(products.map((p) => [p.id, p.name]));
    return rules.map((r) => ({
      id: r.id,
      scope: r.scope,
      productId: r.productId,
      family: r.family,
      targetName: r.productId ? (name.get(r.productId) ?? "") : r.family,
      amountMillimes: r.amountMillimes,
      startsOn: dateToDay(r.startsOn),
      endsOn: r.endsOn ? dateToDay(r.endsOn) : null,
      note: r.note,
      cancelledAt: r.cancelledAt,
      createdAt: r.createdAt,
    }));
  }
}
