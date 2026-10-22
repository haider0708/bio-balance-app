import { Injectable } from "@nestjs/common";
import { type WhatsAppTransport, whatsappFromEnv } from "./transport";

/** What the admin sees in the settings: whether WhatsApp is set up on this server and its session is alive. */
@Injectable()
export class WhatsAppStatus {
  private readonly transport: WhatsAppTransport | null = whatsappFromEnv();
  private cache: { at: number; value: "CONNECTED" | "DISCONNECTED" } | null =
    null;

  get configured() {
    return this.transport !== null;
  }

  async status(): Promise<"NOT_CONFIGURED" | "CONNECTED" | "DISCONNECTED"> {
    if (!this.transport) return "NOT_CONFIGURED";
    if (this.cache && Date.now() - this.cache.at < 20_000)
      return this.cache.value;
    const value = await this.transport.status();
    this.cache = { at: Date.now(), value };
    return value;
  }
}
