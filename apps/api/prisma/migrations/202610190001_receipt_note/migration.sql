-- The receiver confirms a delivery with its paper and may add a note; the admin enters the
-- quantities received when approving.
ALTER TABLE "RestockOrder" ADD COLUMN "receiptNote" TEXT;
