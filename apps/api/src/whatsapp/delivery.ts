import type { Database } from "../core/database";
import { normalizeTunisianPhone } from "../core/phone";
import { SettingsService } from "../core/settings";
import { hashCode } from "../modules/auth/codes";
import { Payload } from "../email/delivery";
import { renderWhatsApp } from "./templates";
import type { WhatsAppTransport } from "./transport";

/** The most WhatsApp messages sent in a day: a few dozen invitations is normal, a flood is not. */
export const DAILY_CAP = 200;

export type Outcome = "sent" | "suppressed";

/**
 * Turns a queued "whatsapp" job (the same payload as the email of the same code) into a message, unless
 * the channel is off, the person has no usable WhatsApp number, or the code is no longer valid. A
 * problem here never stops the email, which is a separate job.
 */
export class WhatsAppDelivery {
  constructor(
    private readonly db: Database,
    private readonly transport: WhatsAppTransport | null,
    private readonly settings: SettingsService,
    private readonly cap = DAILY_CAP,
  ) {}

  async deliver(job: { id: string; payload: unknown }): Promise<Outcome> {
    const parsed = Payload.safeParse(job.payload);
    if (!parsed.success) throw new Error("WHATSAPP_PAYLOAD_INVALID");
    const p = parsed.data;
    if (!this.transport || !(await this.settings.get()).whatsapp.enabled)
      return "suppressed";
    const user = await this.db.user.findUnique({ where: { id: p.userId } });
    if (!user || user.status !== "ACTIVE") return "suppressed";
    // Nothing leaves the test region (the store reviewers' accounts and what they invite).
    if (user.regionId) {
      const region = await this.db.region.findUnique({
        where: { id: user.regionId },
        select: { sandbox: true },
      });
      if (region?.sandbox) return "suppressed";
    }
    const phone = user.phone ? normalizeTunisianPhone(user.phone) : null;
    if (!phone) return "suppressed";
    const locale = user.locale === "en" ? "en" : "fr";
    let text: string;
    if (p.template === "password-changed")
      text = renderWhatsApp(locale, {
        kind: p.template,
        name: user.name,
        changedAt: new Date(p.changedAt),
      });
    else {
      const token = await this.db.accessToken.findUnique({
        where: { id: p.accessTokenId },
      });
      // A code that was used, replaced or has expired must not be sent on a retry.
      if (
        !token ||
        token.usedAt ||
        token.expiresAt <= new Date() ||
        token.tokenHash !== hashCode(p.code)
      )
        return "suppressed";
      const base = process.env.API_PUBLIC_URL?.replace(/\/$/, "");
      const link = base
        ? `${base}/c#${p.template === "reset" ? "r" : "i"}.${p.code}`
        : undefined;
      text =
        p.template === "invite"
          ? renderWhatsApp(locale, {
              kind: "invite",
              code: p.code,
              name: user.name,
              link,
            })
          : renderWhatsApp(locale, {
              kind: "reset",
              code: p.code,
              name: user.name,
              link,
              minutes: Math.max(
                1,
                Math.round((token.expiresAt.getTime() - Date.now()) / 60_000),
              ),
            });
    }
    // A number without WhatsApp is skipped, not tried: that is what gets a sending number banned.
    if ((await this.transport.hasWhatsApp(phone)) === false)
      return "suppressed";
    const today = await this.db.job.count({
      where: {
        kind: "whatsapp",
        createdAt: { gt: new Date(Date.now() - 86_400_000) },
      },
    });
    if (today > this.cap) throw new Error("WHATSAPP_DAILY_CAP");
    await this.transport.send(phone, text);
    return "sent";
  }
}
