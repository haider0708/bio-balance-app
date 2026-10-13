import "reflect-metadata";
import { writeFile } from "node:fs/promises";
import { Database } from "./core/database";
import { EmailDelivery } from "./email/delivery";
import { SmtpEmailTransport } from "./email/smtp";
import { type JobExecutor, JobRunner } from "./jobs/job-runner";
import {
  approveSandbox,
  keepSandboxSelling,
  restoreDemoAccount,
  sandboxServices,
  scheduleSandbox,
  type RestorePayload,
} from "./demo/sandbox";
import { cleanup, scheduleCleanup } from "./jobs/maintenance";
import { MessagingService } from "./modules/messaging/messaging.service";
import { PushDelivery } from "./push/push-delivery";
import { NotificationSignal } from "./push/signal";
import { transportsFromEnv } from "./push/transports";

const db = new Database();
const smtp = new SmtpEmailTransport();
const emails = new EmailDelivery(db, smtp);
const messages = new MessagingService(db);
const transports = transportsFromEnv();
const pushes = new PushDelivery(db, transports);
const sandbox = sandboxServices(db);
const wake = new NotificationSignal(process.env.DATABASE_URL ?? "");
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
    case "sandbox-approve":
      await approveSandbox(sandbox);
      return;
    case "sandbox-sell":
      await keepSandboxSelling(sandbox);
      return;
    case "demo-restore":
      return restoreDemoAccount(db, job.payload as unknown as RestorePayload);
    default:
      throw new Error("UNKNOWN_JOB");
  }
};

for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    stopping = true;
    wake.signal();
  });

async function main() {
  const runner = new JobRunner(
    db,
    [
      "email",
      "message-send",
      "cleanup",
      "sandbox-approve",
      "sandbox-sell",
      "demo-restore",
    ],
    execute,
  );
  const concurrency = Math.max(
    1,
    Math.min(4, Number(process.env.WORKER_CONCURRENCY) || 2),
  );
  let nextSchedule = 0;
  let nextSandbox = 0;
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
          if (index === 0 && Date.now() >= nextSandbox) {
            await scheduleSandbox(db);
            nextSandbox = Date.now() + 60_000;
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
  // New notifications reach phones at once: the database signals the worker, which sends them.
  wake.start();
  const push = (async () => {
    while (!stopping) {
      try {
        // Keep going while there is a backlog; then sleep until the next signal. A slow timer
        // covers a missed signal (and a database without the listener) with little cost.
        if (!(await pushes.tick()))
          await wake.wait(wake.listening ? 30_000 : 3_000);
        else await new Promise((r) => setTimeout(r, 25));
      } catch {
        console.error(JSON.stringify({ level: "error", code: "PUSH_LOOP" }));
        await new Promise((r) => setTimeout(r, 5000));
      }
    }
  })();
  await Promise.all([...loops, push]);
  clearInterval(heartbeat);
  await wake.stop();
  for (const transport of Object.values(transports)) transport.close();
  smtp.close();
  await db.$disconnect();
}

void main();
