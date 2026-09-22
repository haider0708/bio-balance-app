import { z } from "zod";
import { DomainError } from "./errors";

export const syncCursor = z
  .string()
  .regex(/^\d{1,19}$/)
  .refine(
    (value) => BigInt(value) <= 9_223_372_036_854_775_807n,
    "Curseur hors limites.",
  );
const historyCursor = z
  .object({ id: z.uuid(), date: z.iso.datetime({ offset: true }) })
  .strict();

export function decodeHistoryCursor(value: string): { id: string; date: Date } {
  try {
    if (value.length > 300 || !/^[A-Za-z0-9_-]+$/.test(value))
      throw new Error();
    const parsed = historyCursor.parse(
      JSON.parse(Buffer.from(value, "base64url").toString("utf8")),
    );
    return { id: parsed.id, date: new Date(parsed.date) };
  } catch {
    throw new DomainError(
      "INVALID_CURSOR",
      "Page invalide. Actualisez l’historique.",
      400,
    );
  }
}
