import { Body, Controller, Get, Put, Req } from "@nestjs/common";
import { type AuthRequest, Roles, parse } from "./http";
import { SettingsPatch, SettingsService } from "./settings";
import { isOpenAt, nextOpening } from "./hours";
import { WhatsAppStatus } from "../whatsapp/status";

@Controller("v1/settings")
export class SettingsController {
  constructor(
    private readonly settings: SettingsService,
    private readonly whatsapp: WhatsAppStatus,
  ) {}

  @Roles("ADMIN")
  @Get()
  async get() {
    const value = await this.settings.get();
    const now = new Date();
    return {
      ...value,
      whatsapp: { ...value.whatsapp, status: await this.whatsapp.status() },
      // The server's own clock, so the admin sees what the phones will be told.
      now: now.toISOString(),
      open: isOpenAt(value.hours, now),
      nextOpening: nextOpening(value.hours, now)?.at ?? null,
    };
  }

  @Roles("ADMIN")
  @Put()
  async update(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.settings.update(r.actor, parse(SettingsPatch, body));
  }
}
