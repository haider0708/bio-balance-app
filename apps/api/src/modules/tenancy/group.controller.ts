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
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { GroupRequests, groupListQuery } from "./group.contracts";
import { GroupService } from "./group.service";
@ApiTags("groups")
@ApiBearerAuth()
@Controller("v1/groups")
export class GroupController {
  constructor(private readonly service: GroupService) {}
  @Get() list(@Req() r: AuthRequest, @Query() raw: unknown) {
    const q = groupListQuery.parse(raw);
    return this.service.list(r.actor, q.after, q.search);
  }
  @Post() create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.create(r.actor, GroupRequests.Create.parse(b));
  }
  @Patch(":id") update(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.update(
      r.actor,
      z.uuid().parse(id),
      GroupRequests.Update.parse(b),
    );
  }
  @Get(":id/stores") stores(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.stores(r.actor, z.uuid().parse(id));
  }
  @Get(":id/team") team(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.team(r.actor, z.uuid().parse(id));
  }
  @Patch(":id/team/:userId") member(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Param("userId") userId: string,
    @Body() b: unknown,
  ) {
    return this.service.member(
      r.actor,
      z.uuid().parse(id),
      z.uuid().parse(userId),
      GroupRequests.Member.parse(b),
    );
  }
}
