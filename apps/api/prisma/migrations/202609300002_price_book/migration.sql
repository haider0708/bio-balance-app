-- Append-only price book and points-rate history. Existing StoreProduct values
-- remain the cached "current" projection and every existing price and rate is
-- recorded as a first version; no past sale, order or ledger entry is changed.
--   wholesale    : BioBalance -> grossiste   (A)  organization = grossiste or NULL (default)
--   store_supply : supplier   -> store       (B)  store = exception or NULL (default)
--   retail       : store      -> customer    (C)  store required
CREATE TABLE "PriceVersion" (
  id uuid PRIMARY KEY,
  level text NOT NULL CHECK (level IN ('wholesale','store_supply','retail')),
  "productId" uuid NOT NULL REFERENCES "Product"(id),
  "organizationId" uuid,
  "storeId" uuid,
  "priceMillimes" bigint NOT NULL CHECK ("priceMillimes" >= 0),
  reason text,
  "operationId" uuid UNIQUE,
  "createdBy" uuid REFERENCES "User"(id),
  seeded boolean NOT NULL DEFAULT false,
  "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id),
  CHECK (
    (level = 'wholesale' AND "storeId" IS NULL)
    OR (level = 'store_supply' AND ("organizationId" IS NULL) = ("storeId" IS NULL))
    OR (level = 'retail' AND "organizationId" IS NOT NULL AND "storeId" IS NOT NULL))
);
CREATE INDEX "PriceVersion_lookup" ON "PriceVersion" (level, "productId", "storeId", "organizationId", "createdAt" DESC);
ALTER TABLE "PriceVersion" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PriceVersion" FORCE ROW LEVEL SECURITY;
-- A store reads and writes only its own retail price history.
CREATE POLICY "PriceVersion_retail_scope" ON "PriceVersion" USING (
  level='retail' AND "organizationId"::text=current_setting('app.organization_id',true)
  AND "storeId"::text=current_setting('app.store_id',true))
  WITH CHECK (
  level='retail' AND "organizationId"::text=current_setting('app.organization_id',true)
  AND "storeId"::text=current_setting('app.store_id',true));
-- Supply and wholesale prices are reachable only through the pricing use case,
-- which checks the caller's role and projects only the levels that role may see.
CREATE POLICY "PriceVersion_pricing_access" ON "PriceVersion" USING (current_setting('app.price_access',true)='true')
  WITH CHECK (current_setting('app.price_access',true)='true');
CREATE TRIGGER "PriceVersion_immutable" BEFORE UPDATE OR DELETE ON "PriceVersion"
  FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

CREATE TABLE "PointsRateVersion" (
  id uuid PRIMARY KEY,
  "organizationId" uuid NOT NULL,
  "storeId" uuid NOT NULL,
  "productId" uuid NOT NULL REFERENCES "Product"(id),
  "pointsPerUnit" integer NOT NULL CHECK ("pointsPerUnit" >= 0),
  reason text,
  "createdBy" uuid REFERENCES "User"(id),
  seeded boolean NOT NULL DEFAULT false,
  "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id)
);
CREATE INDEX "PointsRateVersion_lookup" ON "PointsRateVersion" ("storeId", "productId", "createdAt" DESC);
ALTER TABLE "PointsRateVersion" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PointsRateVersion" FORCE ROW LEVEL SECURITY;
CREATE POLICY "PointsRateVersion_scope" ON "PointsRateVersion" USING (
  "organizationId"::text=current_setting('app.organization_id',true) AND "storeId"::text=current_setting('app.store_id',true))
  WITH CHECK ("organizationId"::text=current_setting('app.organization_id',true) AND "storeId"::text=current_setting('app.store_id',true));
CREATE POLICY "PointsRateVersion_pricing_access" ON "PointsRateVersion" FOR SELECT USING (current_setting('app.price_access',true)='true');
CREATE TRIGGER "PointsRateVersion_immutable" BEFORE UPDATE OR DELETE ON "PointsRateVersion"
  FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

-- First versions: what is configured today. They apply to any past date.
INSERT INTO "PriceVersion" (id, level, "productId", "organizationId", "storeId", "priceMillimes", reason, seeded, "createdAt")
  SELECT gen_random_uuid(), 'retail', "productId", "organizationId", "storeId", "priceMillimes",
    'Prix existant à la mise en service de l’historique', true, TIMESTAMP '1970-01-01'
  FROM "StoreProduct" WHERE "priceConfigured";
INSERT INTO "PointsRateVersion" (id, "organizationId", "storeId", "productId", "pointsPerUnit", reason, seeded, "createdAt")
  SELECT gen_random_uuid(), "organizationId", "storeId", "productId", "pointsPerUnit",
    'Barème existant à la mise en service de l’historique', true, TIMESTAMP '1970-01-01'
  FROM "StoreProduct" WHERE "pointsConfigured";
