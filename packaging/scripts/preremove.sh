#!/bin/bash

set -e

systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

for service in urfd.service urfd-tcd.service urfd-dashboard.service urfd-allstar-nexus.service; do
    if systemd_available; then
        if systemctl is-active --quiet "$service"; then
            echo "Stopping $service"
            systemctl stop "$service"
        fi
        if systemctl is-enabled --quiet "$service"; then
            echo "Disabling $service"
            systemctl disable "$service"
        fi
    else
        echo "systemd not present; skipping stop/disable for $service"
    fi
done
