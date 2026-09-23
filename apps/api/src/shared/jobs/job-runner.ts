import { randomUUID } from "node:crypto";
import { Database } from "../infrastructure/database";

export interface ClaimedJob {
  id: string;
  kind: string;
  key: string;
  payload: Record<string, string>;
  attempts: number;
  leaseToken: string;
}
export type JobExecutor = (
  job: ClaimedJob,
  stillOwned: () => Promise<boolean>,
) => Promise<void>;
export class JobRunner {
  constructor(
    private readonly db: Database,
    private readonly kinds: string[],
    private readonly execute: JobExecutor,
    private readonly leaseMs = 900_000,
    private readonly random = Math.random,
  ) {}
  async claim(): Promise<ClaimedJob | null> {
    const token = randomUUID(),
      stale = new Date(Date.now() - this.leaseMs);
    const jobs = await this.db.$queryRaw<
      ClaimedJob[]
    >`UPDATE "Job" SET status='running',"lockedAt"=now(),"leaseToken"=${token}::uuid,attempts=attempts+1 WHERE id=(SELECT id FROM "Job" WHERE ((status='pending' AND "availableAt"<=now()) OR (status='running' AND "lockedAt"<${stale})) AND kind=ANY(${this.kinds}::text[]) ORDER BY "availableAt",id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id,kind,key,payload,attempts,"leaseToken"`;
    return jobs[0] ?? null;
  }
  private owned(job: ClaimedJob) {
    return { id: job.id, status: "running", leaseToken: job.leaseToken };
  }
  async renew(job: ClaimedJob) {
    return (
      (
        await this.db.job.updateMany({
          where: this.owned(job),
          data: { lockedAt: new Date() },
        })
      ).count === 1
    );
  }
  async complete(job: ClaimedJob) {
    return (
      (
        await this.db.job.updateMany({
          where: this.owned(job),
          data: {
            status: "completed",
            payload: {},
            lastError: null,
            leaseToken: null,
            lockedAt: null,
          },
        })
      ).count === 1
    );
  }
  async fail(job: ClaimedJob, error: unknown) {
    const failed = job.attempts >= 8;
    // Provider errors can contain addresses/tokens. Persist a safe machine code.
    const message =
      error instanceof Error && /^[A-Z][A-Z0-9_]{1,79}$/.test(error.message)
        ? error.message
        : "JOB_EXECUTION_FAILED";
    const delay =
      Math.min(3600_000, 1000 * 2 ** Math.min(job.attempts, 12)) *
      (0.8 + this.random() * 0.2);
    await this.db.$transaction(async (tx) => {
      const result = await tx.job.updateMany({
        where: this.owned(job),
        data: {
          status: failed ? "failed" : "pending",
          // A terminal mail failure is diagnosed by its code, never by keeping
          // a password-reset or invitation bearer code indefinitely.
          ...(failed && job.kind === "email" ? { payload: {} } : {}),
          availableAt: new Date(Date.now() + delay),
          lastError: message,
          leaseToken: null,
          lockedAt: null,
        },
      });
      if (result.count && failed && job.kind === "media")
        await tx.mediaAsset.updateMany({
          where: { id: job.payload.mediaId, status: "processing" },
          data: { status: "failed" },
        });
    });
  }
  async tick() {
    const job = await this.claim();
    if (!job) return false;
    let renewalRunning = false;
    const interval = setInterval(
      () => {
        if (renewalRunning) return;
        renewalRunning = true;
        void this.renew(job)
          .catch(() => false)
          .finally(() => {
            renewalRunning = false;
          });
      },
      Math.max(100, Math.floor(this.leaseMs / 3)),
    );
    try {
      if (job.attempts > 8) throw new Error("JOB_ATTEMPTS_EXHAUSTED");
      await this.execute(job, () => this.renew(job));
      await this.complete(job);
    } catch (error) {
      await this.fail(job, error);
      console.error(
        JSON.stringify({
          level: "error",
          jobId: job.id,
          kind: job.kind,
          attempt: job.attempts,
        }),
      );
    } finally {
      clearInterval(interval);
    }
    return true;
  }
}
export async function scheduleInventoryChecks(db: Database, now = new Date()) {
  const hour = now.toISOString().slice(0, 13);
  let after: string | undefined;
  do {
    const stores = await db.store.findMany({
      where: {
        status: { not: "archived" },
        ...(after ? { id: { gt: after } } : {}),
      },
      select: { id: true, organizationId: true },
      orderBy: { id: "asc" },
      take: 500,
    });
    if (!stores.length) break;
    await db.job.createMany({
      data: stores.map((s) => ({
        kind: "inventory-check",
        key: `inventory:${s.id}:${hour}`,
        payload: { storeId: s.id, organizationId: s.organizationId },
      })),
      skipDuplicates: true,
    });
    after = stores[stores.length - 1]!.id;
  } while (after);
}
