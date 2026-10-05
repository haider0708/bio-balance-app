-- BioBalance may confirm part of a flag (the rest returns to sale) and records
-- who is responsible, as for a reception it settles. Both are written with the
-- one decision; the existing guard keeps a decided flag final.
ALTER TABLE "QualityFlag"
  ADD COLUMN "confirmedQuantity" integer CHECK ("confirmedQuantity" > 0),
  ADD COLUMN responsibility text CHECK (responsibility IN ('shipper','store','carrier','none'));
