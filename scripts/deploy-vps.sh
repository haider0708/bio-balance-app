#!/usr/bin/env bash
# Deploy the current commit to the shared go2code VPS:
#   upload the source → build the image there → back up the database → migrate → restart → check health.
# Usage: scripts/deploy-vps.sh            (needs `ssh go2code`, sudo rights there, and a clean git tree)
set -euo pipefail
host=${DEPLOY_HOST:-go2code}
url=${DEPLOY_HEALTH_URL:-https://api.galylio.com/health}
cd "$(dirname "$0")/.."

git diff --quiet && git diff --cached --quiet || { echo "Commit your changes first: the image is built from HEAD." >&2; exit 1; }
sha=$(git rev-parse --short=8 HEAD)
src=/opt/biobalance-src-$sha
echo "== Deploying $sha to $host"

ssh "$host" "sudo rm -rf $src && sudo mkdir -p $src"
git archive HEAD apps/api infrastructure scripts docs package.json package-lock.json .npmrc .nvmrc | ssh "$host" "sudo tar -x -C $src"

echo "== Building the image on the server"
ssh "$host" "cd $src && sudo docker build -q -f infrastructure/production/Dockerfile -t biobalance-api:$sha ."

echo "== Installing the new files"
proxy_files="/opt/biobalance/infrastructure/production/shared-vps/nginx*.conf"
proxy_before=$(ssh "$host" "cat $proxy_files 2>/dev/null | sha256sum")
ssh "$host" "sudo rsync -a --delete --exclude /infrastructure/production/setup $src/ /opt/biobalance/ && sudo rm -rf $src"
proxy_after=$(ssh "$host" "cat $proxy_files | sha256sum")

echo "== Backing up the database"
ssh "$host" 'sudo mkdir -p /srv/biobalance-backups/pre-deploy && sudo chmod 700 /srv/biobalance-backups/pre-deploy'
ssh "$host" "docker exec biobalance-postgres-1 sh -c 'pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Fc' | sudo tee /srv/biobalance-backups/pre-deploy/before-$sha.dump >/dev/null"

previous=$(ssh "$host" "sudo grep '^API_IMAGE=' /etc/biobalance/backend.env | cut -d= -f2-")
ssh "$host" "echo '$previous' | sudo tee /etc/biobalance/previous-image >/dev/null; sudo sed -i 's|^API_IMAGE=.*|API_IMAGE=biobalance-api:$sha|' /etc/biobalance/backend.env"

echo "== Applying migrations"
ssh "$host" "sudo biobalance-compose run --rm migrate && sudo /opt/biobalance/scripts/provision-role-vps.sh"

echo "== Restarting, one API at a time: the other one keeps answering"
for service in api1 api2; do
  ssh "$host" "sudo biobalance-compose up -d --no-deps $service"
  state=starting
  for _ in $(seq 1 45); do
    state=$(ssh "$host" "docker inspect -f '{{.State.Health.Status}}' biobalance-$service-1" || true)
    [ "$state" = healthy ] && break
    sleep 2
  done
  if [ "$state" != healthy ]; then
    echo "$service did not become healthy; the other API still runs the previous image ($previous)." >&2
    echo "Roll back: put API_IMAGE=$previous back in /etc/biobalance/backend.env and run: sudo biobalance-compose up -d" >&2
    exit 1
  fi
  echo "$service is healthy."
done
ssh "$host" "sudo biobalance-compose up -d --remove-orphans"
# A changed proxy file needs a new nginx container (the files are mounted one by one); otherwise it keeps running.
if [ "$proxy_before" != "$proxy_after" ]; then
  echo "== The proxy settings changed: restarting nginx"
  ssh "$host" "sudo biobalance-compose up -d --no-deps --force-recreate nginx"
fi

echo "== Waiting for health"
for _ in $(seq 1 40); do
  if [ "$(curl -s -m 5 "$url" || true)" = '{"status":"ok"}' ]; then echo "Healthy: $sha is live."; exit 0; fi
  sleep 3
done
echo "Not healthy after two minutes. Previous image was: $previous" >&2
echo "Roll back: put API_IMAGE=$previous back in /etc/biobalance/backend.env and run: sudo biobalance-compose up -d" >&2
exit 1
