-- Transfers of products between two paras of the same group. The admin approves the quantities;
-- only then does the stock move (one transaction, two history lines per product).
CREATE TYPE "TransferStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'EXPIRED');
CREATE TYPE "TransferDirection" AS ENUM ('SEND', 'REQUEST');
CREATE SEQUENCE "transfer_number_seq";

CREATE TABLE "StockTransfer" (
  "id" UUID NOT NULL,
  "number" TEXT NOT NULL,
  "regionId" UUID NOT NULL,
  "groupId" UUID NOT NULL,
  "fromPdvId" UUID NOT NULL,
  "toPdvId" UUID NOT NULL,
  "direction" "TransferDirection" NOT NULL,
  "status" "TransferStatus" NOT NULL DEFAULT 'PENDING',
  "createdById" UUID NOT NULL,
  "photoId" UUID,
  "note" TEXT,
  "revision" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMP(3),
  "decidedById" UUID,
  "decidedAt" TIMESTAMP(3),
  "decisionNote" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StockTransfer_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "StockTransfer_places_check" CHECK ("fromPdvId" <> "toPdvId"),
  CONSTRAINT "StockTransfer_note_check" CHECK ("note" IS NULL OR char_length("note") <= 300),
  CONSTRAINT "StockTransfer_decision_check" CHECK ("decisionNote" IS NULL OR char_length("decisionNote") <= 300)
);
CREATE UNIQUE INDEX "StockTransfer_number_key" ON "StockTransfer"("number");
CREATE INDEX "StockTransfer_regionId_status_idx" ON "StockTransfer"("regionId", "status");
CREATE INDEX "StockTransfer_fromPdvId_status_idx" ON "StockTransfer"("fromPdvId", "status");
CREATE INDEX "StockTransfer_toPdvId_status_idx" ON "StockTransfer"("toPdvId", "status");
CREATE INDEX "StockTransfer_status_expiresAt_idx" ON "StockTransfer"("status", "expiresAt");

CREATE TABLE "TransferLine" (
  "id" UUID NOT NULL,
  "transferId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "quantity" INTEGER NOT NULL,
  "requestedQuantity" INTEGER NOT NULL,
  CONSTRAINT "TransferLine_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "TransferLine_quantity_check" CHECK ("quantity" > 0 AND "requestedQuantity" >= 0)
);
CREATE UNIQUE INDEX "TransferLine_transferId_productId_key" ON "TransferLine"("transferId", "productId");
ALTER TABLE "TransferLine" ADD CONSTRAINT "TransferLine_transferId_fkey"
  FOREIGN KEY ("transferId") REFERENCES "StockTransfer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "TransferRevision" (
  "id" UUID NOT NULL,
  "transferId" UUID NOT NULL,
  "version" INTEGER NOT NULL,
  "editorId" UUID NOT NULL,
  "before" JSONB NOT NULL,
  "after" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TransferRevision_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "TransferRevision_transferId_version_key" ON "TransferRevision"("transferId", "version");
ALTER TABLE "TransferRevision" ADD CONSTRAINT "TransferRevision_transferId_fkey"
  FOREIGN KEY ("transferId") REFERENCES "StockTransfer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE TRIGGER "TransferRevision_append_only" BEFORE UPDATE OR DELETE ON "TransferRevision"
  FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

-- Who sees a transfer: the admin (not the test region unless asked), the responsable of its region,
-- and a team member of either para. Trusted server work (SYSTEM) is the admin's.
CREATE FUNCTION app_sees_transfer(region uuid, from_pdv uuid, to_pdv uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_admin_sees(region) OR app_in_region(region)
    OR (app_role() = 'VENDEUR' AND (from_pdv = app_pdv() OR to_pdv = app_pdv())) $$;

ALTER TABLE "StockTransfer" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "StockTransfer" FORCE ROW LEVEL SECURITY;
CREATE POLICY "StockTransfer_rls" ON "StockTransfer"
  USING (app_sees_transfer("regionId", "fromPdvId", "toPdvId"))
  WITH CHECK (app_sees_transfer("regionId", "fromPdvId", "toPdvId"));

ALTER TABLE "TransferLine" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "TransferLine" FORCE ROW LEVEL SECURITY;
CREATE POLICY "TransferLine_rls" ON "TransferLine"
  USING (EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));

ALTER TABLE "TransferRevision" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "TransferRevision" FORCE ROW LEVEL SECURITY;
CREATE POLICY "TransferRevision_rls" ON "TransferRevision"
  USING (EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));
