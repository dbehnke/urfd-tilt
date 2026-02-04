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

cat << 'EOF'
URFD installation complete!

Next steps:
1. Configure services by editing files in /etc/urfd/
2. Enable and start services with (if systemd is in use):
   systemctl enable urfd.service
   systemctl enable urfd-tcd.service
   systemctl enable urfd-dashboard.service
   systemctl enable urfd-allstar-nexus.service
   systemctl start urfd.service
   systemctl start urfd-tcd.service
   systemctl start urfd-dashboard.service
   systemctl start urfd-allstar-nexus.service

3. Check status with: systemctl status urfd.service
4. View logs with: journalctl -u urfd -f

Documentation is available in /usr/share/doc/urfd/
EOF
