#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${API_DOMAIN:?Set your owned API hostname with DNS pointing to this server}"
: "${ACME_EMAIL:?Set the certificate account email}"
[[ "$API_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || exit 1
command -v certbot >/dev/null
acme_directory=${ACME_DIRECTORY:-$(dirname "$COMPOSE_FILE")/acme}
mkdir -p "$acme_directory"
acme_container=""
cleanup() { if [[ -n "$acme_container" ]]; then docker stop "$acme_container" >/dev/null || true; fi; }
trap cleanup EXIT
if [[ -z "$("${compose[@]}" ps --status running -q nginx)" ]]; then
  "${compose[@]}" stop nginx
  acme_container=$(docker run --rm -d -p 80:80 -v "$acme_directory:/usr/share/nginx/html:ro" nginx:1.28.0-alpine)
fi
certbot certonly --webroot --webroot-path "$acme_directory" --domain "$API_DOMAIN" \
  --cert-name "$API_DOMAIN" --email "$ACME_EMAIL" --agree-tos --non-interactive --keep-until-expiring
export RENEWED_LINEAGE="/etc/letsencrypt/live/$API_DOMAIN"
"$(dirname "${BASH_SOURCE[0]}")/tls-install.sh"
