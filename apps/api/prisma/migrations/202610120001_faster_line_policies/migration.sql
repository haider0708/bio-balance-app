-- Reports read hundreds of thousands of sale lines. For the admin the check "is the sale visible?"
-- is always true, so say so first and skip the per-line lookup; everyone else is checked as before.
DROP POLICY "SaleLine_rls" ON "SaleLine";
CREATE POLICY "SaleLine_rls" ON "SaleLine"
  USING (app_is_admin() OR EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"))
  WITH CHECK (app_is_admin() OR EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"));
