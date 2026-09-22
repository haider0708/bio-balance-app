#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${BACKUP_DIR:?Set a local backup directory outside the database volume}"
umask 077
exec python3 "$(dirname "${BASH_SOURCE[0]}")/backup_storage.py" run "$BACKUP_DIR" -- "${compose[@]}"
