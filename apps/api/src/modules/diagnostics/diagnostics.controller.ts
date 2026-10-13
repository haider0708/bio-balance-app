import { Body, Controller, Get, Post, Req } from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Public, Roles, parse } from "../../core/http";
import { DiagnosticsService } from "./diagnostics.service";

const Report = z.object({
  platform: z.enum(["android", "ios", "web"]),
  appVersion: z.string().trim().min(1).max(40),
  message: z.string().trim().min(1).max(500),
  stack: z.string().max(4000).default(""),
});

@Controller("v1")
export class DiagnosticsController {
  constructor(private readonly diagnostics: DiagnosticsService) {}

  /** Sent by the app without signing in, so a report never says who met the error. */
  @Public()
  @Post("client-errors")
  report(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.diagnostics.report(parse(Report, body), r.ip ?? "unknown");
  }

  @Roles("ADMIN")
  @Get("client-errors")
  list(@Req() r: AuthRequest) {
    return this.diagnostics.list(r.actor);
  }
}
