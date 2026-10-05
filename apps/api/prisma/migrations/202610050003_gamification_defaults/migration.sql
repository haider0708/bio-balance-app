-- Points and rewards have a default, set by BioBalance for every store (retail)
-- or every grossiste depot (wholesale), and exceptions per store or depot.
-- Defaults are copied into each place, so sales, claims, history and row-level
-- security keep working on the place's own rows.
CREATE TABLE "PointsDefault" (
  id uuid PRIMARY KEY,
  audience text NOT NULL CHECK (audience IN ('retail','wholesale')),
  "productId" uuid NOT NULL REFERENCES "Product"(id),
  "pointsPerUnit" integer NOT NULL CHECK ("pointsPerUnit" >= 0),
  reason text,
  "createdBy" uuid REFERENCES "User"(id),
  "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "PointsDefault_lookup" ON "PointsDefault" (audience, "productId", "createdAt" DESC);
ALTER TABLE "PointsDefault" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PointsDefault" FORCE ROW LEVEL SECURITY;
-- Defaults are the same for everyone: any place reads them, BioBalance writes them.
CREATE POLICY "PointsDefault_read" ON "PointsDefault" FOR SELECT USING (true);
CREATE POLICY "PointsDefault_write" ON "PointsDefault" FOR INSERT
  WITH CHECK (current_setting('app.gamification_admin',true)='true');
CREATE TRIGGER "PointsDefault_immutable" BEFORE UPDATE OR DELETE ON "PointsDefault"
  FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

CREATE TABLE "RewardTemplate" (
  id uuid PRIMARY KEY,
  audience text NOT NULL CHECK (audience IN ('retail','wholesale')),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  cost integer NOT NULL CHECK (cost > 0),
  "productId" uuid REFERENCES "Product"(id),
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  active boolean NOT NULL DEFAULT true,
  version integer NOT NULL DEFAULT 1,
  "createdBy" uuid REFERENCES "User"(id),
  "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE "RewardTemplate" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "RewardTemplate" FORCE ROW LEVEL SECURITY;
CREATE POLICY "RewardTemplate_read" ON "RewardTemplate" FOR SELECT USING (true);
CREATE POLICY "RewardTemplate_insert" ON "RewardTemplate" FOR INSERT
  WITH CHECK (current_setting('app.gamification_admin',true)='true');
CREATE POLICY "RewardTemplate_update" ON "RewardTemplate" FOR UPDATE
  USING (current_setting('app.gamification_admin',true)='true')
  WITH CHECK (current_setting('app.gamification_admin',true)='true');

-- A place's copy of a default reward; its own rewards have no template.
ALTER TABLE "Reward" ADD COLUMN "templateId" uuid REFERENCES "RewardTemplate"(id);
CREATE UNIQUE INDEX "Reward_store_template" ON "Reward" ("storeId", "templateId")
  WHERE "templateId" IS NOT NULL;
-- A place's own rate, which a later default change leaves untouched.
ALTER TABLE "StoreProduct" ADD COLUMN "pointsException" boolean NOT NULL DEFAULT false;

-- Existing rates: the most common rate of each product becomes its default;
-- a place with another rate keeps it as an exception. No rate changes.
CREATE TEMP TABLE place_audience AS
  SELECT s.id "storeId", CASE WHEN o.kind='wholesale' THEN 'wholesale' ELSE 'retail' END audience
  FROM "Store" s JOIN "Organization" o ON o.id=s."organizationId";
INSERT INTO "PointsDefault" (id, audience, "productId", "pointsPerUnit", reason, "createdAt")
SELECT gen_random_uuid(), pa.audience, sp."productId",
  mode() WITHIN GROUP (ORDER BY sp."pointsPerUnit"), 'Barème commun existant', TIMESTAMP '1970-01-01'
FROM "StoreProduct" sp JOIN place_audience pa ON pa."storeId"=sp."storeId"
WHERE sp."pointsConfigured" GROUP BY pa.audience, sp."productId";
UPDATE "StoreProduct" sp SET "pointsException" = true
FROM place_audience pa, "PointsDefault" d
WHERE pa."storeId"=sp."storeId" AND d.audience=pa.audience AND d."productId"=sp."productId"
  AND sp."pointsConfigured" AND sp."pointsPerUnit" <> d."pointsPerUnit";

-- Existing rewards offered identically in every active place of an audience
-- become default rewards; their copies are linked, nothing else changes.
CREATE TEMP TABLE shared_rewards AS
SELECT gen_random_uuid() id, g.* FROM (
  SELECT pa.audience, r.title, r.description, r.cost, r."productId", r.quantity,
    count(DISTINCT r."storeId") places
  FROM "Reward" r JOIN place_audience pa ON pa."storeId"=r."storeId"
  WHERE r.active GROUP BY 1,2,3,4,5,6) g
WHERE g.places > 1 AND g.places = (
  SELECT count(*) FROM place_audience pa2 JOIN "Store" s2 ON s2.id=pa2."storeId"
  WHERE pa2.audience=g.audience AND s2.status <> 'archived');
INSERT INTO "RewardTemplate" (id, audience, title, description, cost, "productId", quantity)
SELECT id, audience, title, description, cost, "productId", quantity FROM shared_rewards;
UPDATE "Reward" r SET "templateId" = t.id
FROM shared_rewards t, place_audience pa
WHERE pa."storeId"=r."storeId" AND pa.audience=t.audience AND r.active
  AND r.title=t.title AND r.description=t.description AND r.cost=t.cost
  AND r.quantity=t.quantity AND r."productId" IS NOT DISTINCT FROM t."productId";
DROP TABLE shared_rewards;
DROP TABLE place_audience;
