#!/bin/bash

set -e

systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

if systemd_available; then
    systemctl daemon-reload
else
    echo "systemd not present or not running; skipping daemon-reload"
fi

if [ "$1" = "purge" ]; then
    echo "Purging URFD configuration and data..."
    rm -rf /etc/urfd
    rm -rf /var/log/urfd
    rm -rf /var/lib/urfd

    if id urfd &>/dev/null; then
        echo "Removing urfd user and group"
        userdel urfd || true
    fi
fi
