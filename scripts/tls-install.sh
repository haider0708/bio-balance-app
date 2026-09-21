#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${RENEWED_LINEAGE:?Set the certbot certificate lineage}"
cert_directory=${CERTIFICATE_DIR:-$(dirname "$COMPOSE_FILE")/certificates}
umask 077
mkdir -p "$cert_directory"
openssl x509 -in "$RENEWED_LINEAGE/fullchain.pem" -noout -checkend 86400 >/dev/null
cert_public=$(openssl x509 -in "$RENEWED_LINEAGE/fullchain.pem" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)
key_public=$(openssl pkey -in "$RENEWED_LINEAGE/privkey.pem" -pubout -outform DER | sha256sum)
[[ "$cert_public" == "$key_public" ]] || { echo 'Certificate/key mismatch' >&2; exit 1; }
install -m 0644 "$RENEWED_LINEAGE/fullchain.pem" "$cert_directory/fullchain.pem.next"
install -m 0600 "$RENEWED_LINEAGE/privkey.pem" "$cert_directory/privkey.pem.next"
mv "$cert_directory/fullchain.pem.next" "$cert_directory/fullchain.pem"
mv "$cert_directory/privkey.pem.next" "$cert_directory/privkey.pem"
if [[ -n "$("${compose[@]}" ps --status running -q nginx)" ]]; then
  "${compose[@]}" exec -T nginx nginx -t
  "${compose[@]}" exec -T nginx nginx -s reload
fi
