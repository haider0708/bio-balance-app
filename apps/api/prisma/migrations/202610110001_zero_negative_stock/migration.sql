-- A sale can no longer take stock below zero. Rows that went negative before that rule
-- are brought back to zero with a correction in the history (the history is never edited).
INSERT INTO "StockMovement" (id, "locationId", "productId", "locationKind", "regionId", delta, reason, "refType", "refId", "createdAt")
SELECT gen_random_uuid(), s."locationId", s."productId", s."locationKind", s."regionId", -s.quantity, 'ADJUSTMENT', 'Correction', gen_random_uuid(), now()
FROM "Stock" s WHERE s.quantity < 0;
UPDATE "Stock" SET quantity = 0, "updatedAt" = now() WHERE quantity < 0;
