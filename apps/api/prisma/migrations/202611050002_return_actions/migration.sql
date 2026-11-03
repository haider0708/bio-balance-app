-- A return can also move the quantities to another para at once, or only add them (the admin's choice).
CREATE TYPE "ReturnAction" AS ENUM ('REMOVE', 'MOVE', 'ADD');
ALTER TABLE "StockReturn"
  ADD COLUMN "action" "ReturnAction" NOT NULL DEFAULT 'REMOVE',
  ADD COLUMN "toPdvId" UUID,
  ADD CONSTRAINT "StockReturn_action_check" CHECK (
    ("action" = 'MOVE' AND "toPdvId" IS NOT NULL AND "toPdvId" <> "pdvId")
    OR ("action" <> 'MOVE' AND "toPdvId" IS NULL));
