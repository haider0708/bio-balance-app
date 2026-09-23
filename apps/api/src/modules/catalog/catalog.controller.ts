import { CatalogRequests } from "../../shared/contracts/requests";
import { Body, Controller, Post, Req, Get, Query } from "@nestjs/common";
import { z } from "zod";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { AuthRequest } from "../../shared/infrastructure/http";
import { CatalogService } from "./catalog.service";

@ApiTags("catalog")
@ApiBearerAuth()
@Controller("v1/catalog")
export class CatalogController {
  constructor(private readonly service: CatalogService) {}
  @Get("products") list(@Req() r: AuthRequest, @Query("after") after?: string) {
    return this.service.list(r.actor, z.uuid().optional().parse(after));
  }
  @Post("products") save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(r.actor, CatalogRequests.Save.parse(b));
  }
  @Post("import") import(@Req() r: AuthRequest, @Body() b: unknown) {
    const input = CatalogRequests.Import.parse(b);
    return this.service.import(r.actor, input.rows, input.commit);
  }
}
