import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Query,
  Req,
} from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { RestockService } from "./restock.service";

const id = z.uuid();
const qty = z.number().int().min(0).max(100_000);
const positive = z.number().int().min(1).max(100_000);
const Lines = (q: z.ZodNumber) =>
  z
    .array(z.object({ productId: id, quantity: q }))
    .min(1)
    .max(300);
const Note = z.string().trim().max(500);

const Create = z.object({
  destId: id,
  note: Note.optional(),
  lines: Lines(positive),
  photoIds: z.array(id).max(5).optional(),
});
const Assign = z.object({ depotId: id, lines: Lines(positive).optional() });
const Direct = z.object({ lines: Lines(positive).optional() });
const Ship = z.object({ lines: Lines(qty) });
const Receiver = z.object({ userId: id.nullable() });
const Receive = z.object({
  photoId: id.optional(),
  photoIds: z.array(id).max(5).optional(),
  note: Note.optional(),
  lines: Lines(qty),
});
const Approve = z.object({
  lines: Lines(qty).optional(),
  note: Note.optional(),
});
const Reason = z.object({ note: Note.min(2) });
const Status = z.enum([
  "REQUESTED",
  "ASSIGNED",
  "SHIPPED",
  "RECEIVED",
  "COMPLETED",
  "CANCELLED",
]);

@Controller("v1/restocks")
export class RestockController {
  constructor(private readonly restocks: RestockService) {}

  @Roles("ADMIN", "RESPONSABLE")
  @Post()
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.restocks.create(r.actor, parse(Create, b));
  }
  @Get()
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.restocks.list(
      r.actor,
      parse(
        z.object({
          status: Status.optional(),
          regionId: id.optional(),
          destId: id.optional(),
          active: z.stringbool().optional(),
        }),
        q,
      ),
    );
  }
  @Get(":id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.restocks.get(r.actor, parse(id, i));
  }
  @Roles("ADMIN")
  @Post(":id/assign")
  assign(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.assign(r.actor, parse(id, i), parse(Assign, b));
  }
  @Roles("ADMIN")
  @Post(":id/send-direct")
  sendDirect(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.restocks.sendDirect(
      r.actor,
      parse(id, i),
      parse(Direct, b ?? {}),
    );
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Post(":id/ship")
  ship(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.ship(r.actor, parse(id, i), parse(Ship, b));
  }
  @Roles("RESPONSABLE")
  @Put(":id/receiver")
  receiver(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.setReceiver(
      r.actor,
      parse(id, i),
      parse(Receiver, b).userId,
    );
  }
  @Roles("ADMIN", "RESPONSABLE", "VENDEUR")
  @Post(":id/receipt")
  receive(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.receive(r.actor, parse(id, i), parse(Receive, b));
  }
  @Roles("ADMIN")
  @Post(":id/approve")
  approve(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.approve(
      r.actor,
      parse(id, i),
      parse(Approve, b ?? {}),
    );
  }
  @Roles("ADMIN")
  @Post(":id/reject-receipt")
  reject(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.reject(r.actor, parse(id, i), parse(Reason, b).note);
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Post(":id/cancel")
  cancel(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.restocks.cancel(r.actor, parse(id, i), parse(Reason, b).note);
  }
}
