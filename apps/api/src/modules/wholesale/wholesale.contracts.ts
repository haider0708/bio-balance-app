import { z } from "zod";

const text = (min: number, max: number) => z.string().trim().min(min).max(max);
export const WholesaleRequests = {
  Create: z
    .object({
      operationId: z.uuid(),
      name: text(2, 120),
      email: z.email().trim().toLowerCase(),
      address: text(3, 300),
      city: text(2, 120),
      phone: z.string().trim().max(30).optional(),
    })
    .strict(),
};
export const supplierOrdersQuery = z.object({
  organizationId: z.uuid(),
  storeId: z.uuid(),
  after: z.uuid().optional(),
  phase: z.enum(["open", "complete", "all"]).default("open"),
});
export const supplierOrderQuery = supplierOrdersQuery.pick({
  organizationId: true,
  storeId: true,
});
