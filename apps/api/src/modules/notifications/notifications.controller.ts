import {
  Body,
  Delete,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { NotificationsService } from "./notifications.service";
@ApiTags("notifications")
@ApiBearerAuth()
@Controller("v1")
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}
  @Get("notifications") list(
    @Req() r: AuthRequest,
    @Query("before") before?: string,
  ) {
    return this.service.list(
      r.actor,
      z.iso.datetime().optional().parse(before),
    );
  }
  @Patch("notifications/:id/read") read(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.read(r.actor, z.uuid().parse(id));
  }
  @Delete('devices') removeDevice(@Req() r:AuthRequest,@Body() body:unknown){
    return this.service.removeDevice(r.actor,z.object({token:z.string().min(20).max(4096)}).parse(body).token);
  }
  @Post("devices") device(@Req() r: AuthRequest, @Body() body: unknown) {
    const v = z
      .object({
        token: z.string().min(20).max(4096),
        platform: z.enum(["android", "ios"]),
      })
      .parse(body);
    return this.service.device(r.actor, v.token, v.platform);
  }
  @Post("stores/:store/announcements") announce(
    @Req() r: AuthRequest,
    @Param("store") store: string,
    @Query("organizationId") org: string,
    @Body() body: unknown,
  ) {
    const v = z
      .object({
        title: z.string().trim().min(2).max(120),
        body: z.string().trim().min(2).max(2000),
        audience: z.enum(["all", "salespeople"]),
      })
      .strict()
      .parse(body);
    return this.service.announce(
      r.actor,
      z.uuid().parse(org),
      z.uuid().parse(store),
      v.title,
      v.body,
      v.audience,
    );
  }
}
