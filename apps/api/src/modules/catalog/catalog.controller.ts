import { Body, Controller, Post, Req } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { CatalogService } from "./catalog.service";
const product = z
  .object({
    id: z.uuid().optional(),
    reference: z.string().trim().min(1).max(80),
    name: z.string().trim().min(2).max(160),
    barcode: z.string().trim().min(3).max(80).optional(),
    description: z.string().max(5000).default(""),
    active: z.boolean().default(true),
    expectedVersion: z.number().int().positive().optional(),
  })
  .strict();
@ApiTags("catalog")
@ApiBearerAuth()
@Controller("v1/catalog")
export class CatalogController {
  constructor(private readonly service: CatalogService) {}
  @Post("products") save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(r.actor, product.parse(b));
  }
  @Post("import") import(@Req() r: AuthRequest, @Body() b: unknown) {
    const input = z
      .object({
        rows: z
          .array(product.omit({ id: true, expectedVersion: true }))
          .min(1)
          .max(1000),
        commit: z.boolean().default(false),
      })
      .strict()
      .parse(b);
    return this.service.import(r.actor, input.rows, input.commit);
  }
}
