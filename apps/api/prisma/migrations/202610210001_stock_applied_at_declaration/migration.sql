-- A stock count now reaches the place's stock when it is declared (sellers can sell at once); the
-- admin's approval verifies it. Each line remembers how much it has put into stock, so every
-- later change (an edit, a correction, the admin's amendment) applies only the difference and
-- never overwrites the sales made in between.
ALTER TABLE "StockDeclarationLine"
  ADD COLUMN "appliedQuantity" INTEGER,
  ADD COLUMN "addedByAdmin" BOOLEAN NOT NULL DEFAULT false;

-- While the responsable corrects a waiting count, it is on hold: the admin cannot decide it.
ALTER TABLE "StockDeclaration"
  ADD COLUMN "editingById" UUID,
  ADD COLUMN "editingUntil" TIMESTAMP(3),
  ADD COLUMN "correctedAt" TIMESTAMP(3);

-- Counts approved before this change put exactly their approved quantity into stock.
UPDATE "StockDeclarationLine" l SET "appliedQuantity" = l."approvedQuantity"
FROM "StockDeclaration" d
WHERE d.id = l."declarationId" AND d.status = 'APPROVED' AND l."approvedQuantity" IS NOT NULL;
