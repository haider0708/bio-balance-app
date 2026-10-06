#!/usr/bin/env bash
# Creates (or recreates) the isolated test database and the restricted app role.
set -euo pipefail
cd "$(dirname "$0")/.."
compose=infrastructure/development/compose.yml
psql_admin=(docker compose -f "$compose" exec -T postgres psql -U biobalance -q)
"${psql_admin[@]}" -d postgres -c 'DROP DATABASE IF EXISTS biobalance_test WITH (FORCE)' -c 'CREATE DATABASE biobalance_test'
DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_test npm run db:migrate
"${psql_admin[@]}" -d biobalance_test -v app_password=local-app-only < scripts/provision-role.sql
