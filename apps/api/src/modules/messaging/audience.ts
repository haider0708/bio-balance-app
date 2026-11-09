import type { Role } from "@prisma/client";
import type { Tx } from "../../core/database";

/** Who a message is for. Selectors combine ("vendeurs of the Nord region"); `userIds` are added on top. */
export interface Audience {
  all?: boolean;
  roles?: Role[];
  regionIds?: string[];
  pdvIds?: string[];
  userIds?: string[];
}

/** The active people an audience reaches. The admin is never a recipient of announcements. */
export async function resolveAudience(tx: Tx, audience: Audience) {
  const base = { status: "ACTIVE" as const, role: { not: "ADMIN" as const } };
  if (audience.all)
    return tx.user.findMany({
      where: base,
      select: { id: true, role: true, regionId: true },
    });
  const filters = [
    ...(audience.roles?.length
      ? [{ role: { in: audience.roles.filter((r) => r !== "ADMIN") } }]
      : []),
    ...(audience.regionIds?.length
      ? [{ regionId: { in: audience.regionIds } }]
      : []),
    ...(audience.pdvIds?.length ? [{ pdvId: { in: audience.pdvIds } }] : []),
  ];
  const selected = filters.length
    ? await tx.user.findMany({
        where: { ...base, AND: filters },
        select: { id: true, role: true, regionId: true },
      })
    : [];
  const named = audience.userIds?.length
    ? await tx.user.findMany({
        where: { ...base, id: { in: audience.userIds } },
        select: { id: true, role: true, regionId: true },
      })
    : [];
  return [...new Map([...selected, ...named].map((u) => [u.id, u])).values()];
}

/** The one region every recipient belongs to, if they all share one (the audit entry is filed under it). */
export function audienceRegion(users: { regionId: string | null }[]) {
  const regions = new Set(users.map((u) => u.regionId));
  return regions.size === 1 ? [...regions][0]! : null;
}
