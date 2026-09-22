import { Controller, Get, Query, Param, Req, Res } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { Response } from "express";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { ReportingService } from "./reporting.service";
@ApiTags("reporting")
@ApiBearerAuth()
@Controller("v1/reports")
export class ReportingController {
  constructor(private readonly service: ReportingService) {}
  @Get("overview") overview(@Req() r: AuthRequest) {
    return this.service.overview(r.actor);
  }
  @Get("stores/:store/sales.csv") async export(
    @Req() r: AuthRequest,
    @Param("store") store: string,
    @Query("organizationId") org: string,
    @Query("after") after: string | undefined,
    @Res() res: Response,
  ) {
    const csv = await this.service.salesCsv(
      r.actor,
      z.uuid().parse(org),
      z.uuid().parse(store),
      z.uuid().optional().parse(after),
    );
    res.setHeader("Content-Disposition", 'attachment; filename="ventes.csv"');
    res.type("text/csv; charset=utf-8").send(csv);
  }
}
