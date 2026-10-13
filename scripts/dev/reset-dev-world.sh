#!/usr/bin/env bash
# A fresh local world for the on-device test: empty development database (regions kept),
# an administrator, the real catalogue, then the seeded accounts and activity.
# Writes the world (accounts) to $1 (default: /tmp/biobalance-world.json).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-/tmp/biobalance-world.json}
setup=$(mktemp -d)/admin-setup.json
db=(docker exec biobalance-dev-postgres-1 psql -U biobalance -d biobalance)
tables=$("${db[@]}" -Atc "select string_agg(format('%I',tablename),',') from pg_tables where schemaname='public' and tablename not in ('_prisma_migrations','Region')")
"${db[@]}" -qc "TRUNCATE $tables RESTART IDENTITY CASCADE"
(cd apps/api && ADMIN_EMAIL=owner@example.test ADMIN_PASSWORD=owner-password ADMIN_SETUP_FILE=$setup node --env-file=.env dist/bootstrap-admin.js >/dev/null)
python3 - "$setup" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['password']='owner-password'; json.dump(d,open(p,'w'))
PY
(cd apps/api && npm run catalog --silent -- --apply | tail -1)
node scripts/dev/seed-dev-world.mjs "$setup" "$out"
