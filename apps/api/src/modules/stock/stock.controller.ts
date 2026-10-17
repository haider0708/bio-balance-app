import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Put,
  Query,
  Req,
} from "@nestjs/common";
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
const Amend = z.object({
  lines: Lines,
  note: z.string().trim().max(500).optional(),
});
const Edit = z.object({
  lines: z.array(z.object({ productId: id, quantity: qty })).max(500),
  photoIds: z.array(id).max(5).optional(),
  note: z.string().trim().max(500).optional(),
  /** Required once the count is approved. */
  reason: z.string().trim().min(2).max(300).optional(),
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

  @Roles("ADMIN", "RESPONSABLE", "VENDEUR")
  @Get("locations/:id")
  levels(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.levels(r.actor, parse(id, i));
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("locations/:id/products/:productId/movements")
  movements(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Param("productId") p: string,
  ) {
    return this.stock.movements(r.actor, parse(id, i), parse(id, p));
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Post("declarations")
  declare(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.stock.declare(r.actor, parse(Declare, b));
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("declarations")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.stock.list(
      r.actor,
      parse(
        z.object({
          status: z.enum(["PENDING", "APPROVED", "REJECTED"]).optional(),
          regionId: id.optional(),
          locationId: id.optional(),
        }),
        q,
      ),
    );
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("declarations/:id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.get(r.actor, parse(id, i));
  }

  /** The responsable saves a corrected count (see StockService.edit). */
  @Roles("RESPONSABLE")
  @Put("declarations/:id")
  edit(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.edit(r.actor, parse(id, i), parse(Edit, b));
  }

  /** The responsable opens a waiting count to correct it: it goes on hold for the admin. */
  @Roles("RESPONSABLE")
  @Post("declarations/:id/edit")
  startEdit(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.startEdit(r.actor, parse(id, i));
  }

  @Roles("RESPONSABLE")
  @Delete("declarations/:id/edit")
  cancelEdit(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.cancelEdit(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post("declarations/:id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.approve(r.actor, parse(id, i), parse(Approve, b ?? {}));
  }

  /** The admin corrects an approved count, within 6 hours of approving it. */
  @Roles("ADMIN")
  @Post("declarations/:id/amend")
  amend(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    const v = parse(Amend, b);
    return this.stock.amend(r.actor, parse(id, i), v);
  }

  /** The admin puts a decided count back to waiting, within 6 hours. */
  @Roles("ADMIN")
  @Post("declarations/:id/reopen")
  reopen(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.reopen(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post("recounts/:id/reopen")
  reopenRecount(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.stock.reopenRecount(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post("declarations/:id/reject")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.stock.reject(r.actor, parse(id, i), parse(Reject, b).note);
  }

  @Roles("RESPONSABLE")
  @Post("recounts")
  requestRecount(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.stock.requestRecount(r.actor, parse(Recount, b));
  }

  @Roles("ADMIN", "RESPONSABLE")
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
