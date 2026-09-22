#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${FLUTTER_BIN:=flutter}"
export FLUTTER_BIN
mkdir -p .artifacts/evidence/step11
python3 tests/deployment/setup.py
source tests/deployment/lab-env.sh
lab="$PWD/.artifacts/deployment-lab"
evidence="$PWD/.artifacts/evidence/step11"
umask 077
# Build every image before creating containers, so an old local tag is never selected.
docker build --target runtime -f infrastructure/production/Dockerfile -t biobalance-api:step11-local . > "$evidence/build-api.log" 2>&1
docker build --target media -f infrastructure/production/Dockerfile -t biobalance-media:step11-local . > "$evidence/build-media.log" 2>&1
rollback_ref=${ROLLBACK_REF:-a8b4610}
git rev-parse --verify "$rollback_ref^{commit}" >/dev/null
rollback_source="$lab/rollback-$rollback_ref"
if [[ ! -d "$rollback_source" ]]; then mkdir "$rollback_source"; git archive "$rollback_ref" | tar -x -C "$rollback_source"; fi
docker build --target runtime -f infrastructure/production/Dockerfile -t "biobalance-api:rollback-$rollback_ref" "$rollback_source" > "$evidence/build-rollback.log" 2>&1
docker build --target media -f infrastructure/production/Dockerfile -t "biobalance-media:rollback-$rollback_ref" "$rollback_source" > "$evidence/build-rollback-media.log" 2>&1
"${compose[@]}" config --quiet
"${compose[@]}" up -d --wait postgres mailpit > "$evidence/up.log" 2>&1
"${compose[@]}" run --rm -T migrate > "$evidence/migrate.log" 2>&1
app_password=$(python3 -c 'import json;print(json.loads(next(x.split("=",1)[1] for x in open(".artifacts/deployment-lab/.env") if x.startswith("APP_PASSWORD="))))')
"${compose[@]}" exec -T postgres psql -U biobalance_owner -d biobalance_deployment_test -v app_password="$app_password" < scripts/provision-role.sql > "$evidence/provision.log" 2>&1
if [[ ! -s "$lab/bootstrap/credentials.json" ]]; then
  "${compose[@]}" run --rm -T -v "$lab/bootstrap:/bootstrap" -e ADMIN_EMAIL=admin@example.test -e ADMIN_SETUP_FILE=/bootstrap/credentials.json api1 node dist/bootstrap-admin.js > "$evidence/bootstrap.log" 2>&1
fi
if [[ ! -s "$lab/fixture.json" ]]; then
  "${compose[@]}" run --rm -T migrate node - < tests/deployment/seed.cjs > "$lab/fixture.json" 2> "$evidence/fixture.log"
else
  "${compose[@]}" run --rm -T -v "$lab/fixture.json:/run/deployment-fixture.json:ro" migrate node - < tests/deployment/refresh-fixture.cjs > "$evidence/fixture-refresh.log" 2>&1
fi
"${compose[@]}" up -d --wait api1 api2 worker media-worker nginx > "$evidence/up-app.log" 2>&1
export NODE_EXTRA_CA_CERTS="$lab/certificates/fullchain.pem"
if [[ -s "$lab/state.json" ]]; then node tests/deployment/probe.cjs verify > "$evidence/probe.log" 2>&1;
else node tests/deployment/probe.cjs > "$evidence/probe.log" 2>&1; fi
node tests/deployment/inspect.cjs > "$evidence/isolation.log" 2>&1
node tests/deployment/mail.cjs > "$evidence/mail.log" 2>&1
python3 - <<'PY'
import json,pathlib
p=pathlib.Path('.artifacts/deployment-lab');f=json.loads((p/'fixture.json').read_text());s=json.loads((p/'state.json').read_text())
out=p/'mobile-fixture.json';out.write_text(json.dumps({'baseUrl':'https://127.0.0.1:18443','account':f['managerId'],'token':f['managerToken'],'media':s['video'],'certificate':str((p/'certificates/fullchain.pem').resolve())}));out.chmod(0o600)
PY
(cd apps/mobile && BIOBALANCE_DEPLOYMENT_FIXTURE="$lab/mobile-fixture.json" "$FLUTTER_BIN" test test/deployment_media_test.dart) > "$evidence/proxy-download.log" 2>&1
bash tests/deployment/tls-test.sh > "$evidence/tls.log" 2>&1
"${compose[@]}" stop worker > "$evidence/worker-stop.log" 2>&1
"${compose[@]}" run --rm -T migrate node - < tests/deployment/jobs.cjs > "$lab/jobs.json" 2> "$evidence/jobs-setup.log"
"${compose[@]}" up -d --wait worker > "$evidence/worker-restart.log" 2>&1
# A real failed job must produce a failing diagnostic status.
# This initial backup makes its freshness independent from the failure test.
bash scripts/local-backup.sh > "$evidence/backup-before-jobs.log" 2>&1
if bash scripts/check-vps.sh > "$evidence/monitor-failure.log" 2>&1; then echo 'Failed job was not diagnosed' >&2; exit 1; fi
rg -q "'failed': 1" "$evidence/monitor-failure.log"
export PROBE_STALE_ID=$(python3 -c 'import json;print(json.load(open(".artifacts/deployment-lab/jobs.json"))["stale"])')
export PROBE_FAILED_ID=$(python3 -c 'import json;print(json.load(open(".artifacts/deployment-lab/jobs.json"))["failed"])')
"${compose[@]}" run --rm -T -e PROBE_STALE_ID -e PROBE_FAILED_ID migrate node - < tests/deployment/job-recovery.cjs > "$evidence/job-recovery.log" 2>&1
bash scripts/check-vps.sh > "$evidence/monitor-recovered.log" 2>&1
TARGET_API_IMAGE="biobalance-api:rollback-$rollback_ref" TARGET_MEDIA_IMAGE="biobalance-media:rollback-$rollback_ref" node tests/deployment/rolling.cjs > "$evidence/rollback.log" 2>&1
node tests/deployment/probe.cjs verify >> "$evidence/rollback.log" 2>&1
TARGET_API_IMAGE=biobalance-api:step11-local TARGET_MEDIA_IMAGE=biobalance-media:step11-local node tests/deployment/rolling.cjs > "$evidence/roll-forward.log" 2>&1
node tests/deployment/probe.cjs verify >> "$evidence/roll-forward.log" 2>&1
"${compose[@]}" exec -T postgres psql -U biobalance_owner -d biobalance_deployment_test -At < tests/deployment/representative.sql > "$evidence/before-restore.json"
bash scripts/local-backup.sh > "$evidence/backup.log" 2>&1
export BACKUP_PATH=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)
bash scripts/verify-restore.sh > "$evidence/restore.log" 2>&1
restore_db=$(python3 -c 'import re;print(re.search(r"database=(\w+)",open(".artifacts/evidence/step11/restore.log").read())[1])')
"${compose[@]}" exec -T postgres psql -U biobalance_owner -d "$restore_db" -At < tests/deployment/representative.sql > "$evidence/after-restore.json"
cmp "$evidence/before-restore.json" "$evidence/after-restore.json"
bash scripts/check-vps.sh > "$evidence/monitor.log" 2>&1
printf 'PASS: isolated deployment, migrations, media, restart, rollback, backup and restoration.\n'
# Keep lab volumes and restored outputs for inspection. No existing data is deleted.
