-- Returns: quantities taken out of a para's stock. A responsable asks, the admin decides; made by
-- the admin it applies at once.
CREATE TYPE "ReturnStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'EXPIRED');
CREATE SEQUENCE "return_number_seq";

CREATE TABLE "StockReturn" (
  "id" UUID NOT NULL,
  "number" TEXT NOT NULL,
  "regionId" UUID NOT NULL,
  "pdvId" UUID NOT NULL,
  "status" "ReturnStatus" NOT NULL DEFAULT 'PENDING',
  "createdById" UUID NOT NULL,
  "note" TEXT,
  "revision" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMP(3),
  "decidedById" UUID,
  "decidedAt" TIMESTAMP(3),
  "decisionNote" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StockReturn_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "StockReturn_note_check" CHECK ("note" IS NULL OR char_length("note") <= 300),
  CONSTRAINT "StockReturn_decision_check" CHECK ("decisionNote" IS NULL OR char_length("decisionNote") <= 300)
);
CREATE UNIQUE INDEX "StockReturn_number_key" ON "StockReturn"("number");
CREATE INDEX "StockReturn_regionId_status_idx" ON "StockReturn"("regionId", "status");
CREATE INDEX "StockReturn_pdvId_status_idx" ON "StockReturn"("pdvId", "status");
CREATE INDEX "StockReturn_status_expiresAt_idx" ON "StockReturn"("status", "expiresAt");

CREATE TABLE "ReturnLine" (
  "id" UUID NOT NULL,
  "returnId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "quantity" INTEGER NOT NULL,
  "requestedQuantity" INTEGER NOT NULL,
  CONSTRAINT "ReturnLine_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ReturnLine_quantity_check" CHECK ("quantity" > 0 AND "requestedQuantity" >= 0)
);
CREATE UNIQUE INDEX "ReturnLine_returnId_productId_key" ON "ReturnLine"("returnId", "productId");
ALTER TABLE "ReturnLine" ADD CONSTRAINT "ReturnLine_returnId_fkey"
  FOREIGN KEY ("returnId") REFERENCES "StockReturn"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "ReturnRevision" (
  "id" UUID NOT NULL,
  "returnId" UUID NOT NULL,
  "version" INTEGER NOT NULL,
  "editorId" UUID NOT NULL,
  "before" JSONB NOT NULL,
  "after" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ReturnRevision_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "ReturnRevision_returnId_version_key" ON "ReturnRevision"("returnId", "version");
ALTER TABLE "ReturnRevision" ADD CONSTRAINT "ReturnRevision_returnId_fkey"
  FOREIGN KEY ("returnId") REFERENCES "StockReturn"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE TRIGGER "ReturnRevision_append_only" BEFORE UPDATE OR DELETE ON "ReturnRevision"
  FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

-- Who sees a return: the admin (not the test region unless asked) and the responsable of its region.
-- Team members have nothing to do with returns. Trusted server work (SYSTEM) is the admin's.
ALTER TABLE "StockReturn" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "StockReturn" FORCE ROW LEVEL SECURITY;
CREATE POLICY "StockReturn_rls" ON "StockReturn"
  USING (app_admin_sees("regionId") OR app_in_region("regionId"))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId"));

ALTER TABLE "ReturnLine" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReturnLine" FORCE ROW LEVEL SECURITY;
CREATE POLICY "ReturnLine_rls" ON "ReturnLine"
  USING (EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"));

ALTER TABLE "ReturnRevision" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReturnRevision" FORCE ROW LEVEL SECURITY;
CREATE POLICY "ReturnRevision_rls" ON "ReturnRevision"
  USING (EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"));
