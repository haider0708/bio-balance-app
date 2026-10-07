-- A grossiste's count is first checked by the responsable of the region (REVIEW), then by the admin.
ALTER TYPE "Approval" ADD VALUE 'REVIEW';
ALTER TABLE "StockDeclaration" ADD COLUMN "reviewedById" UUID, ADD COLUMN "reviewedAt" TIMESTAMP(3), ADD COLUMN "reviewNote" TEXT;

-- A depot's stock belongs to the region of its grossiste, so that region's responsable can read it.
UPDATE "Stock" s SET "regionId" = d."regionId" FROM "Depot" d WHERE s."locationId" = d.id;
UPDATE "StockMovement" m SET "regionId" = d."regionId" FROM "Depot" d WHERE m."locationId" = d.id;
UPDATE "StockDeclaration" x SET "regionId" = d."regionId" FROM "Depot" d WHERE x."locationId" = d.id;

-- Counting a place again needs the admin's permission, used once.
CREATE TABLE "StockRecount" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "locationId" UUID NOT NULL,
  "locationKind" "LocationKind" NOT NULL,
  "regionId" UUID,
  "requestedById" UUID NOT NULL,
  "reason" TEXT NOT NULL,
  "status" "Approval" NOT NULL DEFAULT 'PENDING',
  "decidedById" UUID,
  "decidedAt" TIMESTAMP(3),
  "decisionNote" TEXT,
  "declarationId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StockRecount_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "StockRecount_status_createdAt_idx" ON "StockRecount"("status", "createdAt");
CREATE INDEX "StockRecount_locationId_status_idx" ON "StockRecount"("locationId", "status");
ALTER TABLE "StockRecount" ADD CONSTRAINT "StockRecount_requester_fk" FOREIGN KEY ("requestedById") REFERENCES "User"(id);
ALTER TABLE "StockRecount" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "StockRecount" FORCE ROW LEVEL SECURITY;
CREATE POLICY "StockRecount_rls" ON "StockRecount"
  USING (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot())
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot());
