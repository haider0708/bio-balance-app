import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PageQuery } from "../../core/pagination";
import { SalesService } from "./sales.service";

const id = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const Lines = z
  .array(
    z.object({ productId: id, quantity: z.number().int().min(1).max(9999) }),
  )
  .max(100);
const Create = z.object({
  id,
  occurredAt: z.coerce.date().optional(),
  lines: Lines.min(1),
});
const Correct = z.object({
  reason: z.string().trim().min(2).max(300),
  lines: Lines,
});

@Controller("v1/sales")
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Roles("VENDEUR")
  @Post()
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.sales.create(r.actor, parse(Create, b));
  }
  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get()
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.sales.list(
      r.actor,
      parse(
        PageQuery.extend({
          from: day.optional(),
          to: day.optional(),
          pdvId: id.optional(),
          sellerId: id.optional(),
          regionId: id.optional(),
          groupId: id.optional(),
          productId: id.optional(),
          family: z.string().trim().min(1).max(80).optional(),
          status: z.enum(["ACTIVE", "VOIDED"]).optional(),
        }),
        q,
      ),
    );
  }
  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get("days")
  days(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.sales.days(
      r.actor,
      parse(
        z.object({
          from: day,
          to: day,
          pdvId: id.optional(),
          sellerId: id.optional(),
        }),
        q,
      ),
    );
  }
  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get(":id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.sales.get(r.actor, parse(id, i));
  }
  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Post(":id/correct")
  correct(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.sales.correct(r.actor, parse(id, i), parse(Correct, b));
  }
}
