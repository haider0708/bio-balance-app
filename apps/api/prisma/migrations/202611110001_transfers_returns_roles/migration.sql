-- Transfers between paras of a group: a buyer of either para and the order manager make, change
-- and cancel them like a seller or the responsable does (only the admin approves, and only then
-- does stock move). Returns: a buyer of the para asks for them too.

-- A buyer is a team member of the para, like a seller.
CREATE OR REPLACE FUNCTION app_sees_transfer(region uuid, from_pdv uuid, to_pdv uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() OR app_in_region(region)
    OR (app_role() IN ('VENDEUR', 'ACHETEUR') AND (from_pdv = app_pdv() OR to_pdv = app_pdv()))
$$;

-- The order manager already reads every transfer; now it writes them too (never the stock: that
-- moves when the admin approves).
CREATE POLICY "StockTransfer_orders_insert" ON "StockTransfer" FOR INSERT
  WITH CHECK (app_is_orders());
CREATE POLICY "StockTransfer_orders_update" ON "StockTransfer" FOR UPDATE
  USING (app_is_orders()) WITH CHECK (app_is_orders());
CREATE POLICY "TransferLine_orders_write" ON "TransferLine" FOR ALL
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"))
  WITH CHECK (app_is_orders() AND EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));
CREATE POLICY "TransferRevision_orders_insert" ON "TransferRevision" FOR INSERT
  WITH CHECK (app_is_orders() AND EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));

-- A buyer sees and writes the returns of its own para (lines and revisions follow the return).
CREATE POLICY "StockReturn_buyer" ON "StockReturn" FOR ALL
  USING (app_is_buyer() AND "pdvId" = app_pdv())
  WITH CHECK (app_is_buyer() AND "pdvId" = app_pdv());
