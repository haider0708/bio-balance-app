-- Additive wholesale support. A grossiste is an organization of kind 'wholesale'
-- with one depot store; existing organizations, stores, orders and deliveries
-- keep their identities and history.
ALTER TABLE "Organization" ADD COLUMN "kind" TEXT NOT NULL DEFAULT 'retail';
ALTER TABLE "Organization" ADD CONSTRAINT "Organization_kind" CHECK ("kind" IN ('retail','wholesale'));

-- An order is handled by BioBalance (both columns null) or assigned to a depot.
ALTER TABLE "ReplenishmentOrder" ADD COLUMN "supplierOrganizationId" UUID, ADD COLUMN "supplierStoreId" UUID;
ALTER TABLE "ReplenishmentOrder" ADD CONSTRAINT "ReplenishmentOrder_supplier_fk"
  FOREIGN KEY ("supplierOrganizationId","supplierStoreId") REFERENCES "Store"("organizationId",id);
ALTER TABLE "ReplenishmentOrder" ADD CONSTRAINT "ReplenishmentOrder_supplier_pair"
  CHECK (("supplierOrganizationId" IS NULL) = ("supplierStoreId" IS NULL));
CREATE INDEX "ReplenishmentOrder_supplier_idx" ON "ReplenishmentOrder" ("supplierStoreId", status);

-- A delivery remembers the depot whose stock it left.
ALTER TABLE "Delivery" ADD COLUMN "sourceOrganizationId" UUID, ADD COLUMN "sourceStoreId" UUID;
ALTER TABLE "Delivery" ADD CONSTRAINT "Delivery_source_fk"
  FOREIGN KEY ("sourceOrganizationId","sourceStoreId") REFERENCES "Store"("organizationId",id);
ALTER TABLE "Delivery" ADD CONSTRAINT "Delivery_source_pair"
  CHECK (("sourceOrganizationId" IS NULL) = ("sourceStoreId" IS NULL));
CREATE INDEX "Delivery_source_idx" ON "Delivery" ("sourceStoreId", status);

-- A grossiste reads only the orders assigned to its own depot. Writes stay in the
-- order's store scope, through an audited server use case.
CREATE POLICY "ReplenishmentOrder_supplier_read" ON "ReplenishmentOrder" FOR SELECT USING (
  "supplierStoreId"::text=current_setting('app.supplier_store',true)
  AND EXISTS (SELECT 1 FROM "OrganizationMembership" m WHERE m."organizationId"="ReplenishmentOrder"."supplierOrganizationId"
    AND m."userId"::text=current_setting('app.actor_id',true) AND m.active));
CREATE POLICY "Delivery_supplier_read" ON "Delivery" FOR SELECT USING (
  "sourceStoreId"::text=current_setting('app.supplier_store',true)
  AND EXISTS (SELECT 1 FROM "OrganizationMembership" m WHERE m."organizationId"="Delivery"."sourceOrganizationId"
    AND m."userId"::text=current_setting('app.actor_id',true) AND m.active));
CREATE POLICY "DeliveryReceipt_supplier_read" ON "DeliveryReceipt" FOR SELECT USING (
  EXISTS (SELECT 1 FROM "Delivery" d WHERE d.id="DeliveryReceipt"."deliveryId"));
CREATE POLICY "DeliveryIssue_supplier_read" ON "DeliveryIssue" FOR SELECT USING (
  EXISTS (SELECT 1 FROM "Delivery" d WHERE d.id="DeliveryIssue"."deliveryId"));
