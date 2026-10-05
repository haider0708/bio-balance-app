import { z } from "zod";

const audience = z.enum(["retail", "wholesale"]);
export const GamificationRequests = {
  // BioBalance's default rate for every store (retail) or every depot (wholesale).
  PointsDefault: z
    .object({
      audience,
      productId: z.uuid(),
      pointsPerUnit: z.number().int().min(0).max(1_000_000),
      reason: z.string().trim().min(3).max(300).optional(),
    })
    .strict(),
  // A reward offered in every store (retail) or every depot (wholesale).
  RewardTemplate: z
    .object({
      id: z.uuid().optional(),
      audience,
      title: z.string().trim().min(2).max(120),
      description: z.string().trim().max(1000).default(""),
      cost: z.number().int().min(1).max(10_000_000),
      productId: z.uuid().nullable().optional(),
      quantity: z.number().int().min(1).max(1000).default(1),
      active: z.boolean().default(true),
      expectedVersion: z.number().int().min(1).optional(),
    })
    .strict(),
  // A store's or depot's own rate (an exception), or back to the default.
  StorePoints: z
    .object({
      productId: z.uuid(),
      pointsPerUnit: z.number().int().min(0).max(1_000_000).optional(),
      reset: z.boolean().optional(),
    })
    .strict()
    .refine((v) => v.reset === true || v.pointsPerUnit !== undefined, {
      message: "Indiquez les points ou revenez au barème par défaut.",
    }),
};
export const defaultsQuery = z.object({ audience });
