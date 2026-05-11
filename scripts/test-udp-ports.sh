#!/usr/bin/env bash
# Test script to verify UDP ports are accessible

set -euo pipefail

ENV_FILE="${URFD_DEV_ENV_FILE:-.env.dev}"

if [[ -f "${ENV_FILE}" ]]; then
    set -a
    source "${ENV_FILE}"
    set +a
fi

echo "Testing URFD UDP Ports..."
echo ""

# List of ports to test
ports=(
    "${PORT_DEXTRA:-30001}:30001:DExtra"
    "${PORT_DPLUS:-20001}:20001:DPlus"
    "${PORT_DCS:-30051}:30051:DCS"
    "${PORT_MMDVM:-62030}:62030:MMDVM"
    "${PORT_DMRPLUS:-8880}:8880:DMRPlus"
    "${PORT_YSF:-42000}:42000:YSF"
    "${PORT_M17:-17000}:17000:M17"
    "${PORT_P25:-41000}:41000:P25"
    "${PORT_NXDN:-41400}:41400:NXDN"
    "${PORT_URF:-10017}:10017:URF"
)

# Test localhost
echo "Testing from localhost..."
for port_info in "${ports[@]}"; do
    IFS=':' read -r host_port container_port protocol <<< "$port_info"
    echo -n "  Port ${host_port} -> ${container_port} (${protocol}): "
    
    # Send a test packet using nc (netcat)
    if timeout 1 bash -c "echo 'test' | nc -u -w1 localhost ${host_port}" 2>/dev/null; then
        echo "✓ Port is open"
    else
        # Check if urfd is listening
        if docker compose --env-file "${ENV_FILE}" exec -T urfd ss -lun 2>/dev/null | grep -q ":${container_port} "; then
            echo "✓ URFD is listening"
        else
            echo "✗ Not listening"
        fi
    fi
done

echo ""
echo "Getting host IP addresses..."
if command -v ip &> /dev/null; then
    ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}'
elif command -v ifconfig &> /dev/null; then
    ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}'
fi

echo ""
echo "To connect from another machine, use one of the IP addresses above with the appropriate port."
