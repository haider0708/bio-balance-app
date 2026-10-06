import { z } from "zod";

export const PageQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(30),
  cursor: z.string().max(200).optional(),
});

/** Keyset pagination over (createdAt, id): stable while rows are added. */
export function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString("base64url");
}

export function decodeCursor(
  cursor: string | undefined,
): { createdAt: Date; id: string } | undefined {
  if (!cursor) return undefined;
  try {
    const [at, id] = Buffer.from(cursor, "base64url").toString().split("|");
    const createdAt = new Date(at ?? "");
    if (!id || Number.isNaN(createdAt.getTime())) return undefined;
    return { createdAt, id };
  } catch {
    return undefined;
  }
}

export function page<T extends { id: string; createdAt: Date }>(
  rows: T[],
  limit: number,
) {
  const items = rows.slice(0, limit);
  const last = items.at(-1);
  return {
    items,
    nextCursor:
      rows.length > limit && last ? encodeCursor(last.createdAt, last.id) : null,
  };
}
