import { Controller, Get, Header, Query } from "@nestjs/common";
import { Public } from "../../core/http";
import { SettingsService } from "../../core/settings";

/**
 * What the phones check when they start: the oldest build still allowed (older ones show an
 * "Update required" screen with a link to their store). The admin sets it in the app (Settings);
 * until then MIN_APP_BUILD and IOS_STORE_URL on the server apply. A phone says which platform it
 * is (`?platform=ios|android`) and gets its own minimum; an older app that does not gets the
 * lower of the two (so it is only forced when both stores have the new version).
 */
@Controller("v1")
export class AppConfigController {
  constructor(private readonly settings: SettingsService) {}

  @Public()
  @Get("app-config")
  @Header("Cache-Control", "no-store")
  async config(@Query("platform") platform?: string) {
    const { minimumBuild, stores } = await this.settings.get();
    const own =
      platform === "ios" || platform === "android"
        ? minimumBuild[platform]
        : Math.min(minimumBuild.ios, minimumBuild.android);
    return { minimumBuild: own, minimumBuilds: minimumBuild, stores };
  }
}
