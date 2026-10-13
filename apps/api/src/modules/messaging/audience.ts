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

/**
 * Whether an announcement went only to places the caller cannot see (the test region, hidden
 * from the admin): it is then left out of the admin's list, like everything else of that region.
 */
export async function aimsOnlyAtHidden(tx: Tx, audience: Audience) {
  if (audience.all) return false;
  const [regions, pdvs, users] = await Promise.all([
    audience.regionIds?.length
      ? tx.region.count({ where: { id: { in: audience.regionIds } } })
      : null,
    audience.pdvIds?.length
      ? tx.pdv.count({ where: { id: { in: audience.pdvIds } } })
      : null,
    audience.userIds?.length
      ? tx.user.count({ where: { id: { in: audience.userIds } } })
      : null,
  ]);
  const selectorsHidden =
    regions === 0 ||
    pdvs === 0 ||
    (regions === null && pdvs === null && !audience.roles?.length);
  const namedHidden = users === null || users === 0;
  return selectorsHidden && namedHidden;
}
