#!/usr/bin/env bash
set -euo pipefail

# Wrapper: chooses podman direct vs podman machine based on OS and flags.
MODE=""
KEEP_MACHINE=false

usage() {
  cat <<EOF
Usage: $0 [--dist DIR] [--image IMAGE] [--mode force_direct|force_machine] [--keep-machine] [--help]
Defaults: dist=./dist image=ubuntu:22.04
EOF
}

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --keep-machine) KEEP_MACHINE=true; shift;;
    -h|--help) usage; exit 0;;
    *) ARGS+=("$1"); shift;;
  esac
done

# Build invocation
CMD=(bash scripts/test-systemd.sh "${ARGS[@]}")
[ -n "$MODE" ] && CMD+=(--mode "$MODE")
$KEEP_MACHINE && CMD+=(--keep-machine)

echo "Invoking: ${CMD[*]}"
"${CMD[@]}"
