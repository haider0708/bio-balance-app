#!/usr/bin/env bash
set -euo pipefail
if [[ "${RENEWED_LINEAGE:-}" == /etc/letsencrypt/live/api.galylio.com ]]; then
  /usr/sbin/apache2ctl configtest
  /bin/systemctl reload apache2
fi
