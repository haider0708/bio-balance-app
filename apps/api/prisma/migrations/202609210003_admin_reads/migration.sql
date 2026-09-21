-- Global reads require a dedicated, audited server use case. Writes remain store-scoped.
CREATE POLICY "Sale_admin_read" ON "Sale" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "InventoryLot_admin_read" ON "InventoryLot" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "ReplenishmentOrder_admin_read" ON "ReplenishmentOrder" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "Delivery_admin_read" ON "Delivery" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "Alert_admin_read" ON "Alert" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "PointsAccount_admin_read" ON "PointsAccount" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "RewardClaim_admin_read" ON "RewardClaim" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE INDEX "Sale_lines_gin" ON "Sale" USING gin(lines);
CREATE INDEX "StockMovement_operation" ON "StockMovement" ("storeId","operationId");
