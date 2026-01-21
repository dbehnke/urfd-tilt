#!/usr/bin/env bash
# Calculate port mappings for URFD production instances
# Usage: calculate-ports.sh <instance-name>
# Example: calculate-ports.sh URF001

set -euo pipefail

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

# Usage
usage() {
    cat <<EOF
${BOLD}URFD Port Calculator${RESET}

Calculates port mappings for URFD production instances based on instance number.

${BOLD}Usage:${RESET}
  $0 <instance-name>

${BOLD}Examples:${RESET}
  $0 URF000    # Offset 0 (base ports)
  $0 URF001    # Offset 100
  $0 URF999    # Offset 99900

${BOLD}Port Offset Formula:${RESET}
  OFFSET = INSTANCE_NUMBER * 100

${BOLD}Instance Naming:${RESET}
  - Must match pattern: URF[0-9]{3} (e.g., URF000, URF001, URF999)
  - Leading zeros are required (URF1 is invalid, use URF001)

${BOLD}Output Format:${RESET}
  Prints environment variable assignments suitable for .env files
EOF
    exit 0
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    usage
fi

INSTANCE_NAME="$1"

# Show help
if [[ "${INSTANCE_NAME}" == "-h" ]] || [[ "${INSTANCE_NAME}" == "--help" ]]; then
    usage
fi

# Validate instance name format
if ! [[ "${INSTANCE_NAME}" =~ ^URF[0-9]{3}$ ]]; then
    echo -e "${YELLOW}Error: Invalid instance name format${RESET}"
    echo ""
    echo "Instance name must match pattern: URF[0-9]{3}"
    echo "Examples: URF000, URF001, URF042, URF999"
    echo ""
    echo "Invalid: URF0, URF1, URF01, URFD000, urf001"
    exit 1
fi

# Extract instance number
INSTANCE_NUM="${INSTANCE_NAME:3}"  # Remove "URF" prefix
INSTANCE_NUM=$((10#${INSTANCE_NUM}))  # Convert to decimal (handle leading zeros)

# Calculate port offset
PORT_OFFSET=$((INSTANCE_NUM * 100))

# Base ports (URF000)
BASE_DEXTRA=30001
BASE_DPLUS=20001
BASE_DCS=30051
BASE_DMRPLUS=8880
BASE_MMDVM=62030
BASE_M17=17000
BASE_YSF=42000
BASE_P25=41000
BASE_NXDN=41400
BASE_URF=10017
BASE_TRANSCODER=10100
BASE_G3=40000
BASE_NNG_DASHBOARD=5555
BASE_NNG_VOICE=5556
BASE_NNG_CONTROL=6556
BASE_DASHBOARD_HTTP=8080

# Calculate instance ports
PORT_DEXTRA=$((BASE_DEXTRA + PORT_OFFSET))
PORT_DPLUS=$((BASE_DPLUS + PORT_OFFSET))
PORT_DCS=$((BASE_DCS + PORT_OFFSET))
PORT_DMRPLUS=$((BASE_DMRPLUS + PORT_OFFSET))
PORT_MMDVM=$((BASE_MMDVM + PORT_OFFSET))
PORT_M17=$((BASE_M17 + PORT_OFFSET))
PORT_YSF=$((BASE_YSF + PORT_OFFSET))
PORT_P25=$((BASE_P25 + PORT_OFFSET))
PORT_NXDN=$((BASE_NXDN + PORT_OFFSET))
PORT_URF=$((BASE_URF + PORT_OFFSET))
PORT_TRANSCODER=$((BASE_TRANSCODER + PORT_OFFSET))
PORT_G3=$((BASE_G3 + PORT_OFFSET))
PORT_NNG_DASHBOARD=$((BASE_NNG_DASHBOARD + PORT_OFFSET))
PORT_NNG_VOICE=$((BASE_NNG_VOICE + PORT_OFFSET))
PORT_NNG_CONTROL=$((BASE_NNG_CONTROL + PORT_OFFSET))
PORT_DASHBOARD_HTTP=$((BASE_DASHBOARD_HTTP + PORT_OFFSET))

# Output port assignments
echo "# Port assignments for ${INSTANCE_NAME}"
echo "# Instance number: ${INSTANCE_NUM}"
echo "# Port offset: ${PORT_OFFSET}"
echo ""
echo "# Digital Voice Protocol Ports (UDP)"
echo "PORT_DEXTRA=${PORT_DEXTRA}"
echo "PORT_DPLUS=${PORT_DPLUS}"
echo "PORT_DCS=${PORT_DCS}"
echo "PORT_DMRPLUS=${PORT_DMRPLUS}"
echo "PORT_MMDVM=${PORT_MMDVM}"
echo "PORT_M17=${PORT_M17}"
echo "PORT_YSF=${PORT_YSF}"
echo "PORT_P25=${PORT_P25}"
echo "PORT_NXDN=${PORT_NXDN}"
echo "PORT_URF=${PORT_URF}"
echo ""
echo "# Service Ports (TCP)"
echo "PORT_TRANSCODER=${PORT_TRANSCODER}"
echo "PORT_G3=${PORT_G3}"
echo "PORT_NNG_DASHBOARD=${PORT_NNG_DASHBOARD}"
echo "PORT_NNG_VOICE=${PORT_NNG_VOICE}"
echo "PORT_NNG_CONTROL=${PORT_NNG_CONTROL}"
echo "PORT_DASHBOARD_HTTP=${PORT_DASHBOARD_HTTP}"
