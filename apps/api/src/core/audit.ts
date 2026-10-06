import type { Actor } from "./actor";
import { json, type Tx } from "./database";

/** Who did what, when. Written in the same transaction as the change itself. */
export async function audit(
  tx: Tx,
  actor: Actor | null,
  action: string,
  entity: string,
  entityId: string,
  details: Record<string, unknown> = {},
  regionId?: string | null,
) {
  await tx.auditEntry.createMany({
    data: [
      {
        actorId: actor?.id ?? null,
        action,
        entity,
        entityId,
        regionId: regionId ?? null,
        details: json(details),
      },
    ],
  });
}
