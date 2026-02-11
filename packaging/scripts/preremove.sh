#!/bin/bash

set -e

systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

for service in urfd.service urfd-tcd.service urfd-dashboard.service urfd-allstar-nexus.service; do
    if systemd_available; then
        # Only attempt to stop/disable if systemctl appears functional and PID 1 is systemd
        if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                echo "Stopping $service"
                systemctl stop "$service" || true
            fi
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                echo "Disabling $service"
                systemctl disable "$service" || true
            fi
        else
            echo "PID 1 is not systemd; skipping systemctl operations for $service"
        fi
    else
        echo "systemd not present; skipping stop/disable for $service"
    fi
done
