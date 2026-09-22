#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/compose-common.sh"
: "${BACKUP_DIR:?Set backup path}"
usage=$(df -P "$BACKUP_DIR" | awk 'NR==2{gsub(/%/,"",$5);print $5}')
((usage < 85)) || { printf 'Disk usage is %s%%\n' "$usage" >&2; exit 1; }
recent=$(find "$BACKUP_DIR" -maxdepth 2 -name SHA256SUMS -mmin -1560 -print -quit)
[[ -n "$recent" ]] || { printf 'No completed backup within 26 hours\n' >&2; exit 1; }
python3 - <<'PY'
import os
memory={row.split()[0].rstrip(':'):int(row.split()[1]) for row in open('/proc/meminfo') if row.split()[1].isdigit()}
if memory['MemAvailable']/memory['MemTotal'] < .10:raise SystemExit('Available memory below 10%')
if os.getloadavg()[1] > (os.cpu_count() or 1)*1.5:raise SystemExit('Sustained CPU load above capacity')
print('PASS: host memory and sustained load')
PY
"${compose[@]}" ps --format json | python3 -c 'import sys,json; rows=[json.loads(s) for s in sys.stdin if s.strip()]; expected={"api1","api2","worker","media-worker","postgres","nginx"}; states={r["Service"]:r for r in rows}; bad=[s for s in expected if s not in states or states[s].get("State")!="running" or states[s].get("Health")!="healthy"]; print("Unhealthy services:",bad);sys.exit(bool(bad))'
"${compose[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -At' <<'SQL' | python3 -c 'import sys,json; row=json.loads(sys.stdin.read());print("Job diagnostics:",row);sys.exit(any(row.values()))'
SELECT json_build_object('failed',count(*) FILTER(WHERE status='failed'),
  'stale',count(*) FILTER(WHERE status='running' AND "lockedAt"<now()-interval '16 minutes'),
  'overdue',count(*) FILTER(WHERE status='pending' AND "availableAt"<now()-interval '5 minutes')) FROM "Job";
SQL
if [[ -n "${PUBLIC_HEALTH_URL:-}" ]]; then
  python3 - <<'PY'
import json,os,urllib.request,urllib.parse
url=os.environ['PUBLIC_HEALTH_URL']
parsed=urllib.parse.urlsplit(url)
if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password:
    raise SystemExit('Public health check requires an HTTPS URL without credentials')
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
request=urllib.request.Request(url,headers={'User-Agent':'BioBalance-Monitor/1.0','Accept':'application/json'})
with urllib.request.build_opener(NoRedirect()).open(request,timeout=15) as response:
    if response.status!=200 or json.loads(response.read(4096))!={'status':'ok'}:
        raise SystemExit('Public API health check failed')
print('PASS: public HTTPS endpoint and certificate trust')
PY
fi
if [[ -n "${TLS_CERTIFICATE_FILE:-}" ]]; then
  openssl x509 -in "$TLS_CERTIFICATE_FILE" -noout -checkend 604800 >/dev/null || {
    echo 'Origin certificate expires within seven days or is unreadable' >&2; exit 1;
  }
  echo 'PASS: origin certificate remains valid for more than seven days'
fi
