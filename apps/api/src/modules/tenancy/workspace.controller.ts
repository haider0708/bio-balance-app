import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { WorkspaceService } from "./workspace.service";
const uuid = z.uuid();
const name = z.string().trim().min(2).max(120);
@ApiTags("stores")
@ApiBearerAuth()
@Controller("v1")
export class WorkspaceController {
  constructor(private readonly service: WorkspaceService) {}
  @Get("organizations") organizations(@Req() r: AuthRequest) {
    return this.service.organizations(r.actor);
  }
  @Get("stores") stores(@Req() r: AuthRequest) {
    return this.service.stores(r.actor);
  }
  @Post("stores") create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.createStore(
      r.actor,
      z
        .object({
          organizationId: uuid,
          name,
          address: z.string().trim().min(3).max(300),
          city: name,
          phone: z.string().max(30).optional(),
        })
        .strict()
        .parse(b),
    );
  }
  @Get("stores/:store/snapshot") snapshot(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
    @Query("after") after?: string,
    @Query("catalogRevision") catalogRevision?: string,
    @Query("protocol") protocol?: string,
    @Query("acknowledgments") acknowledgments?: string,
  ) {
    const since = after !== undefined && catalogRevision !== undefined ? {
      cursor:z.string().regex(/^\d{1,19}$/).parse(after),
      catalogRevision:z.string().regex(/^\d+:\d+$/).parse(catalogRevision),
    } : undefined;
    return this.service.snapshot(r.actor, uuid.parse(o), uuid.parse(s), since,
      z.coerce.number().int().min(2).max(3).parse(protocol ?? 2),
      z.array(uuid).max(50).parse(acknowledgments ? acknowledgments.split(',') : []));
  }
  @Get("stores/:store/snapshot-pages/:page") snapshotPage(
    @Req() r: AuthRequest, @Param("store") store: string, @Param("page") page: string,
    @Query("organizationId") org: string,
  ) {
    return this.service.snapshotPage(r.actor, uuid.parse(org), uuid.parse(store), uuid.parse(page));
  }
  @Get("stores/:store/collections/:resource") collection(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Param("resource") resource: string,
    @Query("organizationId") o: string,
    @Query("after") after?: string,
  ) {
    return this.service.list(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      resource,
      uuid.optional().parse(after),
    );
  }
  @Get('stores/:store/history/:resource') history(@Req() r:AuthRequest,@Param('store') s:string,@Param('resource') resource:string,@Query('organizationId') o:string,@Query('productId') product?:string,@Query('before') before?:string){
    return this.service.history(r.actor,uuid.parse(o),uuid.parse(s),z.enum(['sales','points','movements','audit']).parse(resource),uuid.optional().parse(product),z.string().max(300).regex(/^[A-Za-z0-9_-]+$/).optional().parse(before));
  }
  @Get("stores/:store/sales/:sale") sale(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Param("sale") sale: string,
    @Query("organizationId") o: string,
  ) {
    return this.service.saleDetails(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      uuid.parse(sale),
    );
  }
  @Get("stores/:store/changes") changes(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
    @Query("after") after = "0",
  ) {
    return this.service.changes(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      z
        .string()
        .regex(/^\d{1,19}$/)
        .parse(after),
    );
  }
  @Get("stores/:store/ranking") ranking(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
  ) {
    return this.service.ranking(r.actor, uuid.parse(o), uuid.parse(s));
  }
  @Patch("stores/:store/products/:product") config(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Param("product") p: string,
    @Query("organizationId") o: string,
    @Body() b: unknown,
  ) {
    return this.service.configureProduct(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      uuid.parse(p),
      z
        .object({
          priceMillimes: z.string().regex(/^(0|[1-9]\d{0,14})$/),
          threshold: z.number().int().min(0).max(1_000_000),
          pointsPerUnit: z.number().int().min(0).max(100_000),
          expectedVersion: z.number().int().positive().optional(),
        })
        .strict()
        .parse(b),
    );
  }
  @Patch("stores/:store/team/:user") member(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Param("user") u: string,
    @Query("organizationId") o: string,
    @Body() b: unknown,
  ) {
    return this.service.setMember(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      uuid.parse(u),
      z
        .object({
          active: z.boolean(),
          permissions: z.array(z.enum(["sell", "receive", "manage"])).min(1),
        })
        .strict()
        .parse(b),
    );
  }
  @Patch("stores/:store/onboarding") onboarding(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
    @Body() b: unknown,
  ) {
    return this.service.onboarding(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      z.object({ step: z.number().int().min(1).max(5) }).parse(b).step,
    );
  }
  @Post("stores/:store/rewards") reward(
    @Req() r: AuthRequest,
    @Param("store") s: string,
    @Query("organizationId") o: string,
    @Body() b: unknown,
  ) {
    return this.service.reward(
      r.actor,
      uuid.parse(o),
      uuid.parse(s),
      z
        .object({
          id: uuid.optional(),
          title: name,
          description: z.string().max(2000).default(""),
          cost: z.number().int().positive().max(100_000_000),
          productId: uuid.optional(),
          quantity: z.number().int().positive().max(1_000_000).default(1),
          active: z.boolean().default(true),
          expectedVersion: z.number().int().positive().optional(),
        })
        .strict()
        .parse(b),
    );
  }
}
