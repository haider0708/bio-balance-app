import { Controller, Get, Post, Body, Param, Req, Res } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Response } from "express";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { exportQuery } from "./export.contracts";
import { ExportService } from "./export.service";
export const exportRequest = z
  .object({ id: z.uuid(), query: exportQuery })
  .strict();
@ApiTags("reporting")
@ApiBearerAuth()
@Controller("v1/report-exports")
export class ExportController {
  constructor(private readonly service: ExportService) {}
  @Post() create(@Req() r: AuthRequest, @Body() body: unknown) {
    const input = exportRequest.parse(body);
    return this.service.create(r.actor, input.id, input.query);
  }
  @Get(":id") get(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.get(r.actor, z.uuid().parse(id));
  }
  @Get(":id/file") async file(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Res() res: Response,
  ) {
    const file = await this.service.download(r.actor, z.uuid().parse(id));
    res.setHeader("Cache-Control", "no-store");
    res.setHeader(
      "Content-Disposition",
      'attachment; filename="ventes-biobalance.csv"',
    );
    res.type("text/csv").sendFile(file);
  }
}
