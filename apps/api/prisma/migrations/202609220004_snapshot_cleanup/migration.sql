-- The cleanup capability returns only a count and can delete only expired
-- ephemeral pages. It does not grant the application role cross-tenant reads.
-- FORCE RLS also applies to the table owner, so explicitly permit that owner to
-- see/delete expired pages while executing the SECURITY DEFINER function.
DO $$ BEGIN
  EXECUTE format('CREATE POLICY snapshot_expired_owner_read ON "SyncSnapshotPage" FOR SELECT TO %I USING ("expiresAt" < CURRENT_TIMESTAMP AT TIME ZONE ''UTC'')', current_user);
  EXECUTE format('CREATE POLICY snapshot_expired_owner_delete ON "SyncSnapshotPage" FOR DELETE TO %I USING ("expiresAt" < CURRENT_TIMESTAMP AT TIME ZONE ''UTC'')', current_user);
END $$;

CREATE FUNCTION prune_expired_sync_snapshots() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE removed integer;
BEGIN
  DELETE FROM public."SyncSnapshotPage" WHERE id IN (
    SELECT id FROM public."SyncSnapshotPage"
    WHERE "expiresAt" < CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
    ORDER BY "expiresAt", id LIMIT 1000 FOR UPDATE SKIP LOCKED
  );
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END $$;
REVOKE ALL ON FUNCTION prune_expired_sync_snapshots() FROM PUBLIC;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'biobalance_app') THEN
    GRANT EXECUTE ON FUNCTION prune_expired_sync_snapshots() TO biobalance_app;
  END IF;
END $$;
