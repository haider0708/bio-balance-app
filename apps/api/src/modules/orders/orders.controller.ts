import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { OrdersService } from "./orders.service";

const id = z.uuid();

/** The order manager's screens: the network's paras and what is getting low. */
@Controller("v1/orders")
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Roles("ORDERS", "ADMIN")
  @Get("overview")
  overview(@Req() r: AuthRequest) {
    return this.orders.overview(r.actor);
  }

  @Roles("ORDERS", "ADMIN")
  @Get("paras")
  paras(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.orders.paras(
      r.actor,
      parse(
        z.object({
          regionId: id.optional(),
          groupId: id.optional(),
          q: z.string().trim().max(60).optional(),
          low: z.stringbool().optional(),
        }),
        q,
      ),
    );
  }

  @Roles("ORDERS", "ADMIN")
  @Get("paras/:id")
  para(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.orders.para(r.actor, parse(id, i));
  }

  @Roles("ORDERS")
  @Post("paras/:id/ask")
  ask(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.orders.ask(
      r.actor,
      parse(id, i),
      parse(
        z.object({ message: z.string().trim().max(200).optional() }),
        b ?? {},
      ),
    );
  }
}
