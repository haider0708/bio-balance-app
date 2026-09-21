#!/usr/bin/env bash
# Source from operational scripts; credentials stay in Compose's environment file.
: "${COMPOSE_FILE:?Set the absolute Compose file path}"
compose=(docker compose -f "$COMPOSE_FILE")
if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
  compose+=(--env-file "$COMPOSE_ENV_FILE")
elif [[ -f "$(dirname "$COMPOSE_FILE")/.env" ]]; then
  compose+=(--env-file "$(dirname "$COMPOSE_FILE")/.env")
fi
if [[ -n "${COMPOSE_OVERRIDE_FILE:-}" ]]; then compose+=(-f "$COMPOSE_OVERRIDE_FILE"); fi
if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then compose+=(-p "$COMPOSE_PROJECT_NAME"); fi
