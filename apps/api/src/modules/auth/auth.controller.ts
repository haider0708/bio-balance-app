import { Body, Controller, Get, Patch, Post, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Public, parse } from "../../core/http";
import { AuthService } from "./auth.service";

const email = z.string().trim().toLowerCase().pipe(z.email());
const password = z.string().min(10).max(128);

const Login = z.object({
  email,
  password: z.string().min(1).max(128),
  otp: z.string().optional(),
});
const Activate = z.object({
  email,
  code: z.string().min(8).max(12),
  name: z.string().trim().min(2).max(100).optional(),
  password,
});
const Forgot = z.object({ email });
const Reset = z.object({ email, code: z.string().min(8).max(12), password });
const Profile = z.object({
  name: z.string().trim().min(2).max(100).optional(),
  phone: z.string().trim().max(30).nullable().optional(),
  locale: z.enum(["fr", "en"]).optional(),
});
const ChangePassword = z.object({
  current: z.string().min(1).max(128),
  next: password,
});

@Controller("v1")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post("auth/login")
  login(@Body() raw: unknown, @Req() req: AuthRequest) {
    const v = parse(Login, raw);
    return this.auth.login(v.email, v.password, v.otp, req.ip ?? "unknown");
  }

  @Post("auth/logout")
  logout(@Req() req: AuthRequest) {
    return this.auth.logout(req.bearer);
  }

  @Public()
  @Post("auth/activate")
  activate(@Body() raw: unknown, @Req() req: AuthRequest) {
    const v = parse(Activate, raw);
    return this.auth.activate(
      v.email,
      v.code,
      v.name,
      v.password,
      req.ip ?? "unknown",
    );
  }

  @Public()
  @Post("auth/forgot-password")
  forgot(@Body() raw: unknown, @Req() req: AuthRequest) {
    return this.auth.forgot(parse(Forgot, raw).email, req.ip ?? "unknown");
  }

  @Public()
  @Post("auth/reset-password")
  reset(@Body() raw: unknown, @Req() req: AuthRequest) {
    const v = parse(Reset, raw);
    return this.auth.reset(v.email, v.code, v.password, req.ip ?? "unknown");
  }

  @Get("me")
  me(@Req() req: AuthRequest) {
    return this.auth.me(req.actor.id);
  }

  @Patch("me")
  update(@Req() req: AuthRequest, @Body() raw: unknown) {
    return this.auth.updateProfile(req.actor, parse(Profile, raw));
  }

  @Post("me/password")
  password(@Req() req: AuthRequest, @Body() raw: unknown) {
    const v = parse(ChangePassword, raw);
    return this.auth.changePassword(req.actor, v.current, v.next);
  }
}
