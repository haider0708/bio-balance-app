-- A responsable the admin allows (with the global switch on) may suggest the grossiste of a store's
-- restock order; the order still goes to the admin, who approves it as suggested, gives it to
-- another grossiste, sends it from BioBalance, or refuses it.
ALTER TABLE "User" ADD COLUMN "canChooseSupplier" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "RestockOrder" ADD COLUMN "suggestedDepotId" UUID;
