#!/usr/bin/env bash
# Run docker compose with the generated dev environment.

set -euo pipefail

ENV_FILE="${URFD_DEV_ENV_FILE:-.env.dev}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}; run: task dev-env" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

exec docker compose --env-file "${ENV_FILE}" "$@"
