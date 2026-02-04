#!/usr/bin/env bash
set -euo pipefail

if ! command -v colima >/dev/null 2>&1; then
  echo "colima not installed; see https://github.com/abiosoft/colima" >&2
  exit 1
fi

if colima status >/dev/null 2>&1; then
  echo "Colima already running"
else
  echo "Starting Colima..."
  colima start --cpu 4 --memory 4096
fi

echo "Colima is ready for Tilt."
