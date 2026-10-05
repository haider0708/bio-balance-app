#!/usr/bin/env bash
# Runs the month-long simulation on a fresh, isolated local database and prints
# the activity and the consistency checks. Requires the development PostgreSQL
# (infrastructure/development/compose.yml) and a built API (npm run build).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=simulation_test
P="docker exec -i biobalance-dev-postgres-1 psql -U biobalance -v ON_ERROR_STOP=1"
$P -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB" >/dev/null
(cd apps/api && DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/$DB npx prisma migrate deploy >/dev/null)
$P -d $DB -v app_password=local-app-only -f - < scripts/provision-role.sql >/dev/null
cd apps/api
DIST=$PWD/dist \
DATABASE_URL=postgresql://biobalance_app:local-app-only@localhost:54329/$DB \
OWNER_URL=postgresql://biobalance:local-development-only@localhost:54329/$DB \
node ../../scripts/simulation/simulate.cjs
