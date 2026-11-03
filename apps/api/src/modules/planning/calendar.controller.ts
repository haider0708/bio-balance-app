import {
  Controller,
  Get,
  Header,
  NotFoundException,
  Param,
  Req,
} from "@nestjs/common";
import { type AuthRequest, Public } from "../../core/http";
import { AuthService } from "../auth/auth.service";
import { tokenHash } from "../auth/codes";
import { PlanningService } from "./planning.service";

/** The calendar a responsable adds to their calendar app. The secret link is the key: no sign-in. */
@Controller()
export class CalendarController {
  constructor(
    private readonly planning: PlanningService,
    private readonly auth: AuthService,
  ) {}

  @Public()
  @Get("cal/:file")
  @Header("Content-Type", "text/calendar; charset=utf-8")
  // Never kept by a cache or a proxy in between (Cloudflare included): it is somebody's schedule.
  @Header("Cache-Control", "private, no-store, no-transform")
  @Header("Referrer-Policy", "no-referrer")
  async feed(@Req() req: AuthRequest, @Param("file") file: string) {
    await this.auth.throttle(`cal:${tokenHash(req.ip ?? "unknown")}`, 240);
    const match = /^([A-Za-z0-9_-]{43})\.ics$/.exec(file);
    const calendar = match ? await this.planning.calendar(match[1]!) : null;
    if (calendar === null) throw new NotFoundException();
    return calendar;
  }
}
