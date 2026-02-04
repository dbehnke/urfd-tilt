#!/usr/bin/env bash
set -euo pipefail

# Ensure this package is being installed on Debian trixie
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" = "debian" ] && [ "${VERSION_CODENAME:-}" != "trixie" ]; then
    echo "This package is intended for Debian 'trixie'. Detected: ${PRETTY_NAME:-$ID ${VERSION_CODENAME:-}}" >&2
    echo "Aborting installation to avoid incompatible runtime." >&2
    exit 1
  fi
fi

exit 0
