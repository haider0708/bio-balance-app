import "reflect-metadata";
import { Database } from "./shared/infrastructure/database";
import { createTransport } from "nodemailer";
import { applicationDefault, initializeApp, getApps } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { MediaProcessor } from "./modules/training/infrastructure/media-processor";
import { writeFile } from "node:fs/promises";
import { PrismaUnitOfWork } from "./modules/operations/infrastructure/prisma-ledger";
import {
  JobRunner,
  JobExecutor,
  scheduleInventoryChecks,
} from "./shared/jobs/job-runner";
import { PushDeliveryService } from "./modules/notifications/infrastructure/push-delivery";
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
const push = new PushDeliveryService(db, {
  async send(tokens, data) {
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS)
      throw new Error("FCM_NOT_CONFIGURED");
    if (!getApps().length) initializeApp({ credential: applicationDefault() });
    const result = await getMessaging().sendEachForMulticast({
      tokens,
      data,
      notification: {
        title: "BioBalance",
        body: "Un nouveau message est disponible dans votre espace.",
      },
      android: { collapseKey: data.notificationId, ttl: 300_000 },
      apns: {
        headers: {
          "apns-collapse-id": data.notificationId!,
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 300),
        },
      },
    });
    return result.responses.map((r) => ({
      success: r.success,
      errorCode: r.error?.code,
    }));
  },
});
const execute: JobExecutor = async (job, owned) => {
  if (job.kind === "push")
    return push.deliver(job.payload.notificationId!, owned);
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
    mediaMode ? ["media"] : ["email", "push", "inventory-check"],
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
          if (index === 0 && !mediaMode && Date.now() >= nextSchedule) {
            await scheduleInventoryChecks(db);
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
