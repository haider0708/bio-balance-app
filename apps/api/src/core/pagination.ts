import { z } from "zod";

export const PageQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(30),
  cursor: z.string().max(200).optional(),
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Keyset pagination over (createdAt, id): stable while rows are added. */
function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString("base64url");
}

export function decodeCursor(
  cursor: string | undefined,
): { createdAt: Date; id: string } | undefined {
  if (!cursor) return undefined;
  try {
    const [at, id] = Buffer.from(cursor, "base64url").toString().split("|");
    const createdAt = new Date(at ?? "");
    // A cursor the server did not write (edited or truncated) restarts at the first page.
    if (!id || !UUID.test(id) || Number.isNaN(createdAt.getTime()))
      return undefined;
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
      rows.length > limit && last
        ? encodeCursor(last.createdAt, last.id)
        : null,
  };
}
