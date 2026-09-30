import { Body, Controller, Get, Post, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthRequest } from "../../shared/infrastructure/http";
import { PricingRequests } from "./pricing.contracts";
import { PricingService } from "./pricing.service";

@ApiTags("pricing")
@ApiBearerAuth()
@Controller("v1/prices")
export class PricingController {
  constructor(private readonly service: PricingService) {}
  @Get("current") current(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.current(r.actor, q);
  }
  @Get("history") history(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.history(r.actor, q);
  }
  @Post() set(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.service.set(r.actor, PricingRequests.Set.parse(body));
  }
}
