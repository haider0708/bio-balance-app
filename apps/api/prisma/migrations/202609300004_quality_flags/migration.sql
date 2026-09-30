-- Damaged or expired goods are flagged, held out of sale at once, and decided by
-- BioBalance alone. A flag is kept for good: only its one decision may be added.
CREATE TABLE "QualityFlag" (
  id uuid PRIMARY KEY,
  "organizationId" uuid NOT NULL,
  "storeId" uuid NOT NULL,
  "lotId" uuid NOT NULL,
  -- The lot as it was flagged, so the record never depends on later stock changes.
  batch text NOT NULL,
  expiry date NOT NULL,
  "productId" uuid NOT NULL REFERENCES "Product"(id),
  quantity integer NOT NULL CHECK (quantity > 0),
  kind text NOT NULL CHECK (kind IN ('damaged','expired')),
  note text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','confirmed','rejected')),
  "flaggedBy" uuid NOT NULL REFERENCES "User"(id),
  "flaggedAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "decidedBy" uuid REFERENCES "User"(id),
  "decidedAt" timestamp(3),
  "decisionNote" text,
  "sourceDeliveryId" uuid,
  "sourceTicket" text,
  "valueMillimes" bigint,
  "operationId" uuid NOT NULL,
  version integer NOT NULL DEFAULT 1,
  FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id),
  FOREIGN KEY ("storeId","lotId") REFERENCES "InventoryLot"("storeId",id),
  CHECK ((status = 'open') = ("decidedBy" IS NULL AND "decidedAt" IS NULL))
);
CREATE INDEX "QualityFlag_store_status" ON "QualityFlag" ("storeId", status, "flaggedAt" DESC);
CREATE INDEX "QualityFlag_group_status" ON "QualityFlag" ("organizationId", status, "flaggedAt" DESC);
ALTER TABLE "QualityFlag" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "QualityFlag" FORCE ROW LEVEL SECURITY;
CREATE POLICY "QualityFlag_scope" ON "QualityFlag" USING (
  "organizationId"::text=current_setting('app.organization_id',true) AND "storeId"::text=current_setting('app.store_id',true))
  WITH CHECK ("organizationId"::text=current_setting('app.organization_id',true) AND "storeId"::text=current_setting('app.store_id',true));
CREATE POLICY "QualityFlag_admin_read" ON "QualityFlag" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "QualityFlag_group_read" ON "QualityFlag" FOR SELECT USING (
  current_setting('app.group_read',true)='true' AND "organizationId"::text=current_setting('app.organization_id',true)
  AND EXISTS (SELECT 1 FROM "OrganizationMembership" gm WHERE gm."organizationId"="QualityFlag"."organizationId"
    AND gm."userId"::text=current_setting('app.actor_id',true) AND gm.active));
CREATE FUNCTION quality_flag_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Quality flags are kept for good'; END IF;
  IF OLD.status <> 'open' THEN RAISE EXCEPTION 'A decided flag is final'; END IF;
  IF NEW.id <> OLD.id OR NEW."storeId" <> OLD."storeId" OR NEW."lotId" <> OLD."lotId"
     OR NEW.quantity <> OLD.quantity OR NEW.kind <> OLD.kind OR NEW."flaggedBy" <> OLD."flaggedBy"
     OR NEW."flaggedAt" <> OLD."flaggedAt" OR NEW."operationId" <> OLD."operationId" THEN
    RAISE EXCEPTION 'The facts of a flag cannot change';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER "QualityFlag_guard" BEFORE UPDATE OR DELETE ON "QualityFlag"
  FOR EACH ROW EXECUTE FUNCTION quality_flag_guard();
