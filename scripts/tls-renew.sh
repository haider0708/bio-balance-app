#!/usr/bin/env bash
set -euo pipefail
: "${API_DOMAIN:?Set the owned API hostname}"
certbot renew --cert-name "$API_DOMAIN" --non-interactive \
  --deploy-hook "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tls-install.sh" "$@"
