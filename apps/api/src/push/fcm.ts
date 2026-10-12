import { createPrivateKey, type KeyObject, sign } from "node:crypto";
import type {
  PushDeviceTarget,
  PushMessage,
  PushOutcome,
  PushTransport,
} from "./apns";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
/** The channel the app creates on the phone (lib/core/alerts/background_alerts.dart). */
const CHANNEL = "biobalance_alerts";
/** The small white leaf in the status bar (android drawable) and the brand colour of the shade. */
const ICON = "ic_stat_biobalance";
const COLOR = "#0C6B45";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri: string;
}

type Fetch = typeof fetch;

const b64url = (data: Buffer | string) =>
  Buffer.from(data).toString("base64url");

/**
 * Firebase Cloud Messaging (HTTP v1) for Android phones, signed in with a service account:
 * no third-party library, one pooled HTTPS connection set, and a cached access token.
 * Configured with FCM_SERVICE_ACCOUNT (the downloaded JSON key, base64 encoded).
 */
export class FcmTransport implements PushTransport {
  private readonly key: KeyObject;
  private token?: { value: string; expiresAt: number };
  private signingIn?: Promise<string>;

  constructor(
    private readonly account: ServiceAccount,
    private readonly http: Fetch = fetch,
  ) {
    this.key = createPrivateKey(account.private_key);
  }

  static fromEnv(env: NodeJS.ProcessEnv = process.env): FcmTransport | null {
    if (!env.FCM_SERVICE_ACCOUNT) return null;
    const account = JSON.parse(
      Buffer.from(env.FCM_SERVICE_ACCOUNT, "base64").toString("utf8"),
    ) as ServiceAccount;
    return new FcmTransport(account);
  }

  /** A Google access token, valid an hour; renewed five minutes before it ends, once at a time. */
  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt - Date.now() > 300_000)
      return this.token.value;
    this.signingIn ??= this.signIn().finally(
      () => (this.signingIn = undefined),
    );
    return this.signingIn;
  }

  private async signIn(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(
      JSON.stringify({
        iss: this.account.client_email,
        scope: SCOPE,
        aud: this.account.token_uri,
        iat: now,
        exp: now + 3600,
      }),
    )}`;
    const assertion = `${unsigned}.${b64url(sign("RSA-SHA256", Buffer.from(unsigned), this.key))}`;
    const response = await this.http(this.account.token_uri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`FCM_SIGN_IN_${response.status}`);
    const body = (await response.json()) as {
      access_token: string;
      expires_in: number;
    };
    this.token = {
      value: body.access_token,
      expiresAt: Date.now() + body.expires_in * 1000,
    };
    return body.access_token;
  }

  /** The request body for one phone: Android shows it by itself, even with the app closed. */
  static body(device: PushDeviceTarget, message: PushMessage) {
    return {
      message: {
        token: device.token,
        notification: { title: message.title, body: message.body },
        // Tapping the alert opens the app, which opens the notifications.
        data: { route: "notifications" },
        android: {
          priority: "HIGH",
          // An alert not delivered within a day is noise.
          ttl: "86400s",
          notification: {
            channel_id: CHANNEL,
            icon: ICON,
            color: COLOR,
            default_sound: true,
            ...(message.badge > 0 && { notification_count: message.badge }),
          },
        },
      },
    };
  }

  async send(
    device: PushDeviceTarget,
    message: PushMessage,
  ): Promise<PushOutcome> {
    const body = JSON.stringify(FcmTransport.body(device, message));
    const url = `https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const response = await this.http(url, {
          method: "POST",
          headers: {
            authorization: `Bearer ${await this.accessToken()}`,
            "content-type": "application/json",
          },
          body,
          signal: AbortSignal.timeout(10_000),
        });
        if (response.ok) return "sent";
        const error = (await response.json().catch(() => ({}))) as {
          error?: {
            status?: string;
            message?: string;
            details?: { errorCode?: string }[];
          };
        };
        const code =
          error.error?.details?.find((d) => d.errorCode)?.errorCode ??
          error.error?.status;
        // The phone no longer has the app, or the token is not one of this project's. A
        // malformed message of ours is also "invalid argument": only a bad token forgets the phone.
        if (
          response.status === 404 ||
          ["UNREGISTERED", "SENDER_ID_MISMATCH"].includes(String(code)) ||
          (code === "INVALID_ARGUMENT" &&
            /registration token/i.test(error.error?.message ?? ""))
        )
          return "gone";
        // An expired or refused access token: sign in again and retry at once.
        if (response.status === 401 || response.status === 403)
          this.token = undefined;
        else if (response.status !== 429 && response.status < 500) {
          console.error(
            JSON.stringify({
              level: "error",
              code: "PUSH_FAILED",
              platform: "ANDROID",
              status: response.status,
              reason: code,
            }),
          );
          return "failed";
        }
      } catch {
        // Network trouble: try again.
      }
      if (attempt < 3) await new Promise((r) => setTimeout(r, attempt * 400));
    }
    console.error(
      JSON.stringify({
        level: "error",
        code: "PUSH_FAILED",
        platform: "ANDROID",
      }),
    );
    return "failed";
  }

  close() {}
}
