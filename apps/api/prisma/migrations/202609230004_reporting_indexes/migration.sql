CREATE INDEX "SalesDay_day_idx" ON "SalesDay"(day);
CREATE INDEX "SalesProductDay_day_idx" ON "SalesProductDay"(day);
CREATE INDEX "SalesContribution_organizationId_day_saleId_idx" ON "SalesContribution"("organizationId",day,"saleId");
CREATE INDEX "SalesContribution_storeId_day_saleId_idx" ON "SalesContribution"("storeId",day,"saleId");
CREATE INDEX "InventoryLot_available_expiry_idx" ON "InventoryLot"(expiry) WHERE sellable>0;
