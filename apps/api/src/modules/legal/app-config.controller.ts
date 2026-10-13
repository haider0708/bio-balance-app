import { Controller, Get, Header } from "@nestjs/common";
import { Public } from "../../core/http";

const PLAY_STORE =
  "https://play.google.com/store/apps/details?id=tn.biobalance.app";

/**
 * What the phones check when they start: the oldest build still allowed (older ones show an
 * "Update required" screen with a link to their store). Set on the server: MIN_APP_BUILD (the
 * number after "+" in the app's version), IOS_STORE_URL once the App Store page exists.
 */
@Controller("v1")
export class AppConfigController {
  @Public()
  @Get("app-config")
  @Header("Cache-Control", "no-store")
  config() {
    return {
      minimumBuild: Math.max(0, Number(process.env.MIN_APP_BUILD) || 0),
      stores: {
        android: process.env.PLAY_STORE_URL || PLAY_STORE,
        ios: process.env.IOS_STORE_URL || null,
      },
    };
  }
}
