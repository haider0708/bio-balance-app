-- A place with nothing on its shelves can declare "no stock" without a photo.
ALTER TABLE "StockDeclaration" ALTER COLUMN "photoId" DROP NOT NULL;
