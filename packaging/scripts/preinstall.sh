#!/bin/bash

set -e

if id urfd &>/dev/null; then
    echo "User urfd already exists, skipping creation"
else
    echo "Creating urfd system user and group"
    useradd --system --home-dir /var/lib/urfd --shell /usr/sbin/nologin urfd || true
fi
