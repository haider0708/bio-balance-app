-- A receipt without the QR is only a claim: the store says what it got, no stock
-- moves, and BioBalance validates it. The claim is written once and never edited.
ALTER TABLE "Delivery" ADD COLUMN "claim" JSONB;
CREATE FUNCTION delivery_claim_once() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD."claim" IS NOT NULL AND NEW."claim" IS DISTINCT FROM OLD."claim" THEN
    RAISE EXCEPTION 'A receipt claim cannot be changed';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER "Delivery_claim_once" BEFORE UPDATE ON "Delivery"
  FOR EACH ROW EXECUTE FUNCTION delivery_claim_once();
-- Opening stock is declared once per store or depot, then closed for good.
ALTER TABLE "Store" ADD COLUMN "openingClosedAt" TIMESTAMP(3);
-- Stores and depots that already hold stock, or said they have none, used their chance.
UPDATE "Store" SET "openingClosedAt" = now()
 WHERE "noOpeningStock" OR EXISTS (SELECT 1 FROM "InventoryLot" l WHERE l."storeId" = "Store".id);
