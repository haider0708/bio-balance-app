import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { createHash } from "node:crypto";
import { Database } from "./database";
import { DomainError } from "../domain/errors";

export type RequestCategory = "read" | "write" | "sync" | "export" | "media";
const LIMITS: Record<RequestCategory, number> = {
  read: 360,
  write: 180,
  sync: 600,
  export: 12,
  media: 600,
};

/** Fixed one-minute windows, shared across replicas and all an account's sessions.
 * Rejected attempts do not extend a window. No raw credentials are persisted.
 */
@Injectable()
export class RequestBudget {
  constructor(private readonly db: Database) {}

  async consume(userId: string, method: string, route: string, body?: unknown) {
    const category = requestCategory(method, route);
    const operations = (body as { operations?: unknown } | undefined)
      ?.operations;
    const cost =
      category === "sync" && Array.isArray(operations)
        ? Math.max(1, Math.min(100, operations.length))
        : 1;
    const account = createHash("sha256").update(userId).digest("hex");
    // Sorted keys give concurrent requests a consistent row-lock order.
    const entries = [
      { key: `${account}:all`, cost: 1, limit: 1200 },
      { key: `${account}:${category}`, cost, limit: LIMITS[category] },
    ].sort((a, b) => a.key.localeCompare(b.key));
    const values = entries.map(
      (e) => Prisma.sql`(${e.key}::text,${e.cost}::integer)`,
    );
    const rows = await this.db.$queryRaw<
      {
        key: string;
        count: number;
        retryAfterSeconds: number;
      }[]
    >(Prisma.sql`
      INSERT INTO "RequestBudget" (key,count,"windowStart")
      SELECT key,cost,CURRENT_TIMESTAMP FROM (VALUES ${Prisma.join(values)}) AS v(key,cost)
      ORDER BY key
      ON CONFLICT (key) DO UPDATE SET
        count=CASE WHEN "RequestBudget"."windowStart" <= CURRENT_TIMESTAMP - interval '1 minute'
          THEN EXCLUDED.count ELSE LEAST("RequestBudget".count+EXCLUDED.count,1000000) END,
        "windowStart"=CASE WHEN "RequestBudget"."windowStart" <= CURRENT_TIMESTAMP - interval '1 minute'
          THEN CURRENT_TIMESTAMP ELSE "RequestBudget"."windowStart" END
      RETURNING key,count,GREATEST(1,CEIL(EXTRACT(EPOCH FROM
        ("windowStart" + interval '1 minute' - CURRENT_TIMESTAMP)))::int) AS "retryAfterSeconds"
    `);
    const exceeded = rows.filter(
      (r) => r.count > entries.find((e) => e.key === r.key)!.limit,
    );
    if (exceeded.length)
      throw new DomainError(
        "RATE_LIMITED",
        "Trop de requêtes. Réessayez dans quelques instants ; vos opérations locales sont conservées.",
        429,
        {
          retryAfterSeconds: Math.max(
            ...exceeded.map((r) => r.retryAfterSeconds),
          ),
        },
      );
  }
}

export function requestCategory(
  method: string,
  route: string,
): RequestCategory {
  route = route.toLowerCase();
  if (
    route.startsWith("/v1/admin/") ||
    /\/snapshot\/?$/.test(route) ||
    route.startsWith("/v1/reports/") ||
    /\/(export|reporting)(\/|$)/.test(route)
  )
    return "export";
  if (route.startsWith("/v1/sync/")) return "sync";
  if (route.startsWith("/v1/media/")) return "media";
  return ["GET", "HEAD"].includes(method) ? "read" : "write";
}
