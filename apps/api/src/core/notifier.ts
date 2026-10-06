import { json, type Tx } from "./database";

export interface SystemNotice {
  /** Translated by the phone, e.g. "pdv.approved". */
  key: string;
  params?: Record<string, unknown>;
  entityType?: string;
  entityId?: string;
}

/** Drops a system notification into each person's inbox. */
export async function notify(tx: Tx, userIds: string[], notice: SystemNotice) {
  const ids = [...new Set(userIds)];
  if (!ids.length) return;
  await tx.notification.createMany({
    data: ids.map((userId) => ({
      userId,
      kind: "SYSTEM",
      key: notice.key,
      params: json(notice.params ?? {}),
      entityType: notice.entityType ?? null,
      entityId: notice.entityId ?? null,
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

export async function notifyAdmins(tx: Tx, notice: SystemNotice) {
  await notify(tx, await adminIds(tx), notice);
}

/** The active responsable of a region (there is one per region). */
export async function responsableIds(tx: Tx, regionId: string) {
  const rows = await tx.user.findMany({
    where: { role: "RESPONSABLE", status: "ACTIVE", regionId },
    select: { id: true },
  });
  return rows.map((r) => r.id);
}
