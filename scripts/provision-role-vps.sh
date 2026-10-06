#!/usr/bin/env bash
# Run ON the server (as root) after migrations: give the restricted application role its rights.
# The password comes from DATABASE_URL in /etc/biobalance/backend.env and is never printed.
set -euo pipefail
set -a
. /etc/biobalance/backend.env
set +a
password=$(python3 -c 'import os, urllib.parse as u; print(u.unquote(u.urlparse(os.environ["DATABASE_URL"]).password or ""), end="")')
[ -n "$password" ] || { echo "No password in DATABASE_URL" >&2; exit 1; }
docker exec -i biobalance-postgres-1 sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -v app_password="$1"' _ "$password" < "$(dirname "$0")/provision-role.sql"
echo "Application role provisioned."
