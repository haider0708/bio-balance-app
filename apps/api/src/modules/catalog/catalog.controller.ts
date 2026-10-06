import { Body, Controller, Get, Param, Patch, Post, Query, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { CatalogService } from "./catalog.service";

const id = z.uuid();
const str = (max: number) => z.string().trim().max(max);
const Product = z.object({
  reference: str(40).min(1),
  name: str(160).min(1),
  barcode: str(32).nullable().optional(),
  family: str(80).min(1),
  range: str(80).optional(),
  packageSize: str(40).optional(),
  description: str(8000).optional(),
  instructions: str(4000).optional(),
  ingredients: str(4000).optional(),
  precautions: str(4000).optional(),
  imageId: id.nullable().optional(),
  active: z.boolean().optional(),
});

@Controller("v1")
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get("products")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.catalog.list(r.actor, parse(
      z.object({ q: str(80).optional(), family: str(80).optional(), includeInactive: z.stringbool().optional() }), q));
  }
  @Get("products/families") families() {
    return this.catalog.families();
  }
  @Get("products/barcode/:code") barcode(@Param("code") code: string) {
    return this.catalog.byBarcode(parse(str(32).min(4), code));
  }
  @Get("products/:id") get(@Param("id") i: string) {
    return this.catalog.get(parse(id, i));
  }
  @Roles("ADMIN") @Post("products")
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.catalog.create(r.actor, parse(Product, b));
  }
  @Roles("ADMIN") @Post("products/import")
  import(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.catalog.importMany(r.actor, parse(z.object({ items: z.array(Product).min(1).max(500) }), b).items);
  }
  @Roles("ADMIN") @Patch("products/:id")
  update(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.catalog.update(r.actor, parse(id, i), parse(Product.partial(), b));
  }
}
