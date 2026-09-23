import { z } from "zod";
export const dashboardQuery = z
  .object({
    scope: z.enum(["network", "group", "store", "personal"]),
    organizationId: z.uuid().optional(),
    storeId: z.uuid().optional(),
    from: z.iso.date(),
    to: z.iso.date(),
  })
  .superRefine((q, c) => {
    const days = (Date.parse(q.to) - Date.parse(q.from)) / 86400000;
    if (days < 0 || days > 365)
      c.addIssue({
        code: "custom",
        message: "Choisissez une période de 1 à 366 jours.",
      });
    if (q.scope !== "network" && !q.organizationId)
      c.addIssue({ code: "custom", message: "Groupe requis." });
    if (["store", "personal"].includes(q.scope) && !q.storeId)
      c.addIssue({ code: "custom", message: "Magasin requis." });
    if (
      (q.scope === "network" && (q.organizationId || q.storeId)) ||
      (q.scope === "group" && q.storeId)
    )
      c.addIssue({ code: "custom", message: "Périmètre incohérent." });
  });
export type DashboardQuery = z.infer<typeof dashboardQuery>;
