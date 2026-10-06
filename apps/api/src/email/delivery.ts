import { z } from "zod";
import type { Database } from "../core/database";
import { hashCode } from "../modules/auth/codes";
import { type EmailContent, renderEmail } from "./templates";

export interface EmailTransport {
  send(to: string, content: EmailContent, jobId: string): Promise<void>;
}

const Payload = z.discriminatedUnion("template", [
  z.object({
    template: z.literal("invite"),
    userId: z.uuid(),
    accessTokenId: z.uuid(),
    code: z.string().regex(/^[A-Z0-9]{8}$/),
  }),
  z.object({
    template: z.literal("reset"),
    userId: z.uuid(),
    accessTokenId: z.uuid(),
    code: z.string().regex(/^[A-Z0-9]{8}$/),
  }),
  z.object({
    template: z.literal("password-changed"),
    userId: z.uuid(),
    changedAt: z.iso.datetime(),
  }),
]);

/** Turns a queued email job into a sent message, unless the person or code is no longer valid. */
export class EmailDelivery {
  constructor(
    private readonly db: Database,
    private readonly transport: EmailTransport,
  ) {}

  async deliver(
    job: { id: string; payload: unknown },
    stillOwned: () => Promise<boolean>,
  ) {
    const parsed = Payload.safeParse(job.payload);
    if (!parsed.success) throw new Error("EMAIL_PAYLOAD_INVALID");
    const p = parsed.data;
    const user = await this.db.user.findUnique({ where: { id: p.userId } });
    if (!user || user.status !== "ACTIVE") return "suppressed" as const;
    const locale = user.locale === "en" ? "en" : "fr";
    let content: EmailContent;
    if (p.template === "password-changed")
      content = renderEmail(locale, {
        kind: p.template,
        changedAt: new Date(p.changedAt),
        name: user.name,
      });
    else {
      const token = await this.db.accessToken.findUnique({
        where: { id: p.accessTokenId },
      });
      // A code that was used, replaced or has expired must not be mailed on a retry.
      if (
        !token ||
        token.usedAt ||
        token.expiresAt <= new Date() ||
        token.tokenHash !== hashCode(p.code)
      )
        return "suppressed" as const;
      content = renderEmail(locale, {
        kind: p.template,
        code: p.code,
        expiresAt: token.expiresAt,
        name: user.name,
        link: process.env.API_PUBLIC_URL
          ? `${process.env.API_PUBLIC_URL.replace(/\/$/, "")}/c#${p.template === "reset" ? "r" : "i"}.${p.code}`
          : undefined,
      });
    }
    if (!(await stillOwned())) throw new Error("EMAIL_LEASE_LOST");
    await this.transport.send(user.email, content, job.id);
    return "accepted" as const;
  }
}
