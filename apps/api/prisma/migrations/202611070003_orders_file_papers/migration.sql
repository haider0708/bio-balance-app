-- The order manager files the papers it uploads under the order's region (so the region's responsable
-- can open them), as the admin does: it may update only its own proofs.
CREATE POLICY "MediaAsset_orders_file" ON "MediaAsset" FOR UPDATE
  USING (app_role() = 'ORDERS' AND "ownerId" = app_user() AND purpose = 'PROOF')
  WITH CHECK (app_role() = 'ORDERS' AND "ownerId" = app_user() AND purpose = 'PROOF');
