#!/usr/bin/env bash
set -euo pipefail
: "${COMPOSE_FILE:?Set compose path}"
: "${BACKUP_DIR:?Set backup path}"
usage=$(df -P "$BACKUP_DIR" | awk 'NR==2{gsub(/%/,"",$5);print $5}')
((usage < 85)) || { printf 'Disk usage is %s%%\n' "$usage" >&2; exit 1; }
recent=$(find "$BACKUP_DIR" -maxdepth 2 -name SHA256SUMS -mmin -1560 -print -quit)
[[ -n "$recent" ]] || { printf 'No completed backup within 26 hours\n' >&2; exit 1; }
docker compose -f "$COMPOSE_FILE" ps --format json | python3 -c 'import sys,json; rows=[json.loads(s) for s in sys.stdin if s.strip()]; bad=[r["Service"] for r in rows if r.get("State")!="running" or r.get("Health") in ["unhealthy","starting"]]; print("Unhealthy services:",bad);sys.exit(bool(bad) or len(rows)<6)'
