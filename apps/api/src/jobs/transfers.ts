import type { Database } from "../core/database";
import { TransfersService } from "../modules/transfers/transfers.service";

/** Once an hour: transfers the admin did not decide in time are dropped (see TRANSFER_LIFE_MS). */
export async function scheduleTransferJobs(db: Database, now = new Date()) {
  await db.job.createMany({
    data: [
      {
        kind: "transfer-expire",
        key: `transfer-expire:${now.toISOString().slice(0, 13)}`,
        payload: {},
      },
    ],
    skipDuplicates: true,
  });
}

export function expireTransfers(db: Database, now = new Date()) {
  return new TransfersService(db).expire(now);
}
