import "reflect-metadata";
import { Database } from "./shared/infrastructure/database";
import { createTransport } from "nodemailer";
import { applicationDefault, initializeApp, getApps } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { MediaProcessor } from "./modules/training/infrastructure/media-processor";
import { writeFile } from "node:fs/promises";
import { PrismaUnitOfWork } from "./modules/operations/infrastructure/prisma-ledger";
const db = new Database();
let stopping = false;
const mediaMode = process.env.WORKER_KIND === "media";
const smtp = createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT ?? 587),
  secure: process.env.SMTP_SECURE === "true",
  auth: process.env.SMTP_USER
    ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD }
    : undefined,
});
async function execute(kind: string, payload: Record<string, string>) {
  if (kind === "inventory-check") {
    const administrator = await db.user.findFirst({
      where: { platformAdmin: true, disabled: false },
    });
    if (!administrator) throw new Error("ADMIN_NOT_PROVISIONED");
    await new PrismaUnitOfWork(db).run(
      { ...administrator },
      payload.organizationId!,
      payload.storeId!,
      async (ledger) => {
        await ledger.checkInventory();
      },
    );
    return;
  }
  if (kind === "email") {
    await smtp.sendMail({
      from: process.env.SMTP_FROM,
      to: payload.to,
      subject: payload.subject,
      text: payload.text,
    });
    return;
  }
  if (kind === "push") {
    const notification = await db.notification.findUnique({
      where: { id: payload.notificationId },
    });
    if (!notification) return;
    const user = await db.user.findUnique({
      where: { id: notification.userId },
    });
    if (!user || user.disabled) return;
    if (notification.storeId && !user.platformAdmin) {
      const member = await db.membership.findUnique({
        where: {
          storeId_userId: { storeId: notification.storeId, userId: user.id },
        },
      });
      const owner = notification.organizationId
        ? await db.organizationMembership.findUnique({
            where: {
              organizationId_userId: {
                organizationId: notification.organizationId,
                userId: user.id,
              },
            },
          })
        : null;
      if (!member?.active && !owner?.active) return;
    }
    const sessions = await db.session.findMany({
      where: {
        userId: user.id,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: { id: true },
    });
    const devices = await db.deviceToken.findMany({
      where: {
        userId: notification.userId,
        sessionId: { in: sessions.map((s) => s.id) },
      },
      take: 500,
    });
    if (!devices.length) return;
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS)
      throw new Error("FCM_NOT_CONFIGURED");
    if (!getApps().length) initializeApp({ credential: applicationDefault() });
    const result = await getMessaging().sendEachForMulticast({
      tokens: devices.map((d) => d.token),
      notification: { title: notification.title, body: notification.body },
      data: {
        notificationId: notification.id,
        storeId: notification.storeId ?? "",
      },
      android: { collapseKey: notification.id },
      apns: { headers: { "apns-collapse-id": notification.id } },
    });
    for (let i = 0; i < result.responses.length; i++) {
      const response = result.responses[i]!;
      if (
        [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(response.error?.code ?? "")
      )
        await db.deviceToken.delete({ where: { id: devices[i]!.id } });
      else if (!response.success) throw new Error("PUSH_DELIVERY_FAILED");
    }
    return;
  }
  if (kind === "media") {
    await new MediaProcessor(db).process(payload.mediaId!);
    return;
  }
  throw new Error("UNKNOWN_JOB");
}
async function tick() {
  const jobs = await db.$queryRaw<
    {
      id: string;
      kind: string;
      payload: Record<string, string>;
      attempts: number;
    }[]
  >`UPDATE "Job" SET status='running',"lockedAt"=now(),attempts=attempts+1 WHERE id=(SELECT id FROM "Job" WHERE ((status='pending' AND "availableAt"<=now()) OR (status='running' AND "lockedAt"<now()-interval '15 minutes')) AND (CASE WHEN ${mediaMode} THEN kind='media' ELSE kind<>'media' END) ORDER BY "availableAt" FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id,kind,payload,attempts`;
  for (const job of jobs) {
    try {
      await execute(job.kind, job.payload);
      await db.job.update({
        where: { id: job.id },
        data: { status: "completed", payload: {}, lastError: null },
      });
    } catch (error) {
      const failed = job.attempts >= 8;
      await db.job.update({
        where: { id: job.id },
        data: {
          status: failed ? "failed" : "pending",
          availableAt: new Date(
            Date.now() + Math.min(3600_000, 1000 * 2 ** job.attempts),
          ),
          lastError:
            error instanceof Error ? error.message.slice(0, 200) : "JOB_FAILED",
        },
      });
      if (failed && job.kind === "media")
        await db.mediaAsset.update({
          where: { id: job.payload.mediaId },
          data: { status: "failed" },
        });
      console.error(
        JSON.stringify({
          level: "error",
          jobId: job.id,
          kind: job.kind,
          attempt: job.attempts,
        }),
      );
    }
  }
  return jobs.length > 0;
}
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    stopping = true;
  });
async function scheduleChecks() {
  const hour = new Date().toISOString().slice(0, 13);
  const stores = await db.store.findMany({
    select: { id: true, organizationId: true },
    take: 1000,
  });
  await db.job.createMany({
    data: stores.map((s) => ({
      kind: "inventory-check",
      key: `inventory:${s.id}:${hour}`,
      payload: { storeId: s.id, organizationId: s.organizationId },
    })),
    skipDuplicates: true,
  });
}
async function main() {
  const heartbeat = setInterval(
    () =>
      void writeFile(
        "/tmp/biobalance-worker-heartbeat",
        String(Date.now()),
      ).catch(() => {}),
    15000,
  );
  let nextSchedule = 0;
  while (!stopping) {
    try {
      if (!mediaMode && Date.now() >= nextSchedule) {
        await scheduleChecks();
        nextSchedule = Date.now() + 3600000;
      }
      if (!(await tick())) await new Promise((r) => setTimeout(r, 1000));
    } catch {
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  clearInterval(heartbeat);
  await db.$disconnect();
}
void main();
