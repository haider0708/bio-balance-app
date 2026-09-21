#!/usr/bin/env bash
set -euo pipefail
source tests/deployment/lab-env.sh
lab="$PWD/.artifacts/deployment-lab"
mkdir -p "$lab/renewed" "$lab/mismatched"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout "$lab/renewed/privkey.pem" -out "$lab/renewed/fullchain.pem" -subj /CN=localhost -addext subjectAltName=DNS:localhost,IP:127.0.0.1 >/dev/null 2>&1
cp "$lab/certificates/fullchain.pem" "$lab/mismatched/fullchain.pem"
cp "$lab/renewed/privkey.pem" "$lab/mismatched/privkey.pem"
before=$(sha256sum "$lab/certificates/fullchain.pem")
if RENEWED_LINEAGE="$lab/mismatched" CERTIFICATE_DIR="$lab/certificates" bash scripts/tls-install.sh; then
  echo 'Mismatched certificate was not rejected' >&2; exit 1
fi
[[ "$before" == "$(sha256sum "$lab/certificates/fullchain.pem")" ]]
RENEWED_LINEAGE="$lab/renewed" CERTIFICATE_DIR="$lab/certificates" bash scripts/tls-install.sh
[[ "$before" != "$(sha256sum "$lab/certificates/fullchain.pem")" ]]
# Nginx reload is asynchronous; wait for workers serving the renewed certificate.
ready=false
for attempt in $(seq 1 100); do
  if curl --cacert "$lab/certificates/fullchain.pem" -fsS https://localhost:18443/health >/dev/null 2>&1; then ready=true; break; fi
  sleep .1
done
[[ "$ready" == true ]]
# A fresh client trusts this lab's renewed certificate only.
NODE_EXTRA_CA_CERTS="$lab/certificates/fullchain.pem" node tests/deployment/probe.cjs verify
printf 'PASS: certificate/key mismatch rejected, valid certificate installed and Nginx reloaded\n'
