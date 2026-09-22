import { createTransport } from "nodemailer";
import { z } from "zod";
import { EmailTransport } from "./email-delivery";
import { EmailContent } from "./email-templates";

/** SMTP acceptance is delivery to the relay, never proof of inbox placement. */
export class SmtpEmailTransport implements EmailTransport {
  private readonly smtp;
  private readonly from: string;
  private readonly address: string;
  constructor(env: NodeJS.ProcessEnv = process.env) {
    this.from = env.SMTP_FROM ?? "";
    this.address = this.from.match(/<([^<>]+)>$/)?.[1] ?? this.from;
    if (/[\r\n]/.test(this.from) || !z.email().safeParse(this.address).success)
      throw new Error("SMTP_FROM_INVALID");
    const port = Number(env.SMTP_PORT ?? 587);
    if (
      !env.SMTP_HOST ||
      /\s/.test(env.SMTP_HOST) ||
      !Number.isInteger(port) ||
      port < 1 ||
      port > 65535
    )
      throw new Error("SMTP_CONFIGURATION_INVALID");
    this.smtp = createTransport({
      host: env.SMTP_HOST,
      port,
      secure: env.SMTP_SECURE === "true",
      requireTLS:
        env.SMTP_REQUIRE_TLS === "true" || env.NODE_ENV === "production",
      tls: { minVersion: "TLSv1.2", rejectUnauthorized: true },
      auth: env.SMTP_USER
        ? { user: env.SMTP_USER, pass: env.SMTP_PASSWORD }
        : undefined,
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 30000,
      disableFileAccess: true,
      disableUrlAccess: true,
    });
  }
  async send(to: string, content: EmailContent, jobId: string) {
    if (!z.email().safeParse(to).success || !z.uuid().safeParse(jobId).success)
      throw new Error("EMAIL_ADDRESS_INVALID");
    const messageId = `<${jobId}@${this.address.split("@")[1]}>`;
    const result = await this.smtp.sendMail({
      from: this.from,
      to,
      ...content,
      messageId,
      envelope: { from: this.address, to: [to] },
      headers: {
        "Auto-Submitted": "auto-generated",
        "X-Auto-Response-Suppress": "All",
      },
    });
    if (!result.accepted.includes(to) || result.rejected.length)
      throw new Error("SMTP_RECIPIENT_REJECTED");
    console.log(
      JSON.stringify({ event: "email.smtp_accepted", jobId, messageId }),
    );
  }
  close() {
    this.smtp.close();
  }
}
