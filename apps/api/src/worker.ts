import {
  cleanupAuthentication,
  scheduleMaintenance,
} from "./shared/jobs/maintenance";
import { cleanupMedia } from "./modules/training/infrastructure/media-storage";
import path from "node:path";
import "reflect-metadata";
import { Database } from "./shared/infrastructure/database";
import { createTransport } from "nodemailer";
import { MediaProcessor } from "./modules/training/infrastructure/media-processor";
import { writeFile } from "node:fs/promises";
import { PrismaUnitOfWork } from "./modules/operations/infrastructure/prisma-ledger";
import {
  JobRunner,
  JobExecutor,
  scheduleInventoryChecks,
} from "./shared/jobs/job-runner";
const db = new Database();
let stopping = false;
const mediaMode = process.env.WORKER_KIND === "media";
const smtp = createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT ?? 587),
  secure: process.env.SMTP_SECURE === "true",
  requireTLS: process.env.SMTP_REQUIRE_TLS === "true",
  auth: process.env.SMTP_USER
    ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD }
    : undefined,
  connectionTimeout: 10000,
  socketTimeout: 30000,
});
const execute: JobExecutor = async (job) => {
  if (job.kind === "auth-cleanup") return cleanupAuthentication(db);
  if (job.kind === "media-cleanup")
    return cleanupMedia(
      db,
      path.resolve(process.env.MEDIA_ROOT ?? "../../.volumes/media"),
    );
  if (job.kind === "push") {
    // Drain legacy transport jobs without inventing successful device delivery.
    // Their authorized inbox records remain available on the VPS.
    console.log(
      JSON.stringify({
        event: "push.skipped",
        reason: "inbox_only",
        jobId: job.id,
      }),
    );
    return;
  }
  if (job.kind === "media")
    return new MediaProcessor(db).process(job.payload.mediaId!);
  if (job.kind === "email") {
    await smtp.sendMail({
      from: process.env.SMTP_FROM,
      to: job.payload.to,
      subject: job.payload.subject,
      text: job.payload.text,
      messageId: `<${job.id}@biobalance>`,
    });
    return;
  }
  if (job.kind === "inventory-check") {
    const admin = await db.user.findFirst({
      where: { platformAdmin: true, disabled: false },
    });
    if (!admin) throw new Error("ADMIN_NOT_PROVISIONED");
    await new PrismaUnitOfWork(db).run(
      admin,
      job.payload.organizationId!,
      job.payload.storeId!,
      (ledger) => ledger.checkInventory(job.id),
    );
    return;
  }
  throw new Error("UNKNOWN_JOB");
};
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    stopping = true;
  });
async function main() {
  const concurrency = mediaMode
    ? 1
    : Math.max(1, Math.min(4, Number(process.env.WORKER_CONCURRENCY) || 2));
  const runner = new JobRunner(
    db,
    mediaMode
      ? ["media", "media-cleanup"]
      : ["email", "push", "inventory-check", "auth-cleanup"],
    execute,
  );
  let nextSchedule = 0;
  let lastHealthy = Date.now();
  // Renewal/claim progress is required; a live timer alone is not worker health.
  const heartbeat = setInterval(() => {
    if (Date.now() - lastHealthy < 45000)
      void writeFile(
        "/tmp/biobalance-worker-heartbeat",
        String(Date.now()),
      ).catch(() => {});
  }, 15000);
  const workers = Array.from({ length: concurrency }, (_, index) =>
    (async () => {
      while (!stopping) {
        try {
          if (index === 0 && Date.now() >= nextSchedule) {
            if (!mediaMode) await scheduleInventoryChecks(db);
            await scheduleMaintenance(db, mediaMode);
            nextSchedule = Date.now() + 3600000;
          }
          const running = runner.tick();
          // Long media jobs keep health only while PostgreSQL remains reachable.
          const probe = setInterval(() => {
            void db.$queryRaw`SELECT 1`
              .then(() => {
                lastHealthy = Date.now();
              })
              .catch(() => {});
          }, 15000);
          let worked;
          try {
            worked = await running;
            lastHealthy = Date.now();
          } finally {
            clearInterval(probe);
          }
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
  await Promise.all(workers);
  clearInterval(heartbeat);
  smtp.close();
  await db.$disconnect();
}
void main();
