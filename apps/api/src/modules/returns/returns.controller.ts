import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { ReturnsService } from "./returns.service";

const id = z.uuid();
const Lines = z
  .array(
    z.object({
      productId: id,
      quantity: z.number().int().min(1).max(100_000),
    }),
  )
  .min(1)
  .max(30);

@Controller("v1/returns")
export class ReturnsController {
  constructor(private readonly returns: ReturnsService) {}

  @Roles("RESPONSABLE", "ADMIN", "ORDERS")
  @Get()
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.returns.list(
      r.actor,
      parse(
        z.object({
          status: z
            .enum(["PENDING", "APPROVED", "REJECTED", "CANCELLED", "EXPIRED"])
            .optional(),
          pdvId: id.optional(),
        }),
        q,
      ),
    );
  }

  @Roles("RESPONSABLE", "ADMIN")
  @Post()
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.returns.create(
      r.actor,
      parse(
        z.object({
          pdvId: id,
          action: z.enum(["REMOVE", "MOVE", "ADD"]).default("REMOVE"),
          toPdvId: id.optional(),
          lines: Lines,
          note: z.string().trim().max(300).optional(),
        }),
        b,
      ),
    );
  }

  @Roles("RESPONSABLE", "ADMIN", "ORDERS")
  @Get(":id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.returns.get(r.actor, parse(id, i));
  }

  @Roles("RESPONSABLE", "ADMIN")
  @Post(":id/edit")
  edit(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.returns.edit(
      r.actor,
      parse(id, i),
      parse(z.object({ lines: Lines }), b),
    );
  }

  @Roles("RESPONSABLE", "ADMIN")
  @Post(":id/cancel")
  cancel(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.returns.cancel(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post(":id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.returns.approve(
      r.actor,
      parse(id, i),
      parse(
        z.object({
          note: z.string().trim().max(300).optional(),
          lines: Lines.optional(),
          toPdvId: id.optional(),
        }),
        b ?? {},
      ),
    );
  }

  @Roles("ADMIN")
  @Post(":id/reject")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.returns.reject(
      r.actor,
      parse(id, i),
      parse(z.object({ note: z.string().trim().min(2).max(300) }), b),
    );
  }
}
