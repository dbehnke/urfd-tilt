#!/bin/bash
# Test script to verify UDP ports are accessible

echo "Testing URFD UDP Ports..."
echo ""

# List of ports to test
ports=(
    "30001:DExtra"
    "20001:DPlus"
    "30051:DCS"
    "62030:MMDVM"
    "8880:DMRPlus"
    "42000:YSF"
    "17000:M17"
    "41000:P25"
    "41400:NXDN"
    "10017:URF"
)

# Test localhost
echo "Testing from localhost..."
for port_info in "${ports[@]}"; do
    IFS=':' read -r port protocol <<< "$port_info"
    echo -n "  Port $port ($protocol): "
    
    # Send a test packet using nc (netcat)
    if timeout 1 bash -c "echo 'test' | nc -u -w1 localhost $port" 2>/dev/null; then
        echo "✓ Port is open"
    else
        # Check if urfd is listening
        if docker exec urfd ss -lun 2>/dev/null | grep -q ":$port "; then
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
