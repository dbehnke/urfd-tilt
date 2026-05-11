#!/usr/bin/env bash
# Basic local smoke checks for the Compose dev stack.

set -euo pipefail

ENV_FILE="${URFD_DEV_ENV_FILE:-.env.dev}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}; run: task dev-env" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

docker compose --env-file "${ENV_FILE}" config >/dev/null
docker compose --env-file "${ENV_FILE}" ps

if command -v curl >/dev/null 2>&1; then
  curl --fail --silent --show-error "http://localhost:${PORT_DASHBOARD_HTTP}/" >/dev/null
  echo "Dashboard responded on http://localhost:${PORT_DASHBOARD_HTTP}"
else
  echo "curl not found; skipped dashboard HTTP check"
fi

docker compose --env-file "${ENV_FILE}" exec -T urfd ss -lun | grep -q ":30001 "
echo "URFD is listening on container UDP port 30001"
