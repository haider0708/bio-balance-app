import { randomUUID } from "node:crypto";
import type { Database } from "../core/database";

export interface ClaimedJob {
  id: string;
  kind: string;
  key: string;
  payload: Record<string, unknown>;
  attempts: number;
  leaseToken: string;
}
export type JobExecutor = (
  job: ClaimedJob,
  stillOwned: () => Promise<boolean>,
) => Promise<void>;

const MAX_ATTEMPTS = 8;

/**
 * A small durable queue on PostgreSQL. A worker leases one job at a time
 * (FOR UPDATE SKIP LOCKED), renews the lease while it works, and retries failures
 * with exponential backoff.
 */
export class JobRunner {
  constructor(
    private readonly db: Database,
    private readonly kinds: string[],
    private readonly execute: JobExecutor,
    private readonly leaseMs = 900_000,
    private readonly random = Math.random,
  ) {}

  async claim(): Promise<ClaimedJob | null> {
    const token = randomUUID();
    const stale = new Date(Date.now() - this.leaseMs);
    const jobs = await this.db.$queryRaw<ClaimedJob[]>`
      UPDATE "Job" SET status='running', "lockedAt"=now(), "leaseToken"=${token}::uuid, attempts=attempts+1
      WHERE id = (SELECT id FROM "Job"
        WHERE ((status='pending' AND "availableAt"<=now()) OR (status='running' AND "lockedAt"<${stale}))
          AND kind = ANY(${this.kinds}::text[])
        ORDER BY "availableAt", id FOR UPDATE SKIP LOCKED LIMIT 1)
      RETURNING id, kind, key, payload, attempts, "leaseToken"`;
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

  /** Finished jobs keep no payload: it may hold a one-time code. */
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
    const terminal = job.attempts >= MAX_ATTEMPTS;
    // Provider errors can contain addresses or codes: keep only a safe machine word.
    const message =
      error instanceof Error && /^[A-Z][A-Z0-9_]{1,79}$/.test(error.message)
        ? error.message
        : "JOB_EXECUTION_FAILED";
    const delay =
      Math.min(3_600_000, 1000 * 2 ** Math.min(job.attempts, 12)) *
      (0.8 + this.random() * 0.2);
    await this.db.job.updateMany({
      where: this.owned(job),
      data: {
        status: terminal ? "failed" : "pending",
        ...(terminal && job.kind === "email" ? { payload: {} } : {}),
        availableAt: new Date(Date.now() + delay),
        lastError: message,
        leaseToken: null,
        lockedAt: null,
      },
    });
  }

  /** Run one job if there is one. Returns whether it found work. */
  async tick() {
    const job = await this.claim();
    if (!job) return false;
    let renewing = false;
    const timer = setInterval(
      () => {
        if (renewing) return;
        renewing = true;
        void this.renew(job)
          .catch(() => false)
          .finally(() => (renewing = false));
      },
      Math.max(100, Math.floor(this.leaseMs / 3)),
    );
    try {
      if (job.attempts > MAX_ATTEMPTS)
        throw new Error("JOB_ATTEMPTS_EXHAUSTED");
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
      clearInterval(timer);
    }
    return true;
  }
}
