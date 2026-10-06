import { Body, Controller, Delete, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PageQuery } from "../../core/pagination";
import { RewardsService } from "./rewards.service";
import { WalletService } from "./wallet.service";

const id = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const Rule = z.object({
  scope: z.enum(["PRODUCT", "FAMILY"]),
  productId: id.optional(),
  family: z.string().trim().min(1).max(80).optional(),
  amountMillimes: z.number().int().min(0).max(1_000_000_000),
  startsOn: day,
  endsOn: day.nullable().optional(),
  note: z.string().trim().max(300).optional(),
  replaceOverlap: z.boolean().optional(),
});
const Payout = z.object({ amountMillimes: z.number().int().min(1).max(1_000_000_000) });
const Approve = z.object({
  paidAt: z.coerce.date().optional(),
  reference: z.string().trim().max(80).optional(),
  note: z.string().trim().max(300).optional(),
});
const Reject = z.object({ note: z.string().trim().min(2).max(300) });
const PayoutStatus = z.enum(["PENDING", "APPROVED", "REJECTED", "CANCELLED"]);

@Controller("v1")
export class RewardsController {
  constructor(
    private readonly rewards: RewardsService,
    private readonly wallet: WalletService,
  ) {}

  // Rules (admin)
  @Roles("ADMIN") @Post("reward-rules")
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.rewards.create(r.actor, parse(Rule, b));
  }
  @Roles("ADMIN") @Get("reward-rules")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.rewards.list(r.actor, parse(
      z.object({ when: z.enum(["current", "upcoming", "past"]).optional(), scope: z.enum(["PRODUCT", "FAMILY"]).optional(), includeCancelled: z.stringbool().optional() }), q));
  }
  @Roles("ADMIN") @Get("reward-rules/effective")
  effective(@Req() r: AuthRequest, @Query("day") d?: string) {
    return this.rewards.effective(r.actor, parse(day.optional(), d) ?? new Date().toISOString().slice(0, 10));
  }
  @Roles("ADMIN") @Delete("reward-rules/:id")
  cancel(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.rewards.cancel(r.actor, parse(id, i));
  }

  // Wallet (team member)
  @Roles("VENDEUR") @Get("wallet")
  mine(@Req() r: AuthRequest) {
    return this.wallet.mine(r.actor);
  }
  @Roles("VENDEUR") @Get("wallet/entries")
  entries(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.wallet.entries(r.actor, parse(PageQuery, q));
  }
  @Roles("ADMIN") @Get("wallets")
  overview(@Req() r: AuthRequest, @Query("regionId") region?: string) {
    return this.wallet.overview(r.actor, { regionId: parse(id.optional(), region) });
  }

  // Payouts
  @Roles("VENDEUR") @Post("payouts")
  request(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.wallet.request(r.actor, parse(Payout, b).amountMillimes);
  }
  @Roles("VENDEUR", "ADMIN") @Get("payouts")
  payouts(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.wallet.list(r.actor, parse(z.object({ status: PayoutStatus.optional(), regionId: id.optional() }), q));
  }
  @Roles("VENDEUR") @Post("payouts/:id/cancel")
  cancelPayout(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.wallet.cancel(r.actor, parse(id, i));
  }
  @Roles("ADMIN") @Post("payouts/:id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.wallet.approve(r.actor, parse(id, i), parse(Approve, b ?? {}));
  }
  @Roles("ADMIN") @Post("payouts/:id/reject")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.wallet.reject(r.actor, parse(id, i), parse(Reject, b).note);
  }
}
