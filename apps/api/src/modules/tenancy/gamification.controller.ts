import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { GamificationRequests } from "./gamification.contracts";
import { GamificationService } from "./gamification.service";

const uuid = z.uuid();

@ApiTags("gamification")
@ApiBearerAuth()
@Controller("v1/gamification")
export class GamificationController {
  constructor(private readonly service: GamificationService) {}
  @Get("defaults") defaults(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.defaults(r.actor, q);
  }
  @Post("points-defaults") pointsDefault(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.setPointsDefault(
      r.actor,
      GamificationRequests.PointsDefault.parse(b),
    );
  }
  @Post("reward-templates") rewardTemplate(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.saveRewardTemplate(
      r.actor,
      GamificationRequests.RewardTemplate.parse(b),
    );
  }
  @Get("stores/:store/points") storePoints(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
  ) {
    return this.service.storePoints(r.actor, uuid.parse(o), uuid.parse(s));
  }
  @Post("stores/:store/points") setStorePoints(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
    @Body() b: unknown,
  ) {
    return this.service.setStorePoints(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      GamificationRequests.StorePoints.parse(b),
    );
  }
}
