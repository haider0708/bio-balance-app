-- A store is either a pharmacie or a parapharmacie. The value is chosen when
-- the store is created and can be corrected later; it is never both.
-- Stores created before this attribute keep an unknown nature: no existing
-- store is assigned a business fact that was never recorded.
ALTER TABLE "Store" ADD COLUMN "nature" TEXT;
ALTER TABLE "Store" ADD CONSTRAINT "Store_nature"
  CHECK ("nature" IS NULL OR "nature" IN ('pharmacie','parapharmacie'));
