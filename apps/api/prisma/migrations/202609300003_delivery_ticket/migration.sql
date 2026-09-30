-- A delivery is now a numbered ticket (bon de livraison). Existing deliveries are
-- numbered in dispatch order; no quantity, stock or history is changed.
CREATE SEQUENCE "DeliveryTicketSeq";
ALTER TABLE "Delivery" ADD COLUMN "ticketNumber" TEXT, ADD COLUMN "ticketVersion" INTEGER NOT NULL DEFAULT 1;
UPDATE "Delivery" d SET "ticketNumber" = 'BL-' || to_char(o."dispatchedAt", 'YYYY') || '-' || lpad(o.seq::text, 6, '0')
  FROM (SELECT id, "dispatchedAt", nextval('"DeliveryTicketSeq"') AS seq
        FROM (SELECT id, "dispatchedAt" FROM "Delivery" ORDER BY "dispatchedAt", id) ordered) o
  WHERE d.id = o.id;
ALTER TABLE "Delivery" ALTER COLUMN "ticketNumber" SET NOT NULL;
CREATE UNIQUE INDEX "Delivery_ticketNumber_key" ON "Delivery" ("ticketNumber");
-- A reception records whether the ticket's QR was scanned, or why it was not.
ALTER TABLE "DeliveryReceipt" ADD COLUMN "scanned" BOOLEAN NOT NULL DEFAULT false, ADD COLUMN "manualReason" TEXT;
