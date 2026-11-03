import type { Database } from "../core/database";
import { ReturnsService } from "../modules/returns/returns.service";

/** Once an hour: returns the admin did not decide in time are dropped (see RETURN_LIFE_MS). */
export async function scheduleReturnJobs(db: Database, now = new Date()) {
  await db.job.createMany({
    data: [
      {
        kind: "return-expire",
        key: `return-expire:${now.toISOString().slice(0, 13)}`,
        payload: {},
      },
    ],
    skipDuplicates: true,
  });
}

export function expireReturns(db: Database, now = new Date()) {
  return new ReturnsService(db).expire(now);
}
