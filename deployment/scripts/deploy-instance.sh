#!/usr/bin/env bash
# Deploy a new URFD production instance
# Usage: deploy-instance.sh <instance-name> <image-version> [options]

set -euo pipefail

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"
INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

# Default options
INSTALL_SYSTEMD=false
START_AFTER_DEPLOY=false
SKIP_VALIDATION=false

# Usage
usage() {
    cat <<EOF
${BOLD}URFD Production Instance Deployment${RESET}

Deploys a new URFD production instance with all required configuration.

${BOLD}Usage:${RESET}
  $0 <instance-name> <image-version> [OPTIONS]

${BOLD}Arguments:${RESET}
  instance-name    Instance identifier (format: URF[0-9]{3}, e.g., URF000, URF001)
  image-version    Docker image version tag (e.g., v1.0.0, v1.8.0-dev)

${BOLD}Options:${RESET}
  --systemd              Install and enable systemd service
  --start                Start instance immediately after deployment
  --skip-validation      Skip configuration validation (not recommended)
  --instances-dir PATH   Custom instances directory (default: ${INSTANCES_DIR})
  -h, --help             Show this help message

${BOLD}Examples:${RESET}
  $0 URF001 v1.0.0
  $0 URF042 v1.8.0-dev --systemd --start
  $0 URF999 v2.0.0-rc1 --instances-dir /custom/path

${BOLD}What This Script Does:${RESET}
  1. Validates instance name and version format
  2. Checks that instance doesn't already exist
  3. Creates instance directory structure
  4. Calculates port offsets automatically
  5. Copies and processes configuration templates
  6. Performs variable substitution in all config files
  7. Validates the deployment
  8. Optionally installs systemd service
  9. Optionally starts the instance

${BOLD}Instance Directory Structure:${RESET}
  \${INSTANCES_DIR}/<instance-name>/
    ├── .env                      # Environment variables
    ├── docker-compose.yml        # Docker Compose configuration
    ├── config/                   # Configuration files
    │   ├── urfd.ini
    │   ├── tcd.ini
    │   ├── dashboard/
    │   │   └── config.yaml
    │   └── allstar/              # Optional
    │       └── config.yaml
    └── data/                     # Runtime data
        ├── logs/
        ├── audio/
        └── dashboard/

${BOLD}Port Offset:${RESET}
  Ports are automatically calculated: OFFSET = INSTANCE_NUMBER * 100
  URF000 = offset 0, URF001 = offset 100, URF002 = offset 200, etc.

${BOLD}Environment Variables:${RESET}
  URFD_INSTANCES_DIR    Custom instances directory (default: /opt/urfd-production/instances)

${BOLD}Safety:${RESET}
  - Script will NOT overwrite existing instances (fail-safe)
  - Validation is performed before deployment completes
  - Docker images must be built beforehand

EOF
    exit 0
}

# Logging functions
log_step() {
    echo -e "${BOLD}${CYAN}[$(date '+%H:%M:%S')]${RESET} ${BOLD}$1${RESET}"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $1"
}

log_error() {
    echo -e "${RED}✗ ERROR:${RESET} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${RESET} $1"
}

log_info() {
    echo -e "${GRAY}  $1${RESET}"
}

# Parse arguments
INSTANCE_NAME=""
IMAGE_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --systemd)
            INSTALL_SYSTEMD=true
            shift
            ;;
        --start)
            START_AFTER_DEPLOY=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --instances-dir)
            INSTANCES_DIR="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "${INSTANCE_NAME}" ]]; then
                INSTANCE_NAME="$1"
            elif [[ -z "${IMAGE_VERSION}" ]]; then
                IMAGE_VERSION="$1"
            else
                log_error "Too many arguments"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "${INSTANCE_NAME}" ]] || [[ -z "${IMAGE_VERSION}" ]]; then
    log_error "Missing required arguments"
    echo ""
    echo "Usage: $0 <instance-name> <image-version> [OPTIONS]"
    echo "Use --help for more information"
    exit 1
fi

echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}         URFD Production Instance Deployment${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${CYAN}Instance:${RESET}      ${INSTANCE_NAME}"
echo -e "${CYAN}Version:${RESET}       ${IMAGE_VERSION}"
echo -e "${CYAN}Instances dir:${RESET} ${INSTANCES_DIR}"
echo -e "${CYAN}Systemd:${RESET}       $(${INSTALL_SYSTEMD} && echo "yes" || echo "no")"
echo -e "${CYAN}Auto-start:${RESET}    $(${START_AFTER_DEPLOY} && echo "yes" || echo "no")"
echo ""

# ======================================================================
# STEP 1: VALIDATE INPUT
# ======================================================================
log_step "Step 1/9: Validating input parameters"

# Validate instance name format
if ! [[ "${INSTANCE_NAME}" =~ ^URF[0-9]{3}$ ]]; then
    log_error "Invalid instance name format: ${INSTANCE_NAME}"
    log_info "Instance name must match pattern: URF[0-9]{3}"
    log_info "Examples: URF000, URF001, URF042, URF999"
    exit 1
fi
log_success "Instance name format valid"

# Validate version format
if ! [[ "${IMAGE_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
    log_warning "Version doesn't follow semantic versioning: ${IMAGE_VERSION}"
    log_info "Expected format: v1.2.3 or v1.2.3-suffix"
else
    log_success "Version format valid"
fi

# Extract instance number
INSTANCE_NUM="${INSTANCE_NAME:3}"
INSTANCE_NUM=$((10#${INSTANCE_NUM}))
log_info "Instance number: ${INSTANCE_NUM}"

INSTANCE_DIR="${INSTANCES_DIR}/${INSTANCE_NAME}"

echo ""

# ======================================================================
# STEP 2: CHECK FOR EXISTING INSTANCE
# ======================================================================
log_step "Step 2/9: Checking for existing instance"

if [[ -d "${INSTANCE_DIR}" ]]; then
    log_error "Instance already exists: ${INSTANCE_DIR}"
    log_info "Remove the existing instance or choose a different name"
    log_info "To remove: rm -rf ${INSTANCE_DIR}"
    exit 1
fi
log_success "Instance directory available: ${INSTANCE_DIR}"

# Create instances parent directory if needed
if [[ ! -d "${INSTANCES_DIR}" ]]; then
    log_info "Creating instances directory: ${INSTANCES_DIR}"
    mkdir -p "${INSTANCES_DIR}"
fi

echo ""

# ======================================================================
# STEP 3: CREATE DIRECTORY STRUCTURE
# ======================================================================
log_step "Step 3/9: Creating directory structure"

mkdir -p "${INSTANCE_DIR}"
mkdir -p "${INSTANCE_DIR}/config"
mkdir -p "${INSTANCE_DIR}/config/dashboard"
mkdir -p "${INSTANCE_DIR}/data"
mkdir -p "${INSTANCE_DIR}/data/logs"
mkdir -p "${INSTANCE_DIR}/data/audio"
mkdir -p "${INSTANCE_DIR}/data/dashboard"

log_success "Directory structure created"

echo ""

# ======================================================================
# STEP 4: CALCULATE PORT OFFSETS
# ======================================================================
log_step "Step 4/9: Calculating port assignments"

PORT_OFFSET=$((INSTANCE_NUM * 100))
log_info "Port offset: ${PORT_OFFSET}"

# Generate port assignments
"${SCRIPT_DIR}/calculate-ports.sh" "${INSTANCE_NAME}" > "${INSTANCE_DIR}/.ports.tmp"
log_success "Port assignments calculated"

echo ""

# ======================================================================
# STEP 5: GENERATE ENVIRONMENT FILE
# ======================================================================
log_step "Step 5/9: Generating environment configuration"

# Start with template
cp "${TEMPLATES_DIR}/.env.template" "${INSTANCE_DIR}/.env"

# Update critical variables
sed -i.bak "s|^INSTANCE_NAME=.*|INSTANCE_NAME=${INSTANCE_NAME}|" "${INSTANCE_DIR}/.env"
sed -i.bak "s|^INSTANCE_DIR=.*|INSTANCE_DIR=${INSTANCE_DIR}|" "${INSTANCE_DIR}/.env"
sed -i.bak "s|^IMAGE_VERSION=.*|IMAGE_VERSION=${IMAGE_VERSION}|" "${INSTANCE_DIR}/.env"
sed -i.bak "s|^REFLECTOR_CALLSIGN=.*|REFLECTOR_CALLSIGN=${INSTANCE_NAME}|" "${INSTANCE_DIR}/.env"

# Merge port assignments
cat "${INSTANCE_DIR}/.ports.tmp" | grep "^PORT_" >> "${INSTANCE_DIR}/.env.new"
grep -v "^PORT_" "${INSTANCE_DIR}/.env" >> "${INSTANCE_DIR}/.env.new"
mv "${INSTANCE_DIR}/.env.new" "${INSTANCE_DIR}/.env"

# Cleanup
rm -f "${INSTANCE_DIR}/.env.bak" "${INSTANCE_DIR}/.ports.tmp"

log_success "Environment file created: .env"

echo ""

# ======================================================================
# STEP 6: PROCESS CONFIGURATION TEMPLATES
# ======================================================================
log_step "Step 6/9: Processing configuration templates"

# Source environment for substitution
set +u
source "${INSTANCE_DIR}/.env"
set -u

# Function to perform variable substitution
substitute_vars() {
    local input_file="$1"
    local output_file="$2"
    
    # Use envsubst or manual replacement
    if command -v envsubst &> /dev/null; then
        envsubst < "${input_file}" > "${output_file}"
    else
        # Fallback: use eval with cat and heredoc
        eval "cat <<EOF
$(cat "${input_file}")
EOF
" > "${output_file}"
    fi
}

# Process docker-compose.yml
substitute_vars "${TEMPLATES_DIR}/docker-compose.prod.yml" "${INSTANCE_DIR}/docker-compose.yml"
log_success "Created: docker-compose.yml"

# Process urfd.ini
substitute_vars "${TEMPLATES_DIR}/configs/urfd.ini.template" "${INSTANCE_DIR}/config/urfd.ini"
log_success "Created: config/urfd.ini"

# Process tcd.ini
substitute_vars "${TEMPLATES_DIR}/configs/tcd.ini.template" "${INSTANCE_DIR}/config/tcd.ini"
log_success "Created: config/tcd.ini"

# Process dashboard config
substitute_vars "${TEMPLATES_DIR}/configs/dashboard.yaml.template" "${INSTANCE_DIR}/config/dashboard/config.yaml"
log_success "Created: config/dashboard/config.yaml"

# Create empty whitelist/blacklist/interlink files
touch "${INSTANCE_DIR}/config/urfd.whitelist"
touch "${INSTANCE_DIR}/config/urfd.blacklist"
touch "${INSTANCE_DIR}/config/urfd.interlink"
touch "${INSTANCE_DIR}/config/urfd.terminal"
log_success "Created: access control files"

echo ""

# ======================================================================
# STEP 7: VALIDATE DEPLOYMENT
# ======================================================================
if [[ "${SKIP_VALIDATION}" == "false" ]]; then
    log_step "Step 7/9: Validating deployment"
    
    if "${SCRIPT_DIR}/validate-instance.sh" "${INSTANCE_DIR}"; then
        log_success "Validation passed"
    else
        log_error "Validation failed"
        log_info "Review errors above and fix configuration"
        log_info "Instance directory: ${INSTANCE_DIR}"
        exit 1
    fi
else
    log_step "Step 7/9: Skipping validation (--skip-validation)"
    log_warning "Validation skipped - deployment may be incomplete"
fi

echo ""

# ======================================================================
# STEP 8: INSTALL SYSTEMD SERVICE (OPTIONAL)
# ======================================================================
if [[ "${INSTALL_SYSTEMD}" == "true" ]]; then
    log_step "Step 8/9: Installing systemd service"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "Systemd installation requires root privileges"
        log_info "Run with sudo or manually install service later"
        exit 1
    fi
    
    # Process systemd template
    SYSTEMD_SERVICE="/etc/systemd/system/urfd-instance@${INSTANCE_NAME}.service"
    substitute_vars "${TEMPLATES_DIR}/systemd/urfd-instance@.service" "${SYSTEMD_SERVICE}"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable service
    systemctl enable "urfd-instance@${INSTANCE_NAME}.service"
    
    log_success "Systemd service installed and enabled"
    log_info "Start: sudo systemctl start urfd-instance@${INSTANCE_NAME}"
    log_info "Stop:  sudo systemctl stop urfd-instance@${INSTANCE_NAME}"
    log_info "Status: sudo systemctl status urfd-instance@${INSTANCE_NAME}"
else
    log_step "Step 8/9: Skipping systemd installation"
    log_info "To install later, use: --systemd flag or manually copy template"
fi

echo ""

# ======================================================================
# STEP 9: START INSTANCE (OPTIONAL)
# ======================================================================
if [[ "${START_AFTER_DEPLOY}" == "true" ]]; then
    log_step "Step 9/9: Starting instance"
    
    cd "${INSTANCE_DIR}"
    docker compose up -d
    
    log_success "Instance started"
    log_info "Dashboard: http://localhost:${PORT_DASHBOARD_HTTP}"
    log_info "Logs: docker compose -f ${INSTANCE_DIR}/docker-compose.yml logs -f"
else
    log_step "Step 9/9: Instance deployed (not started)"
    log_info "To start: cd ${INSTANCE_DIR} && docker compose up -d"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}✓ Deployment Complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${CYAN}Instance:${RESET}         ${INSTANCE_NAME}"
echo -e "${CYAN}Directory:${RESET}        ${INSTANCE_DIR}"
echo -e "${CYAN}Dashboard URL:${RESET}    http://localhost:${PORT_DASHBOARD_HTTP}"
echo ""
echo -e "${BOLD}Next Steps:${RESET}"
echo "  1. Review and customize: ${INSTANCE_DIR}/.env"
echo "  2. Edit reflector settings: ${INSTANCE_DIR}/config/urfd.ini"
echo "  3. Start the instance: cd ${INSTANCE_DIR} && docker compose up -d"
echo "  4. View logs: docker compose logs -f"
echo ""
