import { Controller, Get, Param, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { DashboardService } from "./dashboard.service";
import { dashboardQuery } from "./dashboard.contracts";
@ApiTags("dashboards")
@ApiBearerAuth()
@Controller("v1/dashboards")
export class DashboardController {
  constructor(private readonly service: DashboardService) {}
  @Get() get(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.get(r.actor, dashboardQuery.parse(q));
  }
  @Get("orders") orders(
    @Req() r: AuthRequest,
    @Query() q: unknown,
    @Query("after") after?: string,
    @Query("phase") phase?: string,
  ) {
    return this.service.orders(
      r.actor,
      dashboardQuery.parse(q),
      z.uuid().optional().parse(after),
      z.enum(["preparation", "transit", "complete"]).optional().parse(phase),
    );
  }
  @Get("attention") attention(
    @Req() r: AuthRequest,
    @Query() q: unknown,
    @Query("kind") kind: string,
    @Query("after") after?: string,
  ) {
    return this.service.attention(
      r.actor,
      dashboardQuery.parse(q),
      z.enum(["low_stock", "expired", "deliveries", "rewards"]).parse(kind),
      z.uuid().optional().parse(after),
    );
  }
  @Get("sales") sales(
    @Req() r: AuthRequest,
    @Query() q: unknown,
    @Query("after") after?: string,
  ) {
    return this.service.sales(
      r.actor,
      dashboardQuery.parse(q),
      z.uuid().optional().parse(after),
    );
  }
  @Get("groups/:groupId/stores/:storeId/orders/:id") order(
    @Req() r: AuthRequest,
    @Param("groupId") groupId: string,
    @Param("storeId") storeId: string,
    @Param("id") id: string,
  ) {
    return this.service.order(
      r.actor,
      z.uuid().parse(groupId),
      z.uuid().parse(storeId),
      z.uuid().parse(id),
    );
  }
}
