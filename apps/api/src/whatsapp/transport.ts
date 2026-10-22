import { whatsappChatId } from "../core/phone";

/** What the codes are sent through. WhatsApp only brings the code; the email always goes too. */
export interface WhatsAppTransport {
  /** Whether the number has WhatsApp (messaging numbers that do not is what gets a number banned). */
  hasWhatsApp(phone: string): Promise<boolean | null>;
  send(phone: string, text: string): Promise<void>;
  /** CONNECTED, or what is wrong (the session was lost, the QR code must be scanned again). */
  status(): Promise<"CONNECTED" | "DISCONNECTED">;
}

export interface WahaOptions {
  url: string;
  apiKey: string;
  session?: string;
  fetchImpl?: typeof fetch;
  /** Pause before each message, in milliseconds (people do not send several messages in one second). */
  gapMs?: () => number;
  sleep?: (ms: number) => Promise<void>;
}

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * WAHA, a self-hosted container that holds the WhatsApp session of the dedicated number and exposes
 * it over HTTP on BioBalance's private network. Messages leave one at a time, a few seconds apart.
 */
export class WahaTransport implements WhatsAppTransport {
  private readonly url: string;
  private readonly session: string;
  private readonly fetcher: typeof fetch;
  private readonly gap: () => number;
  private readonly sleep: (ms: number) => Promise<void>;
  private tail: Promise<unknown> = Promise.resolve();
  private lastSent = 0;

  constructor(private readonly options: WahaOptions) {
    this.url = options.url.replace(/\/$/, "");
    this.session = options.session ?? "default";
    this.fetcher = options.fetchImpl ?? fetch;
    this.gap = options.gapMs ?? (() => 3000 + Math.random() * 5000);
    this.sleep = options.sleep ?? wait;
  }

  private async call(path: string, init: RequestInit = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      return await this.fetcher(`${this.url}${path}`, {
        ...init,
        signal: controller.signal,
        headers: {
          "content-type": "application/json",
          "x-api-key": this.options.apiKey,
        },
      });
    } finally {
      clearTimeout(timer);
    }
  }

  async hasWhatsApp(phone: string) {
    try {
      const res = await this.call(
        `/api/contacts/check-exists?phone=${encodeURIComponent(phone.slice(1))}&session=${this.session}`,
      );
      if (!res.ok) return null;
      const body = (await res.json()) as { numberExists?: boolean };
      return typeof body.numberExists === "boolean" ? body.numberExists : null;
    } catch {
      return null;
    }
  }

  send(phone: string, text: string) {
    // One message at a time, spaced out: the chain makes concurrent jobs wait their turn.
    const run = this.tail.then(async () => {
      const pause = this.lastSent + this.gap() - Date.now();
      if (pause > 0) await this.sleep(pause);
      try {
        const res = await this.call("/api/sendText", {
          method: "POST",
          body: JSON.stringify({
            session: this.session,
            chatId: whatsappChatId(phone),
            text,
          }),
        });
        if (!res.ok) throw new Error("WHATSAPP_SEND_FAILED");
      } catch (error) {
        // Only a safe machine word leaves this file: provider errors can carry the number or the code.
        throw error instanceof Error && error.message === "WHATSAPP_SEND_FAILED"
          ? error
          : new Error("WHATSAPP_UNREACHABLE");
      } finally {
        this.lastSent = Date.now();
      }
    });
    this.tail = run.catch(() => undefined);
    return run;
  }

  async status() {
    try {
      const res = await this.call(`/api/sessions/${this.session}`);
      if (!res.ok) return "DISCONNECTED" as const;
      const body = (await res.json()) as { status?: string };
      return body.status === "WORKING"
        ? ("CONNECTED" as const)
        : ("DISCONNECTED" as const);
    } catch {
      return "DISCONNECTED" as const;
    }
  }
}

/** The configured sender, or null when WhatsApp is not set up on this server. */
export function whatsappFromEnv(
  env: Record<string, string | undefined> = process.env,
): WhatsAppTransport | null {
  if (!env.WAHA_URL || !env.WAHA_API_KEY) return null;
  return new WahaTransport({ url: env.WAHA_URL, apiKey: env.WAHA_API_KEY });
}
