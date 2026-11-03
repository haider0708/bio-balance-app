-- The order manager: proposals on waiting orders, papers, delivery, and what the role may read and
-- write. It sees the whole network's stock and orders but none of the money (wallets, payouts,
-- rewards stay closed): reads and writes are listed table by table below.
ALTER TABLE "RestockOrder"
  ADD COLUMN "proposedSource" "OrderSource",
  ADD COLUMN "proposedDepotId" UUID,
  ADD COLUMN "proposedById" UUID,
  ADD COLUMN "proposedAt" TIMESTAMP(3),
  ADD COLUMN "proposalNote" TEXT,
  ADD COLUMN "documentIds" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[],
  ADD COLUMN "deliveredAt" TIMESTAMP(3),
  ADD COLUMN "deliveredById" UUID,
  ADD CONSTRAINT "RestockOrder_proposal_check" CHECK (
    ("proposedSource" IS NULL AND "proposedDepotId" IS NULL)
    OR ("proposedSource" = 'GROSSISTE' AND "proposedDepotId" IS NOT NULL)
    OR ("proposedSource" = 'BIOBALANCE' AND "proposedDepotId" IS NULL)),
  ADD CONSTRAINT "RestockOrder_proposalNote_check" CHECK ("proposalNote" IS NULL OR char_length("proposalNote") <= 300);
ALTER TABLE "RestockLine" ADD COLUMN "proposed" INTEGER,
  ADD CONSTRAINT "RestockLine_proposed_check" CHECK ("proposed" IS NULL OR "proposed" >= 0);

CREATE FUNCTION app_is_orders() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT app_role() = 'ORDERS' $$;

-- Reads: the network as the admin sees it (not the test region).
CREATE POLICY "Group_orders_read" ON "Group" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "Pdv_orders_read" ON "Pdv" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "Depot_orders_read" ON "Depot" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "Stock_orders_read" ON "Stock" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "StockMovement_orders_read" ON "StockMovement" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "RestockOrder_orders_read" ON "RestockOrder" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "RestockLine_orders_read" ON "RestockLine" FOR SELECT
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"));
CREATE POLICY "StockTransfer_orders_read" ON "StockTransfer" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "TransferLine_orders_read" ON "TransferLine" FOR SELECT
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));
CREATE POLICY "TransferRevision_orders_read" ON "TransferRevision" FOR SELECT
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "StockTransfer" t WHERE t.id = "transferId"));
CREATE POLICY "StockReturn_orders_read" ON "StockReturn" FOR SELECT
  USING (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "ReturnLine_orders_read" ON "ReturnLine" FOR SELECT
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"));
CREATE POLICY "ReturnRevision_orders_read" ON "ReturnRevision" FOR SELECT
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "StockReturn" r WHERE r.id = "returnId"));
-- The papers (delivery notes, photos of goods) of every order.
CREATE POLICY "MediaAsset_orders_read" ON "MediaAsset" FOR SELECT
  USING (app_is_orders() AND purpose = 'PROOF');

-- Writes: only what preparing, shipping and delivering an order changes. The routes decide what
-- the role may do with them; money tables stay closed to it.
CREATE POLICY "RestockOrder_orders_write" ON "RestockOrder" FOR INSERT
  WITH CHECK (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "RestockOrder_orders_update" ON "RestockOrder" FOR UPDATE
  USING (app_is_orders() AND app_region_visible("regionId"))
  WITH CHECK (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "RestockLine_orders_write" ON "RestockLine" FOR ALL
  USING (app_is_orders() AND EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"))
  WITH CHECK (app_is_orders() AND EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"));
-- Goods leaving a grossiste when it ships.
CREATE POLICY "Stock_orders_insert" ON "Stock" FOR INSERT
  WITH CHECK (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "Stock_orders_update" ON "Stock" FOR UPDATE
  USING (app_is_orders() AND app_region_visible("regionId"))
  WITH CHECK (app_is_orders() AND app_region_visible("regionId"));
CREATE POLICY "StockMovement_orders_insert" ON "StockMovement" FOR INSERT
  WITH CHECK (app_is_orders() AND app_region_visible("regionId"));
