-- Run as migration owner with psql -v app_password='...' -f scripts/provision-role.sql.
-- The role must not own operational tables and must not bypass RLS.
SELECT 'CREATE ROLE biobalance_app LOGIN NOSUPERUSER NOBYPASSRLS'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='biobalance_app')\gexec
ALTER ROLE biobalance_app PASSWORD :'app_password';
GRANT USAGE ON SCHEMA public TO biobalance_app;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO biobalance_app;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO biobalance_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO biobalance_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO biobalance_app;
GRANT EXECUTE ON FUNCTION prune_expired_sync_snapshots() TO biobalance_app;
