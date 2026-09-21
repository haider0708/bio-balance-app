#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DATABASE_URL:?Use the restricted application connection to an isolated *_load_test database}"
: "${LOAD_OWNER_DATABASE_URL:?Use the owner connection to the same isolated load database}"
export NODE_ENV=production
# Synthetic MFA key shared by both load processes; never a deployment credential.
export MFA_ENCRYPTION_KEY=$(node -e 'process.stdout.write(require("node:crypto").randomBytes(32).toString("base64"))')
instances=${API_INSTANCES:-2}
[[ "$instances" = 1 || "$instances" = 2 ]]
mkdir -p .artifacts/evidence/step10
load_tmp=$(mktemp -d -t biobalance-load-XXXXXXXX)
load_api_pids=()
cleanup() {
  for pid in "${load_api_pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${load_api_pids[@]}"; do wait "$pid" 2>/dev/null || true; done
  rm -rf "$load_tmp"
}
trap cleanup EXIT
urls=()
for index in $(seq 1 "$instances"); do
  PORT=0 LOAD_READY_FILE="$load_tmp/port-$index" node tests/load/serve.cjs > ".artifacts/evidence/step10/api-$index.log" 2>&1 &
  load_api_pids+=("$!")
  for attempt in $(seq 1 40); do
    if [[ -s "$load_tmp/port-$index" ]]; then break; fi
    kill -0 "${load_api_pids[-1]}"
    sleep .25
  done
  port=$(cat "$load_tmp/port-$index")
  [[ "$port" =~ ^[0-9]+$ ]]
  curl -fsS "http://127.0.0.1:$port/health" >/dev/null
  urls+=("http://127.0.0.1:$port")
done
bases=$(IFS=,; echo "${urls[*]}")
set +e
ALLOW_SYNTHETIC_LOAD=yes BASE_URLS="$bases" FIXTURES="${LOAD_FIXTURES:-$PWD/.artifacts/load-fixtures.json}" \
  "${K6_BIN:-$PWD/.tooling/k6/k6}" run --summary-export=.artifacts/evidence/step10/load-summary.json tests/load/api.js
load_status=$?
set -e
node tests/load/verify.cjs > .artifacts/evidence/step10/integrity.log 2>&1
exit "$load_status"
