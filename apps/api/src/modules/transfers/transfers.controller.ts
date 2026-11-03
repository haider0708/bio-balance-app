import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { TransfersService } from "./transfers.service";

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
const Create = z.object({
  fromPdvId: id,
  toPdvId: id,
  direction: z.enum(["SEND", "REQUEST"]).default("SEND"),
  lines: Lines,
  photoId: id.optional(),
  note: z.string().trim().max(300).optional(),
});

@Controller("v1/transfers")
export class TransfersController {
  constructor(private readonly transfers: TransfersService) {}

  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get()
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.transfers.list(
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

  // Before ":id", so "partners" is not read as an id.
  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get("partners")
  partners(@Req() r: AuthRequest, @Query("pdvId") pdvId?: string) {
    return this.transfers.partners(r.actor, parse(id.optional(), pdvId));
  }

  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Post()
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.transfers.create(r.actor, parse(Create, b));
  }

  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Get(":id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.transfers.get(r.actor, parse(id, i));
  }

  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Post(":id/edit")
  edit(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.transfers.edit(
      r.actor,
      parse(id, i),
      parse(z.object({ lines: Lines }), b),
    );
  }

  @Roles("VENDEUR", "RESPONSABLE", "ADMIN")
  @Post(":id/cancel")
  cancel(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.transfers.cancel(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post(":id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.transfers.approve(
      r.actor,
      parse(id, i),
      parse(
        z.object({
          note: z.string().trim().max(300).optional(),
          lines: Lines.optional(),
        }),
        b ?? {},
      ),
    );
  }

  @Roles("ADMIN")
  @Post(":id/reject")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.transfers.reject(
      r.actor,
      parse(id, i),
      parse(z.object({ note: z.string().trim().min(2).max(300) }), b),
    );
  }
}
