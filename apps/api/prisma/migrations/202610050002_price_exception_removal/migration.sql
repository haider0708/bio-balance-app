-- An exception (a price for one grossiste or one store) can be withdrawn: a
-- "cleared" version is appended and the party follows the default again. The
-- history keeps both; a default itself is only ever replaced, never cleared.
ALTER TABLE "PriceVersion" ADD COLUMN cleared boolean NOT NULL DEFAULT false;
ALTER TABLE "PriceVersion" ADD CONSTRAINT "PriceVersion_cleared_exception" CHECK (
  NOT cleared OR (level = 'wholesale' AND "organizationId" IS NOT NULL)
  OR (level = 'store_supply' AND "storeId" IS NOT NULL));
