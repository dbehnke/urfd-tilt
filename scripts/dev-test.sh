#!/usr/bin/env bash
# Run development tests for initialized service repositories.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS=0
RAN=0

run_task_tests() {
  local service_dir="$1"
  local service_name="$2"

  if [[ -f "${PROJECT_ROOT}/${service_dir}/Taskfile.yml" ]]; then
    RAN=1
    echo "==> ${service_name}: task test"
    if ! (cd "${PROJECT_ROOT}/${service_dir}" && task test); then
      STATUS=1
    fi
  fi
}

run_task_tests "src/urfd-nng-dashboard" "URFD NNG Dashboard"
run_task_tests "src/allstar-nexus" "AllStar Nexus"

if [[ "${RAN}" -eq 0 ]]; then
  echo "No service test Taskfiles found. Run task init to initialize submodules."
fi

exit "${STATUS}"
