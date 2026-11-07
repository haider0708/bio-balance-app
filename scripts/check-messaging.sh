#!/usr/bin/env bash
# Is the messaging working? Run every five minutes by biobalance-messaging.timer.
#
# The exit status is a bit mask that scripts/monitor-report.py turns into precise alerts:
#   0  all good
#   1  WhatsApp is switched on but its session is not WORKING (credentials, codes and updates are not reaching phones)
#   2  messages failed for good in the last 3 days (someone did not get an email or a WhatsApp)
#   3  both
#  64  the check itself could not run (database or container unreachable)
# A failed message is kept 14 days by the cleanup, but alerts only for 3: long enough to be seen and fixed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"

sql() {
  "${compose[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -At' <<<"$1"
}

failed=$(sql "SELECT count(*) FROM \"Job\" WHERE status = 'failed' AND \"createdAt\" > now() - interval '3 days'") || exit 64
enabled=$(sql "SELECT coalesce((SELECT value->>'enabled' FROM \"AppSetting\" WHERE key = 'whatsapp'), 'false')") || exit 64

# The session status straight from WAHA, asked twice 20 seconds apart: a restart in progress is not an incident.
session_working() {
  local container
  container=$(docker ps -q --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-biobalance}" --filter label=com.docker.compose.service=waha | head -n1)
  [[ -n "$container" ]] || return 1
  docker exec "$container" sh -c 'wget -qO- --timeout=8 --header="X-Api-Key: $WAHA_API_KEY" http://localhost:3000/api/sessions/default' 2>/dev/null |
    python3 -c 'import sys,json; sys.exit(json.load(sys.stdin).get("status") != "WORKING")' 2>/dev/null
}

status=0
if [[ "$enabled" == true ]]; then
  if session_working; then
    echo 'PASS: the WhatsApp session is working'
  else
    sleep 20
    if session_working; then
      echo 'PASS: the WhatsApp session is working'
    else
      echo 'FAIL: the WhatsApp session is not working (scan the QR code again: docs/runbook.md, "WhatsApp")' >&2
      status=$((status | 1))
    fi
  fi
else
  echo 'SKIP: WhatsApp is switched off in the settings'
fi

if ((failed > 0)); then
  echo "FAIL: $failed message(s) failed for good in the last 3 days" >&2
  status=$((status | 2))
else
  echo 'PASS: no message failed in the last 3 days'
fi
exit "$status"
