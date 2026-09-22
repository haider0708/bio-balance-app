-- Resolve transaction-local security context once per statement. UUID comparisons
-- retain fail-closed scope checks while allowing the ordered store/date index to
-- stop at LIMIT instead of scanning and sorting the complete store history.
ALTER POLICY "Sale_scope" ON "Sale"
USING (
  "organizationId" = (SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid)
  AND "storeId" = (SELECT NULLIF(current_setting('app.store_id', true), '')::uuid)
)
WITH CHECK (
  "organizationId" = (SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid)
  AND "storeId" = (SELECT NULLIF(current_setting('app.store_id', true), '')::uuid)
);

-- This remains SELECT-only. Setting the explicit server admin-read context does
-- not authorize writes, and is still confined to the caller's transaction.
ALTER POLICY "Sale_admin_read" ON "Sale"
USING ((SELECT current_setting('app.admin_read', true) = 'true'));
