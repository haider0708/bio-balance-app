import { Body, Controller, Get, Post, Req } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { z } from "zod";
import { IdentityService } from "./identity.service";
import { AuthRequest, Public } from "../../shared/infrastructure/http";
const email = z.email().transform((e) => e.trim().toLowerCase());
const password = z.string().min(12).max(128);
@ApiTags("identity")
@ApiBearerAuth()
@Controller("v1/identity")
export class IdentityController {
  constructor(private readonly service: IdentityService) {}
  @Public() @Post("login") login(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    const v = z
      .object({
        email,
        password: z.string().min(1).max(128),
        otp: z.string().optional(),
      })
      .parse(raw);
    return this.service.login(v.email, v.password, v.otp, req.ip ?? "unknown");
  }
  @Get("me") me(@Req() req: AuthRequest) {
    return req.actor;
  }
  @Post("logout") logout(@Req() req: AuthRequest) {
    return this.service.logout(req.bearer);
  }
  @Post("invitations") invite(@Req() req: AuthRequest, @Body() raw: unknown) {
    return this.service.invite(
      req.actor,
      z
        .object({
          email,
          organizationId: z.uuid().optional(),
          organizationName: z.string().min(2).max(120).optional(),
          storeId: z.uuid().optional(),
          permissions: z
            .array(z.enum(["sell", "receive", "manage"]))
            .min(1)
            .default(["sell", "receive"]),
        })
        .parse(raw),
    );
  }
  @Public() @Post("activate") activate(@Body() raw: unknown) {
    const v = z
      .object({
        token: z.string().min(32).max(256),
        name: z.string().trim().min(2).max(120),
        password,
      })
      .parse(raw);
    return this.service.activate(v.token, v.name, v.password);
  }
  @Public() @Post("forgot-password") forgot(
    @Body() raw: unknown,
    @Req() req: AuthRequest,
  ) {
    return this.service.forgot(
      z.object({ email }).parse(raw).email,
      req.ip ?? "unknown",
    );
  }
  @Public() @Post("reset-password") reset(@Body() raw: unknown) {
    const v = z
      .object({ token: z.string().min(32).max(256), password })
      .parse(raw);
    return this.service.reset(v.token, v.password);
  }
}
