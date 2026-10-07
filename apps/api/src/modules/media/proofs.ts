import type { Actor } from "../../core/actor";
import type { Tx } from "../../core/database";
import { requireRule } from "../../core/errors";

export const MAX_PROOF_PHOTOS = 5;

/**
 * The photos a person attaches to a count or a delivery: one to five distinct
 * proof photos they uploaded themselves. Returned in the order they chose.
 */
export async function ownedProofs(
  tx: Tx,
  actor: Actor,
  ids: string[],
  missing: string,
): Promise<string[]> {
  requireRule(ids.length >= 1, "PHOTO_REQUIRED", missing, 422);
  requireRule(
    ids.length <= MAX_PROOF_PHOTOS && new Set(ids).size === ids.length,
    "TOO_MANY_PHOTOS",
    `Add between 1 and ${MAX_PROOF_PHOTOS} different photos.`,
    422,
  );
  const found = await tx.mediaAsset.findMany({
    where: { id: { in: ids }, purpose: "PROOF", ownerId: actor.id },
    select: { id: true },
  });
  requireRule(found.length === ids.length, "PHOTO_REQUIRED", missing, 422);
  return ids;
}
