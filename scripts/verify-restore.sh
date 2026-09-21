#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${COMPOSE_FILE:?Set compose file path}"
: "${BACKUP_PATH:?Set the completed backup directory}"
umask 077
restore_database="biobalance_restore_$(date +%s)_${RANDOM}"
(cd "$BACKUP_PATH" && sha256sum -c SHA256SUMS)
restore_owner=$("${compose[@]}" exec -T postgres sh -c 'printf %s "$POSTGRES_USER"')
"${compose[@]}" exec -T postgres createdb -U "$restore_owner" "$restore_database"
"${compose[@]}" exec -T postgres pg_restore -U "$restore_owner" -d "$restore_database" --exit-on-error < "$BACKUP_PATH/database.dump"
restore_media=$(mktemp -d -t biobalance-restore-media-XXXXXXXX)
python3 - "$BACKUP_PATH/media.tar.gz" "$restore_media" <<'PY'
import sys,tarfile
with tarfile.open(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2],filter='data')
PY
"${compose[@]}" exec -T postgres psql -U "$restore_owner" -d "$restore_database" -v ON_ERROR_STOP=1 -At > "$restore_media/references.jsonl" <<'SQL'
SELECT json_build_object('path',path,'size',"processedSize"::text,'sha256',sha256) FROM "MediaAsset" WHERE status='ready';
SQL
python3 - "$restore_media" <<'PYVERIFY'
import sys,json,pathlib,hashlib,re
root=pathlib.Path(sys.argv[1]);count=0
for line in (root/'references.jsonl').read_text().splitlines():
    row=json.loads(line); name=row['path']
    if not re.fullmatch(r'[a-zA-Z0-9._-]+',name) or name in ('.','..'):
        raise SystemExit('Invalid restored media path')
    file=root/name
    if not file.is_file() or file.is_symlink(): raise SystemExit('Missing restored media: '+name)
    if row['size'] is None or row['sha256'] is None:
        raise SystemExit('Missing media integrity metadata: '+name)
    if file.stat().st_size!=int(row['size']): raise SystemExit('Restored media size mismatch: '+name)
    digest=hashlib.sha256()
    with file.open('rb') as source:
        for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
    if digest.hexdigest()!=row['sha256']:raise SystemExit('Restored media checksum mismatch: '+name)
    count+=1
print(f'PASS: {count} processed media files match database size and SHA-256')
PYVERIFY
"${compose[@]}" exec -T postgres psql -U "$restore_owner" -d "$restore_database" -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS stores FROM "Store"; SELECT count(*) AS sales FROM "Sale"; SELECT count(*) AS movements FROM "StockMovement";'
printf 'Restore verified: database=%s media=%s\n' "$restore_database" "$restore_media"
# Both isolated outputs remain available for inspection. Production is untouched.
