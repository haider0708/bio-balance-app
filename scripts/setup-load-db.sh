#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
compose=infrastructure/development/compose.yml
if ! docker compose -f "$compose" exec -T postgres psql -U biobalance -tAc "SELECT 1 FROM pg_database WHERE datname='biobalance_load_test'" | rg -q '^1$'; then
  docker compose -f "$compose" exec -T postgres createdb -U biobalance biobalance_load_test
fi
DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_load_test npm run db:migrate
docker compose -f "$compose" exec -T postgres psql -U biobalance -d biobalance_load_test -v app_password=local-app-only -f /dev/stdin < scripts/provision-role.sql
LOAD_OWNER_DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_load_test node tests/load/seed.cjs
