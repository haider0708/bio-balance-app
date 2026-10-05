import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { WholesaleRequests } from "./wholesale.contracts";
import { WholesaleService } from "./wholesale.service";
import { GamificationService } from "../tenancy/gamification.service";

@ApiTags("wholesale")
@ApiBearerAuth()
@Controller("v1")
export class WholesaleController {
  constructor(
    private readonly service: WholesaleService,
    private readonly gamification: GamificationService,
  ) {}
  @Get("wholesalers") list(@Req() r: AuthRequest) {
    return this.service.list(r.actor);
  }
  @Post("wholesalers") async create(
    @Req() r: AuthRequest,
    @Body() body: unknown,
  ) {
    const created = await this.service.create(
      r.actor,
      WholesaleRequests.Create.parse(body),
    );
    // A new depot starts with BioBalance's default points and rewards.
    if (created.storeId)
      await this.gamification.applyDefaults(
        r.actor,
        created.id,
        created.storeId,
      );
    return created;
  }
  @Get("supplier/orders") orders(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.orders(r.actor, q);
  }
  @Get("supplier/orders/:id") order(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Query() q: unknown,
  ) {
    return this.service.order(r.actor, z.uuid().parse(id), q);
  }
}
