#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
out=${VPS_LOAD_CLIENT_DIR:?Set an absolute private directory containing fixtures.json, ca.pem and k6-config.json}
[[ "$out" == /* ]]
for required in fixtures.json ca.pem k6-config.json; do test -f "$out/$required"; done
export SSL_CERT_FILE="$out/ca.pem" BASE_URLS=https://load.biobalance.invalid:18443
export FIXTURES="$out/fixtures.json" ALLOW_SYNTHETIC_LOAD=yes SYNTHETIC_PROXY=yes
export STEADY_DURATION=5m BURST_DURATION=30s STEADY_RATE=100 BURST_RATE=200
ssh -o BatchMode=yes -o ServerAliveInterval=15 go2code 'sudo -n env CAPACITY_EXTERNAL=yes bash /opt/biobalance-load-lab/qualify-external.sh acceptance' > "$out/observer.log" 2>&1 &
observer=$!
for attempt in {1..60}; do
  if grep -q '^CAPACITY_READY:' "$out/observer.log"; then break; fi
  kill -0 "$observer" || { cat "$out/observer.log"; exit 1; }
  sleep 1
done
remote_out=$(sed -n 's/^CAPACITY_READY://p' "$out/observer.log" | head -1)
[[ "$remote_out" =~ ^/opt/biobalance-load-lab/results/acceptance-external-[0-9TZ]+$ ]]
printf '%s\n' "$remote_out" > "$out/remote-directory.txt"
"$root/.tooling/k6/k6" run --config "$out/k6-config.json" --summary-export "$out/summary.json" "$root/tests/load/api.js" > "$out/k6.log" 2>&1 &
client=$!
trap 'kill -INT "$client" 2>/dev/null || true' EXIT INT TERM
while kill -0 "$client" 2>/dev/null; do
  if ! kill -0 "$observer" 2>/dev/null; then kill -INT "$client" || true; break; fi
  sleep 3
done
set +e
wait "$client"; client_status=$?
set -e
trap - EXIT INT TERM
printf '%s\n' "$client_status" > "$out/client-exit-status.txt"
for file in k6.log summary.json client-exit-status.txt; do
 ssh -o BatchMode=yes go2code "sudo -n tee '$remote_out/$file' >/dev/null" < "$out/$file"
done
ssh -o BatchMode=yes go2code "sudo -n touch '$remote_out/client.done'"
set +e
wait "$observer"; observer_status=$?
set -e
printf 'Client status=%s; server/ledger status=%s\n' "$client_status" "$observer_status"
printf '%s\n' "$client_status" > "$out/client-exit-status.txt"
tail -68 "$out/observer.log"
[[ "$client_status" == 0 && "$observer_status" == 0 ]]
