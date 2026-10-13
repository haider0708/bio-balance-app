import { json, type Tx } from "./database";

export interface SystemNotice {
  /** Translated by the phone, e.g. "pdv.approved". */
  key: string;
  params?: Record<string, unknown>;
  entityType?: string;
  entityId?: string;
  /** False for what belongs in the inbox only (each sale of a region): no phone is woken. */
  push?: boolean;
}

/** Drops a system notification into each person's inbox. */
export async function notify(tx: Tx, userIds: string[], notice: SystemNotice) {
  const ids = [...new Set(userIds)];
  if (!ids.length) return;
  // Automation acting for someone (Actor.quietAlerts): in the inbox, but never pushed to a phone.
  const [setting] = await tx.$queryRaw<{ quiet: boolean }[]>`
    SELECT current_setting('app.quiet_alerts', true) = 'on' AS quiet`;
  const quiet = setting?.quiet === true;
  await tx.notification.createMany({
    data: ids.map((userId) => ({
      userId,
      kind: "SYSTEM",
      key: notice.key,
      params: json(notice.params ?? {}),
      entityType: notice.entityType ?? null,
      entityId: notice.entityId ?? null,
      pushedAt: quiet || notice.push === false ? new Date() : null,
    })),
  });
}

export async function adminIds(tx: Tx): Promise<string[]> {
  const admins = await tx.user.findMany({
    where: { role: "ADMIN", status: "ACTIVE" },
    select: { id: true },
  });
  return admins.map((a) => a.id);
}

/**
 * Tells the admins about something that happened in `regionId`. Nothing done in the test region
 * (the store reviewers' accounts) reaches them.
 */
export async function notifyAdmins(
  tx: Tx,
  regionId: string | null | undefined,
  notice: SystemNotice,
) {
  if (regionId && (await isSandbox(tx, regionId))) return;
  await notify(tx, await adminIds(tx), notice);
}

/** Whether a region is the test region. */
export async function isSandbox(tx: Tx, regionId: string) {
  const region = await tx.region.findUnique({
    where: { id: regionId },
    select: { sandbox: true },
  });
  return region?.sandbox === true;
}

/** The active responsable of a region (there is one per region). */
export async function responsableIds(tx: Tx, regionId: string) {
  const rows = await tx.user.findMany({
    where: { role: "RESPONSABLE", status: "ACTIVE", regionId },
    select: { id: true },
  });
  return rows.map((r) => r.id);
}
