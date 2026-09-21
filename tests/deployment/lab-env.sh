#!/usr/bin/env bash
set -euo pipefail
# Source from the repository root after setup.py.
export COMPOSE_FILE="$PWD/infrastructure/production/compose.yml"
export COMPOSE_ENV_FILE="$PWD/.artifacts/deployment-lab/.env"
export COMPOSE_OVERRIDE_FILE="$PWD/.artifacts/deployment-lab/override.yml"
export COMPOSE_PROJECT_NAME=biobalance-release-lab
export BACKUP_DIR="$PWD/.artifacts/deployment-lab/backups"
source "$PWD/scripts/compose-common.sh"
