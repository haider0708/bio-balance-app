import "reflect-metadata";
import { parseArgs } from "node:util";
import { z } from "zod";
import { Database } from "../shared/infrastructure/database";
import type { EmailPayload } from "../shared/email/email-delivery";

/** Operator-only CLI, never an HTTP endpoint; no account or access grant. */
async function main() {
  const { values } = parseArgs({
    options: { to: { type: "string" }, reference: { type: "string" } },
  });
  const to = z.email().parse(values.to);
  const reference = z.uuid().parse(values.reference);
  const db = new Database();
  try {
    const job = await db.job.upsert({
      where: { key: `email-test:${reference}` },
      create: {
        kind: "email",
        key: `email-test:${reference}`,
        payload: {
          version: "1",
          template: "delivery-test",
          to,
          reference,
          sentAt: new Date().toISOString(),
        } satisfies EmailPayload,
      },
      update: {},
    });
    if (
      job.status !== "completed" &&
      job.status !== "failed" &&
      (job.payload as Record<string, string>).to !== to
    )
      throw Error("EMAIL_REFERENCE_REUSED");
    console.log(
      JSON.stringify({ jobId: job.id, status: job.status, reference }),
    );
  } finally {
    await db.$disconnect();
  }
}
void main().catch(() => {
  console.error("EMAIL_TEST_COMMAND_FAILED");
  process.exitCode = 1;
});
