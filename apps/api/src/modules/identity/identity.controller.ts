import { IdentityRequests } from "../../shared/contracts/requests";
import { Body, Controller, Get, Post, Req } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { IdentityService } from "./identity.service";
import { AuthRequest, Public } from "../../shared/infrastructure/http";

@ApiTags("identity")
@ApiBearerAuth()
@Controller("v1/identity")
export class IdentityController {
  constructor(private readonly service: IdentityService) {}
  @Public() @Post("login") login(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    const v = IdentityRequests.Login.parse(raw);
    return this.service.login(v.email, v.password, v.otp, req.ip ?? "unknown");
  }
  @Get("me") me(@Req() req: AuthRequest) {
    return req.actor;
  }
  @Post("logout") logout(@Req() req: AuthRequest) {
    return this.service.logout(req.bearer);
  }
  @Post("invitations") invite(@Req() req: AuthRequest, @Body() raw: unknown) {
    return this.service.invite(req.actor, IdentityRequests.Invite.parse(raw));
  }
  @Public() @Post("activate") activate(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    const v = IdentityRequests.Activate.parse(raw);
    return this.service.activate(
      v.token,
      v.name,
      v.password,
      req.ip ?? "unknown",
    );
  }
  @Public() @Post("forgot-password") forgot(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    return this.service.forgot(
      IdentityRequests.Forgot.parse(raw).email,
      req.ip ?? "unknown",
    );
  }
  @Public() @Post("reset-password") reset(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    const v = IdentityRequests.Reset.parse(raw);
    return this.service.reset(v.token, v.password, req.ip ?? "unknown");
  }
}
