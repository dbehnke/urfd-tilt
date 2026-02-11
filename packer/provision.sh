#!/usr/bin/env bash
set -euo pipefail

DEBDIR="/tmp/urfd-dist"
export DEBIAN_FRONTEND=noninteractive

if [ ! -d "$DEBDIR" ]; then
  echo "ERROR: expected deb directory $DEBDIR not found"
  exit 1
fi

echo "Installing .deb packages from $DEBDIR"
dpkg -i "$DEBDIR"/*.deb || true

echo "Fixing dependencies via apt"
apt-get update
apt-get -y -f install

echo "Reloading systemd daemon (if present)"
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi

SERVICES=(urfd urfd-dashboard tcd urfd-allstar-nexus)
for s in "${SERVICES[@]}"; do
  echo "--- Checking service: $s ---"
  if systemctl list-unit-files | grep -q "^${s}\.service"; then
    systemctl enable --now "${s}.service" || echo "enable/start returned non-zero for ${s}"
    systemctl status "${s}.service" --no-pager || true
    echo "---- journal (${s}) last 200 lines ----"
    journalctl -u "${s}.service" -n 200 --no-pager || true
  else
    echo "Unit ${s}.service not found; skipping"
  fi
done

echo "Provisioning complete"
