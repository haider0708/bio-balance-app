-- One to five photos per stock count and per delivery receipt; the first one stays in the old column as the cover.
ALTER TABLE "StockDeclaration" ADD COLUMN "photoIds" UUID[] NOT NULL DEFAULT '{}';
UPDATE "StockDeclaration" SET "photoIds" = ARRAY["photoId"] WHERE "photoId" IS NOT NULL;
ALTER TABLE "RestockOrder" ADD COLUMN "receiptPhotoIds" UUID[] NOT NULL DEFAULT '{}';
UPDATE "RestockOrder" SET "receiptPhotoIds" = ARRAY["receiptPhotoId"] WHERE "receiptPhotoId" IS NOT NULL;
