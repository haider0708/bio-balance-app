import { createHash } from "node:crypto";
import { z } from "zod";
import { invitationIsAuthorized } from "../../modules/identity/invitation-policy";
import { Database } from "../infrastructure/database";
import { ClaimedJob } from "../jobs/job-runner";
import { EmailContent, renderEmail } from "./email-templates";

const credential = {
  version: z.literal("1"),
  to: z.email(),
  accessTokenId: z.uuid(),
  token: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
};
export const EmailPayload = z.discriminatedUnion("template", [
  z.object({ ...credential, template: z.literal("invite") }).strict(),
  z
    .object({
      ...credential,
      token: z.string().regex(/^(?:[A-Z0-9]{8}|[A-Za-z0-9_-]{43})$/),
      template: z.literal("reset"),
    })
    .strict(),
  z
    .object({
      version: z.literal("1"),
      template: z.literal("password-changed"),
      to: z.email(),
      userId: z.uuid(),
      changedAt: z.iso.datetime(),
    })
    .strict(),
  z
    .object({
      version: z.literal("1"),
      template: z.literal("delivery-test"),
      to: z.email(),
      reference: z.uuid(),
      sentAt: z.iso.datetime(),
    })
    .strict(),
]);
export type EmailPayload = z.infer<typeof EmailPayload>;
export interface EmailTransport {
  send(to: string, content: EmailContent, jobId: string): Promise<void>;
}
type EmailJob = Pick<ClaimedJob, "id" | "key" | "payload">;

/** Accept old queued invitations without rewriting their operation IDs/payloads. */
function decode(job: EmailJob): EmailPayload {
  if (job.payload.version === undefined) {
    const key = /^(invite|reset):([0-9a-f-]{36})$/i.exec(job.key);
    const token = job.payload.text?.match(/ : ([A-Za-z0-9_-]{43})\./)?.[1];
    if (key && token) {
      const legacy = EmailPayload.safeParse({
        version: "1",
        template: key[1],
        accessTokenId: key[2],
        to: job.payload.to,
        token,
      });
      if (legacy.success) return legacy.data;
    }
  }
  const parsed = EmailPayload.safeParse(job.payload);
  if (!parsed.success) throw new Error("EMAIL_PAYLOAD_INVALID");
  return parsed.data;
}

export class EmailDeliveryService {
  constructor(
    private readonly db: Database,
    private readonly transport: EmailTransport,
    private readonly now = () => new Date(),
  ) {}

  async deliver(job: EmailJob, stillOwned: () => Promise<boolean>) {
    const payload = decode(job);
    const content = await this.content(job, payload);
    // A consumed, expired or revoked capability must not be mailed on a retry.
    if (!content) return "suppressed" as const;
    if (!(await stillOwned())) throw new Error("EMAIL_LEASE_LOST");
    await this.transport.send(payload.to, content, job.id);
    return "accepted" as const;
  }

  private async content(
    job: EmailJob,
    payload: EmailPayload,
  ): Promise<EmailContent | null> {
    if (payload.template === "delivery-test") {
      if (job.key !== `email-test:${payload.reference}`)
        throw new Error("EMAIL_PAYLOAD_INVALID");
      return renderEmail({
        kind: "delivery-test",
        reference: payload.reference,
        sentAt: new Date(payload.sentAt),
      });
    }
    if (payload.template === "password-changed") {
      if (!/^password-changed:[0-9a-f-]{36}$/i.test(job.key))
        throw new Error("EMAIL_PAYLOAD_INVALID");
      const user = await this.db.user.findUnique({
        where: { id: payload.userId },
      });
      if (!user || user.disabled || user.email !== payload.to) return null;
      return renderEmail({
        kind: "password-changed",
        changedAt: new Date(payload.changedAt),
      });
    }
    if (job.key !== `${payload.template}:${payload.accessTokenId}`)
      throw new Error("EMAIL_PAYLOAD_INVALID");
    return this.db.$transaction(async (tx) => {
      const token = await tx.accessToken.findUnique({
        where: { id: payload.accessTokenId },
      });
      if (!token || token.usedAt || token.expiresAt <= this.now()) return null;
      if (
        token.email !== payload.to ||
        token.purpose !== payload.template ||
        token.tokenHash !==
          createHash("sha256").update(payload.token).digest("hex")
      ) {
        throw new Error("EMAIL_CAPABILITY_MISMATCH");
      }
      const user = await tx.user.findUnique({ where: { email: payload.to } });
      if (user?.disabled || (payload.template === "reset" && !user))
        return null;
      let organizationName: string | undefined, storeName: string | undefined;
      if (payload.template === "invite") {
        if (!(await invitationIsAuthorized(tx, token))) return null;
        organizationName = token.organizationId
          ? (
              await tx.organization.findUnique({
                where: { id: token.organizationId },
              })
            )?.name
          : undefined;
        storeName = token.storeId
          ? (await tx.store.findUnique({ where: { id: token.storeId } }))?.name
          : undefined;
      }
      return renderEmail({
        kind: payload.template,
        token: payload.token,
        expiresAt: token.expiresAt,
        organizationName,
        storeName,
        invitationKind: token.kind as
          "new_group" | "responsible" | "salesperson" | null,
      });
    });
  }
}
