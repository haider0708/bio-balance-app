-- The test region ("sandbox"): the store reviewers' accounts work there with demonstration data.
-- The admin does not see it unless they ask to: the server sets app.hidden_region for the admin's
-- requests, and every policy below reads it. Trusted server work (SYSTEM) and the region's own
-- people are not affected.
ALTER TABLE "Region" ADD COLUMN "sandbox" BOOLEAN NOT NULL DEFAULT false;
CREATE UNIQUE INDEX "Region_one_sandbox" ON "Region" ("sandbox") WHERE "sandbox";

CREATE FUNCTION app_hidden_region() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.hidden_region', true), '')::uuid $$;

-- Whether a row of `region` stays visible: always, unless a region is hidden and it is that one
-- (rows of no region stay visible).
CREATE FUNCTION app_region_visible(region uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_hidden_region() IS NULL OR region IS DISTINCT FROM app_hidden_region() $$;

-- What the admin (or trusted server work) may see of a region's rows: all but the hidden region.
CREATE FUNCTION app_admin_sees(region uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() AND app_region_visible(region) $$;

-- Regions and people have no policy yet: they get one that only hides the hidden region.
ALTER TABLE "Region" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Region" FORCE ROW LEVEL SECURITY;
CREATE POLICY "Region_visible" ON "Region"
  USING (app_region_visible(id)) WITH CHECK (app_region_visible(id));
ALTER TABLE "User" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "User" FORCE ROW LEVEL SECURITY;
CREATE POLICY "User_visible" ON "User"
  USING (app_region_visible("regionId")) WITH CHECK (app_region_visible("regionId"));

-- Sales and restocks: through their functions.
CREATE OR REPLACE FUNCTION app_sees_sale(region uuid, seller uuid, pdv uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_admin_sees(region) OR app_in_region(region)
    OR (app_role() = 'VENDEUR' AND seller = app_user() AND pdv = app_pdv()) $$;
CREATE OR REPLACE FUNCTION app_sees_order(region uuid, supplier_region uuid, receiver uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_admin_sees(region) OR app_in_region(region) OR app_in_region(supplier_region)
    OR (receiver IS NOT NULL AND receiver = app_user()) $$;

-- Every other policy with a region: the admin's part becomes app_admin_sees(region).
DROP POLICY "AuditEntry_read" ON "AuditEntry";
CREATE POLICY "AuditEntry_read" ON "AuditEntry" FOR SELECT USING (app_admin_sees("regionId"));

DROP POLICY "Depot_read" ON "Depot";
DROP POLICY "Depot_write" ON "Depot";
CREATE POLICY "Depot_read" ON "Depot" FOR SELECT
  USING (app_admin_sees("regionId") OR app_in_region("regionId"));
CREATE POLICY "Depot_write" ON "Depot" FOR ALL
  USING (app_admin_sees("regionId")) WITH CHECK (app_admin_sees("regionId"));

DROP POLICY "Group_rls" ON "Group";
CREATE POLICY "Group_rls" ON "Group"
  USING (app_admin_sees("regionId") OR app_in_region("regionId"))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId"));

DROP POLICY "MediaAsset_read" ON "MediaAsset";
CREATE POLICY "MediaAsset_read" ON "MediaAsset" FOR SELECT USING (
  purpose <> 'PROOF' OR app_admin_sees("regionId") OR "ownerId" = app_user() OR app_in_region("regionId"));

DROP POLICY "PayoutRequest_rls" ON "PayoutRequest";
CREATE POLICY "PayoutRequest_rls" ON "PayoutRequest"
  USING (app_admin_sees("regionId") OR "userId" = app_user())
  WITH CHECK (app_admin_sees("regionId") OR "userId" = app_user());

DROP POLICY "Pdv_rls" ON "Pdv";
CREATE POLICY "Pdv_rls" ON "Pdv"
  USING (app_admin_sees("regionId") OR app_in_region("regionId") OR id = app_pdv())
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId"));

DROP POLICY "Stock_rls" ON "Stock";
CREATE POLICY "Stock_rls" ON "Stock"
  USING (app_admin_sees("regionId") OR app_in_region("regionId")
    OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId")
    OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));

DROP POLICY "StockDeclaration_rls" ON "StockDeclaration";
CREATE POLICY "StockDeclaration_rls" ON "StockDeclaration"
  USING (app_admin_sees("regionId") OR app_in_region("regionId"))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId"));

DROP POLICY "StockMovement_rls" ON "StockMovement";
CREATE POLICY "StockMovement_rls" ON "StockMovement"
  USING (app_admin_sees("regionId") OR app_in_region("regionId"))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId")
    OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));

DROP POLICY "StockRecount_rls" ON "StockRecount";
CREATE POLICY "StockRecount_rls" ON "StockRecount"
  USING (app_admin_sees("regionId") OR app_in_region("regionId"))
  WITH CHECK (app_admin_sees("regionId") OR app_in_region("regionId"));
