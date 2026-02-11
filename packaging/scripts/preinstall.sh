#!/bin/bash

set -e

if [ -x "$(dirname "$0")/check-debian-trixie.sh" ]; then
  # Run the trixie check early to abort installation on incompatible distros
  "$(dirname "$0")/check-debian-trixie.sh"
fi

if id urfd &>/dev/null; then
    echo "User urfd already exists, skipping creation"
else
    echo "Creating urfd system user and group"
    useradd --system --home-dir /var/lib/urfd --shell /usr/sbin/nologin urfd || true
fi
