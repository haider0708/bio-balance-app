import { z } from "zod";
const name = z.string().trim().min(2).max(120);
export const GroupRequests = {
  Create: z
    .object({
      grantId: z.uuid(),
      operationId: z.uuid(),
      name,
      phone: z.string().trim().max(30).optional(),
    })
    .strict(),
  Update: z
    .object({
      name,
      phone: z.string().trim().max(30).nullable().optional(),
      imageId: z.uuid().nullable().optional(),
      expectedVersion: z.number().int().positive(),
    })
    .strict(),
  Member: z
    .object({
      active: z.boolean(),
      role: z.enum(["responsible", "salesperson"]),
      storeIds: z
        .array(z.uuid())
        .max(1, "Un vendeur est affecté à un seul magasin.")
        .default([]),
    })
    .strict(),
};
export const groupListQuery = z.object({
  after: z.uuid().optional(),
  search: z.string().trim().max(120).optional(),
});
