-- The buyer (ACHETEUR): places the orders of one para and receives them, with no sales and no wallet.
-- A vendeur with "canOrder" does the same besides selling. Both belong to a region and a para.
ALTER TABLE "User" ADD COLUMN "canOrder" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "User" DROP CONSTRAINT "User_scope_check";
ALTER TABLE "User" ADD CONSTRAINT "User_scope_check" CHECK (
  (role IN ('RESPONSABLE','VENDEUR','ACHETEUR')) = ("regionId" IS NOT NULL)
  AND (role IN ('VENDEUR','ACHETEUR')) = ("pdvId" IS NOT NULL));
-- Only a vendeur carries the switch: a buyer always orders, nobody else does.
ALTER TABLE "User" ADD CONSTRAINT "User_canOrder_check" CHECK (NOT "canOrder" OR role = 'VENDEUR');

-- The API says in every transaction whether a vendeur is also a buyer.
CREATE FUNCTION app_is_buyer() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_role() = 'ACHETEUR'
    OR (app_role() = 'VENDEUR' AND COALESCE(current_setting('app.can_order', true), '') = 'on') $$;

-- A buyer reads, creates and updates the orders that are for its own para, and nothing else.
-- (Which actions it may take on them is the route's rule: it asks, receives, cancels its own.)
CREATE POLICY "RestockOrder_buyer_read" ON "RestockOrder" FOR SELECT
  USING (app_is_buyer() AND "destKind" = 'PDV' AND "destId" = app_pdv());
CREATE POLICY "RestockOrder_buyer_insert" ON "RestockOrder" FOR INSERT
  WITH CHECK (app_is_buyer() AND "destKind" = 'PDV' AND "destId" = app_pdv());
CREATE POLICY "RestockOrder_buyer_update" ON "RestockOrder" FOR UPDATE
  USING (app_is_buyer() AND "destKind" = 'PDV' AND "destId" = app_pdv())
  WITH CHECK (app_is_buyer() AND "destKind" = 'PDV' AND "destId" = app_pdv());

-- The papers of its para's orders (delivery notes added by the order manager or the admin, receipts).
CREATE POLICY "MediaAsset_buyer_read" ON "MediaAsset" FOR SELECT
  USING (app_is_buyer() AND purpose = 'PROOF' AND EXISTS (
    SELECT 1 FROM "RestockOrder" o
    WHERE o."destKind" = 'PDV' AND o."destId" = app_pdv()
      AND ("MediaAsset".id = ANY(o."documentIds") OR "MediaAsset".id = ANY(o."receiptPhotoIds") OR "MediaAsset".id = o."receiptPhotoId")));
