ALTER TABLE "Store" ADD COLUMN "workingAlone" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "noOpeningStock" BOOLEAN NOT NULL DEFAULT false, ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "StoreProduct" ADD COLUMN "zeroPointsConfirmed" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "MediaAsset" ADD COLUMN "organizationId" UUID, ADD COLUMN "storeId" UUID,
  ADD COLUMN purpose TEXT NOT NULL DEFAULT 'training', ADD COLUMN "expectedSha256" TEXT, ADD COLUMN "processedSize" BIGINT;
ALTER TABLE "MediaAsset" ADD CONSTRAINT "MediaAsset_scope_check" CHECK (
  (purpose IN ('store','reward') AND "organizationId" IS NOT NULL AND "storeId" IS NOT NULL)
  OR (purpose IN ('training','catalog') AND "organizationId" IS NULL AND "storeId" IS NULL));
CREATE INDEX "MediaAsset_storeId_purpose_idx" ON "MediaAsset"("storeId",purpose);
