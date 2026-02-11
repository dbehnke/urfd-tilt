#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 PUBLIC_KEY [OUTFILE]" >&2
  exit 2
fi

PUBKEY="$1"
OUTFILE="${2:-/tmp/packer-user-data-$$.yml}"

cat > "$OUTFILE" <<EOF
#cloud-config
users:
  - name: packer
    gecos: Packer User
    primary_group: packer
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    passwd: ""

package_update: true
package_upgrade: true

ssh_pwauth: true
ssh_authorized_keys:
  - "$PUBKEY"

runcmd:
  - [ sh, -c, 'mkdir -p /tmp/urfd-dist || true' ]
EOF

echo "$OUTFILE"
