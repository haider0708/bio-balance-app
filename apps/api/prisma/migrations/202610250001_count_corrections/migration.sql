-- A correction of an approved count is asked of the admin (a StockRecount row of kind CORRECTION).
ALTER TABLE "StockRecount" ADD COLUMN "kind" TEXT NOT NULL DEFAULT 'RECOUNT';
ALTER TABLE "StockRecount" ADD COLUMN "correctsId" UUID;
-- Each save of a count raises its revision, so two people editing at once cannot overwrite each other.
ALTER TABLE "StockDeclaration" ADD COLUMN "revision" INTEGER NOT NULL DEFAULT 0;
