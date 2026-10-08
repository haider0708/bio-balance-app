#!/usr/bin/env bash
# Build the admin web page from the app's code and publish it on the shared go2code VPS at https://admin.galylio.com/
# Usage: scripts/deploy-web.sh        (needs Flutter locally, `ssh go2code` and sudo rights there)
# The page needs no restart: nginx serves the files from /opt/biobalance-web and re-checks them on every visit.
set -euo pipefail
host=${DEPLOY_HOST:-go2code}
url=${DEPLOY_WEB_URL:-https://admin.galylio.com/}
cd "$(dirname "$0")/../apps/mobile"

echo "== Building the web page"
flutter build web --release --base-href / --dart-define=API_BASE_URL=https://admin.galylio.com --no-web-resources-cdn --csp --no-source-maps --no-wasm-dry-run >/dev/null
cp -r build/web "/tmp/biobalance-web.$$"
trap 'rm -rf "/tmp/biobalance-web.$$"' EXIT

echo "== Uploading to $host"
ssh "$host" 'sudo mkdir -p /opt/biobalance-web'
# The entry files go last, so a visitor never gets a new index with old files.
rsync -a --delete --rsync-path='sudo rsync' --exclude '/index.html' --exclude '/flutter_bootstrap.js' --exclude '/flutter_service_worker.js' --exclude '/version.json' "/tmp/biobalance-web.$$/" "$host:/opt/biobalance-web/"
rsync -a --rsync-path='sudo rsync' "/tmp/biobalance-web.$$/index.html" "/tmp/biobalance-web.$$/flutter_bootstrap.js" "/tmp/biobalance-web.$$/flutter_service_worker.js" "/tmp/biobalance-web.$$/version.json" "$host:/opt/biobalance-web/"
ssh "$host" 'sudo chown -R root:root /opt/biobalance-web && sudo chmod -R a+rX /opt/biobalance-web'

echo "== Checking"
code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$url")
[ "$code" = 200 ] && echo "Live: $url" || { echo "The page answered $code" >&2; exit 1; }
