import { z } from "zod";

const millimes = z.string().regex(/^(0|[1-9]\d{0,14})$/);
export const PricingRequests = {
  // BioBalance sets wholesale (A) and store-supply (B) prices; a store sets its own retail price elsewhere.
  Set: z
    .object({
      operationId: z.uuid(),
      level: z.enum(["wholesale", "store_supply"]),
      productId: z.uuid(),
      // wholesale: a grossiste organization; store_supply: the store's organization.
      organizationId: z.uuid().optional(),
      // store_supply only: an exception for one store. Without it, the default price.
      storeId: z.uuid().optional(),
      priceMillimes: millimes,
      reason: z.string().trim().min(3).max(300).optional(),
    })
    .strict(),
};
export const currentPricesQuery = z.object({
  organizationId: z.uuid(),
  storeId: z.uuid(),
});
export const priceHistoryQuery = z.object({
  productId: z.uuid(),
  organizationId: z.uuid().optional(),
  storeId: z.uuid().optional(),
  level: z.enum(["wholesale", "store_supply", "retail"]).optional(),
});
