#!/usr/bin/env bash
set -euo pipefail
: "${COMPOSE_FILE:?Set compose file path}"
: "${BACKUP_PATH:?Set the completed backup directory}"
restore_database="biobalance_restore_$(date +%s)"
(cd "$BACKUP_PATH" && sha256sum -c SHA256SUMS)
restore_owner=$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -c 'printf %s "$POSTGRES_USER"')
docker compose -f "$COMPOSE_FILE" exec -T postgres createdb -U "$restore_owner" "$restore_database"
docker compose -f "$COMPOSE_FILE" exec -T postgres pg_restore -U "$restore_owner" -d "$restore_database" --exit-on-error < "$BACKUP_PATH/database.dump"
restore_media=$(mktemp -d -t biobalance-restore-media-XXXXXXXX)
python3 - "$BACKUP_PATH/media.tar.gz" "$restore_media" <<'PY'
import sys,tarfile
with tarfile.open(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2],filter='data')
PY
docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U "$restore_owner" -d "$restore_database" -v ON_ERROR_STOP=1 -Atc 'SELECT path FROM "MediaAsset" WHERE status = '\''ready'\'';' > "$restore_media/references.txt"
while IFS= read -r media_path; do
  [[ -z "$media_path" ]] && continue
  [[ "$media_path" =~ ^[a-zA-Z0-9._-]+$ && -s "$restore_media/$media_path" ]] || { printf 'Missing restored media: %s\n' "$media_path" >&2; exit 1; }
done < "$restore_media/references.txt"
docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U "$restore_owner" -d "$restore_database" -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS stores FROM "Store"; SELECT count(*) AS sales FROM "Sale"; SELECT count(*) AS movements FROM "StockMovement";'
printf 'Restore verified: database=%s media=%s\n' "$restore_database" "$restore_media"
# Both isolated outputs remain available for inspection. Production is untouched.
