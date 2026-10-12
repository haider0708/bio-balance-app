import { ApnsTransport, type PushTransport } from "./apns";
import { FcmTransport } from "./fcm";

export type PushPlatform = "IOS" | "ANDROID";

/** The push services this server is set up for; a platform without its key gets none. */
export type PushTransports = Partial<Record<PushPlatform, PushTransport>>;

export function transportsFromEnv(
  env: NodeJS.ProcessEnv = process.env,
): PushTransports {
  const ios = ApnsTransport.fromEnv(env);
  const android = FcmTransport.fromEnv(env);
  return { ...(ios && { IOS: ios }), ...(android && { ANDROID: android }) };
}

/** Whether this server sends push alerts to that platform (the phone then stops its own check). */
export const pushConfigured = (
  platform: PushPlatform,
  env: NodeJS.ProcessEnv = process.env,
) =>
  platform === "IOS"
    ? Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_KEY_P8)
    : Boolean(env.FCM_SERVICE_ACCOUNT);
