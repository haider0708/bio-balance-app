import "reflect-metadata";
import { writeFile } from "node:fs/promises";
import { Database } from "./core/database";
import { EmailDelivery } from "./email/delivery";
import { SmtpEmailTransport } from "./email/smtp";
import { type JobExecutor, JobRunner } from "./jobs/job-runner";
import { cleanup, scheduleCleanup } from "./jobs/maintenance";
import { MessagingService } from "./modules/messaging/messaging.service";

const db = new Database();
const smtp = new SmtpEmailTransport();
const emails = new EmailDelivery(db, smtp);
const messages = new MessagingService(db);
let stopping = false;

const execute: JobExecutor = async (job, stillOwned) => {
  switch (job.kind) {
    case "email": {
      const outcome = await emails.deliver(job, stillOwned);
      if (outcome === "suppressed")
        console.log(
          JSON.stringify({ event: "email.suppressed", jobId: job.id }),
        );
      return;
    }
    case "message-send":
      return messages.deliverScheduled(String(job.payload.messageId));
    case "cleanup":
      return cleanup(db);
    default:
      throw new Error("UNKNOWN_JOB");
  }
};

for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => (stopping = true));

async function main() {
  const runner = new JobRunner(
    db,
    ["email", "message-send", "cleanup"],
    execute,
  );
  const concurrency = Math.max(
    1,
    Math.min(4, Number(process.env.WORKER_CONCURRENCY) || 2),
  );
  let nextSchedule = 0;
  let lastHealthy = Date.now();
  // The container health check reads this file; it stops updating if the worker stops making progress.
  const heartbeat = setInterval(() => {
    if (Date.now() - lastHealthy < 45_000)
      void writeFile(
        "/tmp/biobalance-worker-heartbeat",
        String(Date.now()),
      ).catch(() => undefined);
  }, 15_000);
  const loops = Array.from({ length: concurrency }, (_, index) =>
    (async () => {
      while (!stopping) {
        try {
          if (index === 0 && Date.now() >= nextSchedule) {
            await scheduleCleanup(db);
            nextSchedule = Date.now() + 3_600_000;
          }
          const worked = await runner.tick();
          lastHealthy = Date.now();
          if (!worked) await new Promise((r) => setTimeout(r, 1000));
        } catch {
          console.error(
            JSON.stringify({
              level: "error",
              code: "WORKER_DATABASE_UNAVAILABLE",
            }),
          );
          await new Promise((r) => setTimeout(r, 3000));
        }
      }
    })(),
  );
  await Promise.all(loops);
  clearInterval(heartbeat);
  smtp.close();
  await db.$disconnect();
}

void main();
