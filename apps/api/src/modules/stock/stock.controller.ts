import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { StockService } from "./stock.service";

const id = z.uuid();
const qty = z.number().int().min(0).max(100_000);
const Lines = z
  .array(z.object({ productId: id, quantity: qty }))
  .min(1)
  .max(500);
const Declare = z.object({
  locationId: id,
  photoId: id.optional(),
  photoIds: z.array(id).max(5).optional(),
  note: z.string().trim().max(500).optional(),
  lines: z.array(z.object({ productId: id, quantity: qty })).max(500),
});
const Approve = z.object({
  lines: Lines.optional(),
  note: z.string().trim().max(500).optional(),
});
const Reject = z.object({ note: z.string().trim().min(2).max(500) });
const Review = z.object({
  action: z.enum(["approve", "reject"]),
  note: z.string().trim().max(500).optional(),
});
const Recount = z.object({
  locationId: id,
  reason: z.string().trim().min(3).max(500),
});
const Adjust = z.object({
  locationId: id,
  reason: z.string().trim().min(3).max(300),
  lines: z
    .array(z.object({ productId: id, quantity: qty }))
    .min(1)
    .max(500),
});
const Decision = z.object({ note: z.string().trim().max(500).optional() });

@Controller("v1/stock")
export class StockController {
  constructor(private readonly stock: StockService) {}

  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE", "VENDEUR")
  @Get("locations/:id")
  levels(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.levels(r.actor, parse(id, i));
  }

  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE")
  @Get("locations/:id/products/:productId/movements")
  movements(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Param("productId") p: string,
  ) {
    return this.stock.movements(r.actor, parse(id, i), parse(id, p));
  }

  @Roles("RESPONSABLE", "GROSSISTE")
  @Post("declarations")
  declare(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.stock.declare(r.actor, parse(Declare, b));
  }

  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE")
  @Get("declarations")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.stock.list(
      r.actor,
      parse(
        z.object({
          status: z
            .enum(["PENDING", "REVIEW", "APPROVED", "REJECTED"])
            .optional(),
          regionId: id.optional(),
          locationId: id.optional(),
        }),
        q,
      ),
    );
  }

  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE")
  @Get("declarations/:id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.get(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post("declarations/:id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.approve(r.actor, parse(id, i), parse(Approve, b ?? {}));
  }

  @Roles("ADMIN")
  @Post("declarations/:id/reject")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.reject(r.actor, parse(id, i), parse(Reject, b).note);
  }

  @Roles("RESPONSABLE")
  @Post("declarations/:id/review")
  review(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.review(r.actor, parse(id, i), parse(Review, b));
  }

  @Roles("RESPONSABLE", "GROSSISTE")
  @Post("recounts")
  requestRecount(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.stock.requestRecount(r.actor, parse(Recount, b));
  }

  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE")
  @Get("recounts")
  recounts(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.stock.listRecounts(
      r.actor,
      parse(
        z.object({
          status: z.enum(["PENDING", "APPROVED", "REJECTED"]).optional(),
          locationId: id.optional(),
        }),
        q,
      ),
    );
  }

  @Roles("ADMIN")
  @Post("recounts/:id/approve")
  approveRecount(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.stock.decideRecount(
      r.actor,
      parse(id, i),
      "approve",
      parse(Decision, b ?? {}).note,
    );
  }

  @Roles("ADMIN")
  @Post("recounts/:id/reject")
  rejectRecount(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.stock.decideRecount(
      r.actor,
      parse(id, i),
      "reject",
      parse(Reject, b).note,
    );
  }

  @Roles("ADMIN")
  @Post("adjust")
  adjust(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.stock.adjust(r.actor, parse(Adjust, b));
  }
}
