import { type ClientHttp2Session, connect, constants } from "node:http2";
import { createPrivateKey, type KeyObject, sign } from "node:crypto";

export interface PushMessage {
  title: string;
  body: string;
  /** The number on the app icon. */
  badge: number;
  /** Alerts of the same kind are grouped on the lock screen. */
  thread: string;
}

export interface PushDeviceTarget {
  token: string;
  sandbox: boolean;
}

/** sent; gone = the phone no longer accepts alerts for this app (forget it); failed = try later or drop. */
export type PushOutcome = "sent" | "gone" | "failed";

export interface PushTransport {
  send(device: PushDeviceTarget, message: PushMessage): Promise<PushOutcome>;
  close(): void;
}

/** Whether this server sends push alerts (the Apple key is configured). */
export const pushConfigured = (env: NodeJS.ProcessEnv = process.env) =>
  Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_KEY_P8);

const b64url = (data: Buffer | string) =>
  Buffer.from(data).toString("base64url");

/**
 * Apple Push Notification service over HTTP/2 with a signing key (.p8), no third party.
 * Configured with APNS_KEY_ID, APNS_TEAM_ID and APNS_KEY_P8 (the .p8 file in base64);
 * APNS_TOPIC is the bundle identifier.
 */
export class ApnsTransport implements PushTransport {
  private readonly key: KeyObject;
  private jwt?: { value: string; issuedAt: number };
  private readonly sessions = new Map<string, ClientHttp2Session>();

  constructor(
    private readonly options: {
      keyId: string;
      teamId: string;
      key: string;
      topic: string;
    },
  ) {
    this.key = createPrivateKey(options.key);
  }

  static fromEnv(env: NodeJS.ProcessEnv = process.env): ApnsTransport | null {
    const { APNS_KEY_ID: keyId, APNS_TEAM_ID: teamId, APNS_KEY_P8: key } = env;
    if (!keyId || !teamId || !key) return null;
    return new ApnsTransport({
      keyId,
      teamId,
      key: Buffer.from(key, "base64").toString("utf8"),
      topic: env.APNS_TOPIC || "tn.biobalance.app",
    });
  }

  /** Apple wants a new token at most every 20 minutes and refuses ones older than an hour. */
  private bearer() {
    const now = Math.floor(Date.now() / 1000);
    if (this.jwt && now - this.jwt.issuedAt < 40 * 60) return this.jwt.value;
    const unsigned = `${b64url(JSON.stringify({ alg: "ES256", kid: this.options.keyId }))}.${b64url(
      JSON.stringify({ iss: this.options.teamId, iat: now }),
    )}`;
    const signature = sign("sha256", Buffer.from(unsigned), {
      key: this.key,
      dsaEncoding: "ieee-p1363",
    });
    this.jwt = { value: `${unsigned}.${b64url(signature)}`, issuedAt: now };
    return this.jwt.value;
  }

  private session(host: string) {
    const open = this.sessions.get(host);
    if (open && !open.closed && !open.destroyed) return open;
    const session = connect(`https://${host}`);
    const forget = () => {
      if (this.sessions.get(host) === session) this.sessions.delete(host);
    };
    session.on("error", forget);
    session.on("goaway", forget);
    session.on("close", forget);
    this.sessions.set(host, session);
    return session;
  }

  send(device: PushDeviceTarget, message: PushMessage): Promise<PushOutcome> {
    return new Promise((resolve) => {
      const host = device.sandbox
        ? "api.sandbox.push.apple.com"
        : "api.push.apple.com";
      const payload = JSON.stringify({
        aps: {
          alert: { title: message.title, body: message.body },
          badge: message.badge,
          sound: "default",
          "thread-id": message.thread,
        },
      });
      let request;
      try {
        request = this.session(host).request({
          ":method": "POST",
          ":path": `/3/device/${device.token}`,
          authorization: `bearer ${this.bearer()}`,
          "apns-topic": this.options.topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          // Not delivered after a day: an old alert is noise.
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 86_400),
          "content-type": "application/json",
        });
      } catch {
        resolve("failed");
        return;
      }
      let status = 0;
      let body = "";
      request.setTimeout(10_000, () => {
        request.close(constants.NGHTTP2_CANCEL);
        resolve("failed");
      });
      request.on("response", (headers) => {
        status = Number(headers[":status"]);
      });
      request.setEncoding("utf8");
      request.on("data", (chunk: string) => (body += chunk));
      request.on("error", () => resolve("failed"));
      request.on("end", () => {
        if (status === 200) return resolve("sent");
        let reason = "";
        try {
          reason = String((JSON.parse(body) as { reason?: string }).reason);
        } catch {
          // No readable reason.
        }
        if (
          status === 410 ||
          ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(
            reason,
          )
        )
          return resolve("gone");
        // A refused signature: make a new one next time.
        if (status === 403) this.jwt = undefined;
        console.error(
          JSON.stringify({
            level: "error",
            code: "PUSH_FAILED",
            status,
            reason,
          }),
        );
        resolve("failed");
      });
      request.end(payload);
    });
  }

  close() {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
  }
}
