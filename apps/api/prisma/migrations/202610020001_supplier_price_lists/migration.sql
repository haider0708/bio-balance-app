-- A grossiste sets what stores pay him: a supplier's own store-supply list.
-- supplierOrganizationId NULL keeps meaning BioBalance's list, so every existing
-- price is unchanged.
ALTER TABLE "PriceVersion" ADD COLUMN "supplierOrganizationId" uuid REFERENCES "Organization"(id);
ALTER TABLE "PriceVersion" ADD CONSTRAINT "PriceVersion_supplier_level"
  CHECK ("supplierOrganizationId" IS NULL OR level = 'store_supply');
CREATE INDEX "PriceVersion_supplier" ON "PriceVersion" ("supplierOrganizationId", "productId", "createdAt" DESC)
  WHERE "supplierOrganizationId" IS NOT NULL;
