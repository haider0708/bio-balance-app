import { z } from "zod";
import { dashboardQuery, DashboardQuery } from "./dashboard.contracts";
export const historyExportQuery = z
  .object({
    kind: z.literal("history"),
    organizationId: z.uuid(),
    storeId: z.uuid(),
    resource: z.enum(["movements", "points", "audit"]),
    productId: z.uuid().optional(),
  })
  .strict();
export const exportQuery = z.union([historyExportQuery, dashboardQuery]);
export type ExportQuery = z.infer<typeof exportQuery>;
export function exportScope(query: ExportQuery): DashboardQuery {
  if (!("kind" in query)) return query;
  return {
    scope: query.resource === "points" ? "personal" : "store",
    organizationId: query.organizationId,
    storeId: query.storeId,
    // History exports include the full append-only history. These dates only
    // satisfy the shared authorization context and do not filter their rows.
    from: "1970-01-01",
    to: "1970-01-01",
  };
}
