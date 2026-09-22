#!/usr/bin/env bash
# Run only in the disposable, loopback-bound full-stack capacity lab.
set -euo pipefail
umask 077
mode=${1:?Choose smoke or acceptance}
[[ "$mode" == smoke || "$mode" == acceptance ]]
lab=/opt/biobalance-load-lab
cd "$lab"
set -a
source backend.env
set +a
[[ "$POSTGRES_DB" == biobalance_load_test ]]
compose=(docker compose -p biobalance-capacity-lab -f /opt/biobalance/infrastructure/production/compose.yml --env-file "$lab/backend.env" -f "$lab/override.yml")
sales=$("${compose[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc '\''SELECT count(*) FROM "Sale"'\''' </dev/null)
((sales>=2000000)) || { echo 'Full historical dataset required'; exit 1; }
transport=${CAPACITY_EXTERNAL:-no}
[[ "$transport" == yes || "$transport" == no ]]
label="$mode"; [[ "$transport" == no ]] || label="$mode-external"
out="$lab/results/$label-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
"${compose[@]}" ps --format json > "$out/services-before.jsonl"
mapfile -t service_containers < <("${compose[@]}" ps -q)
df -PB1 / > "$out/disk-before.txt"
free -b > "$out/memory-before.txt"
uname -r > "$out/kernel.txt"
export SSL_CERT_FILE="$lab/certificates/fullchain.pem"
export BASE_URLS=https://load.biobalance.invalid:18443
export FIXTURES="$lab/fixtures/load.json"
export ALLOW_SYNTHETIC_LOAD=yes SYNTHETIC_PROXY=yes
if [[ "$mode" == smoke ]]; then
  export STEADY_DURATION=10s BURST_DURATION=5s STEADY_RATE=5 BURST_RATE=10
else
  export STEADY_DURATION=5m BURST_DURATION=30s STEADY_RATE=100 BURST_RATE=200
fi
curl --fail --silent --show-error --max-time 10 --cacert "$SSL_CERT_FILE" \
  --resolve load.biobalance.invalid:18443:127.0.0.1 "$BASE_URLS/health" > "$out/tls-health.json"
if [[ "$transport" == yes ]]; then
  # The SSH client runs k6 elsewhere and publishes its result before this marker.
  # A lost client is bounded; the safety loop below still protects the live host.
  timeout 8m sh -c 'while [ ! -f "$1/client.done" ]; do sleep 1; done' sh "$out" &
  load_pid=$!
  printf 'CAPACITY_READY:%s\n' "$out"
else
  "$lab/tools/k6" run --config "$lab/k6-config.json" --summary-export "$out/summary.json" "$lab/tools/api.js" > "$out/k6.log" 2>&1 &
  load_pid=$!
fi
abort_reason=''
health_failures=0
stop_load() {
  if kill -0 "$load_pid" 2>/dev/null; then kill -INT "$load_pid" || true; fi
}
trap stop_load EXIT INT TERM
while kill -0 "$load_pid" 2>/dev/null; do
  free_bytes=$(df -PB1 / | awk 'NR==2{print $4}')
  available=$(awk '/MemAvailable:/{print $2}' /proc/meminfo)
  if ((free_bytes<12884901888 || available<1500000)); then
    abort_reason='Shared-host disk or memory reserve reached'
    stop_load
    break
  fi
  if curl --fail --silent --show-error --max-time 5 -A BioBalance-Monitor/1.0 https://api.galylio.com/health > "$out/live-health.json" 2>/dev/null; then
    health_failures=0
  else
    health_failures=$((health_failures+1))
  fi
  if ((health_failures>=3)); then
    abort_reason='Live API failed three independent health probes'
    stop_load
    break
  fi
  { date -u +%FT%TZ; docker stats --no-stream --format '{{json .}}' \
      "${service_containers[@]}"; } >> "$out/resources.jsonl"
  sleep 5
done
set +e
wait "$load_pid"
load_status=$?
set -e
if [[ "$transport" == yes && "$load_status" == 0 ]]; then
  load_status=$(cat "$out/client-exit-status.txt")
  [[ "$load_status" =~ ^[0-9]{1,3}$ ]] || exit 1
fi
trap - EXIT INT TERM
printf '%s\n' "$load_status" > "$out/k6-exit-status.txt"
printf '%s\n' "$abort_reason" > "$out/abort-reason.txt"
export LOAD_OWNER_DATABASE_URL="$MIGRATION_DATABASE_URL"
# Always check ledger consistency, including when a latency threshold fails.
set +e
"${compose[@]}" run --rm -T --no-deps -u 0 -e NODE_PATH=/app/node_modules -e LOAD_OWNER_DATABASE_URL \
  -v "$lab/tools:/operator:ro" migrate node /operator/verify.cjs </dev/null > "$out/ledger-verification.log" 2>&1
ledger_status=$?
set -e
printf '%s\n' "$ledger_status" > "$out/ledger-exit-status.txt"
"${compose[@]}" ps --format json > "$out/services-after.jsonl"
df -PB1 / > "$out/disk-after.txt"
free -b > "$out/memory-after.txt"
printf 'Capacity evidence: %s\n' "$out"
tail -70 "$out/k6.log"
cat "$out/ledger-verification.log"
[[ "$load_status" == 0 && "$ledger_status" == 0 && -z "$abort_reason" ]]
