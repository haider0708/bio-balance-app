-- 1. A grossiste may supply stores of other regions, so an order remembers the region it is supplied from:
--    that region's responsable ships it and sees it.
ALTER TABLE "RestockOrder" ADD COLUMN "supplierRegionId" UUID;
UPDATE "RestockOrder" o SET "supplierRegionId" = d."regionId" FROM "Depot" d WHERE o."supplierDepotId" = d.id;
CREATE INDEX "RestockOrder_supplierRegionId_status_idx" ON "RestockOrder"("supplierRegionId", "status");

DROP POLICY "RestockOrder_rls" ON "RestockOrder";
DROP POLICY "RestockLine_rls" ON "RestockLine";
DROP FUNCTION app_sees_order(uuid, uuid);
CREATE FUNCTION app_sees_order(region uuid, supplier_region uuid, receiver uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() OR app_in_region(region) OR app_in_region(supplier_region)
    OR (receiver IS NOT NULL AND receiver = app_user()) $$;
CREATE POLICY "RestockOrder_rls" ON "RestockOrder"
  USING (app_sees_order("regionId", "supplierRegionId", "receiverId"))
  WITH CHECK (app_sees_order("regionId", "supplierRegionId", "receiverId"));
CREATE POLICY "RestockLine_rls" ON "RestockLine"
  USING (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"));

-- 2. Moving a store or a grossiste to another region carries its stock history along: the only change
--    the history table accepts is the region column, and only while the admin's move is running.
CREATE OR REPLACE FUNCTION prevent_history_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'StockMovement'
     AND current_setting('app.region_move', true) = 'on'
     AND app_role() = 'ADMIN'
     AND (to_jsonb(OLD) - 'regionId') = (to_jsonb(NEW) - 'regionId') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'History is append-only';
END; $$;
