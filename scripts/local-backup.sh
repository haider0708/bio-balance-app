#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${COMPOSE_FILE:?Set the compose file path}"
: "${BACKUP_DIR:?Set a local backup directory outside the database volume}"
umask 077
mkdir -p "$BACKUP_DIR"
backup_target="$BACKUP_DIR/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$backup_target"
"${compose[@]}" exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup_target/database.dump"
# Ready media is immutable; copying after pg_dump includes every referenced file.
if [[ -n "${BACKUP_MEDIA_DIR:-}" ]]; then
  tar -C "$BACKUP_MEDIA_DIR" -czf "$backup_target/media.tar.gz" .
else
  "${compose[@]}" exec -T api1 tar -C /var/lib/biobalance/media -czf - . > "$backup_target/media.tar.gz"
fi
(cd "$backup_target" && sha256sum database.dump media.tar.gz > SHA256SUMS)
printf 'Local backup created: %s\n' "$backup_target"
