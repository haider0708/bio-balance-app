#!/usr/bin/env bash
# Creates (or recreates) the isolated test database and the restricted app role.
set -euo pipefail
cd "$(dirname "$0")/.."
compose=infrastructure/development/compose.yml
if docker compose version >/dev/null 2>&1; then
  psql_admin=(docker compose -f "$compose" exec -T postgres psql -U biobalance -q)
else
  # Docker without the Compose plugin (the Mac's Colima): the development database runs as a plain container.
  container=$(docker ps --format '{{.Names}}' | grep -m1 -E '^biobalance-dev-postgres(-1)?$' || true)
  [ -n "$container" ] || { echo "Start the development database first (docs: README, Check it)." >&2; exit 1; }
  psql_admin=(docker exec -i "$container" psql -U biobalance -q)
fi
"${psql_admin[@]}" -d postgres -c 'DROP DATABASE IF EXISTS biobalance_test WITH (FORCE)' -c 'CREATE DATABASE biobalance_test'
DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_test npm run db:migrate
"${psql_admin[@]}" -d biobalance_test -v app_password=local-app-only < scripts/provision-role.sql
