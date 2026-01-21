#!/usr/bin/env bash
# Validate URFD production instance configuration
# Usage: validate-instance.sh <instance-dir>

set -euo pipefail

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Validation counters
ERRORS=0
WARNINGS=0

# Usage
usage() {
    cat <<EOF
${BOLD}URFD Instance Validator${RESET}

Validates URFD production instance configuration files and directory structure.

${BOLD}Usage:${RESET}
  $0 <instance-dir>

${BOLD}Example:${RESET}
  $0 /opt/urfd-production/instances/URF001

${BOLD}Validation Checks:${RESET}
  - Directory structure (config/, data/, etc.)
  - Required configuration files exist
  - Environment variables are set
  - Port assignments are valid
  - Docker Compose file is valid
  - No port conflicts with other instances
  - File permissions are correct

${BOLD}Exit Codes:${RESET}
  0 - All validations passed
  1 - Errors found (deployment will fail)
  2 - Warnings only (deployment may succeed but review recommended)
EOF
    exit 0
}

# Error logging
log_error() {
    echo -e "${RED}✗ ERROR:${RESET} $1"
    ERRORS=$((ERRORS + 1))
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${RESET} $1"
    WARNINGS=$((WARNINGS + 1))
}

log_success() {
    echo -e "${GREEN}✓${RESET} $1"
}

log_info() {
    echo -e "${CYAN}ℹ${RESET} $1"
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    usage
fi

INSTANCE_DIR="$1"

if [[ "${INSTANCE_DIR}" == "-h" ]] || [[ "${INSTANCE_DIR}" == "--help" ]]; then
    usage
fi

echo -e "${BOLD}URFD Instance Validator${RESET}"
echo ""
echo -e "${CYAN}Instance directory:${RESET} ${INSTANCE_DIR}"
echo ""

# ======================================================================
# DIRECTORY STRUCTURE VALIDATION
# ======================================================================
echo -e "${BOLD}[1/8] Validating directory structure...${RESET}"

if [[ ! -d "${INSTANCE_DIR}" ]]; then
    log_error "Instance directory does not exist: ${INSTANCE_DIR}"
else
    log_success "Instance directory exists"
fi

# Check required directories
REQUIRED_DIRS=(
    "config"
    "config/dashboard"
    "data"
    "data/logs"
    "data/audio"
    "data/dashboard"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ ! -d "${INSTANCE_DIR}/${dir}" ]]; then
        log_error "Required directory missing: ${dir}"
    else
        log_success "Directory exists: ${dir}"
    fi
done

echo ""

# ======================================================================
# CONFIGURATION FILES VALIDATION
# ======================================================================
echo -e "${BOLD}[2/8] Validating configuration files...${RESET}"

REQUIRED_FILES=(
    ".env"
    "docker-compose.yml"
    "config/urfd.ini"
    "config/tcd.ini"
    "config/dashboard/config.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${INSTANCE_DIR}/${file}" ]]; then
        log_error "Required file missing: ${file}"
    else
        log_success "File exists: ${file}"
    fi
done

echo ""

# ======================================================================
# ENVIRONMENT VARIABLES VALIDATION
# ======================================================================
echo -e "${BOLD}[3/8] Validating environment variables...${RESET}"

if [[ ! -f "${INSTANCE_DIR}/.env" ]]; then
    log_error "Cannot validate environment variables - .env file missing"
else
    # Source the .env file
    set +u  # Allow undefined variables temporarily
    source "${INSTANCE_DIR}/.env"
    set -u
    
    # Check critical variables
    CRITICAL_VARS=(
        "INSTANCE_NAME"
        "INSTANCE_DIR"
        "IMAGE_VERSION"
        "REFLECTOR_CALLSIGN"
        "REFLECTOR_SYSOP_EMAIL"
        "PORT_DASHBOARD_HTTP"
    )
    
    for var in "${CRITICAL_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Critical environment variable not set: ${var}"
        else
            log_success "Variable set: ${var}=${!var}"
        fi
    done
    
    # Validate instance name format
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        if ! [[ "${INSTANCE_NAME}" =~ ^URF[0-9]{3}$ ]]; then
            log_error "Invalid INSTANCE_NAME format: ${INSTANCE_NAME} (must match URF[0-9]{3})"
        fi
    fi
    
    # Validate version format
    if [[ -n "${IMAGE_VERSION:-}" ]]; then
        if ! [[ "${IMAGE_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
            log_warning "IMAGE_VERSION doesn't follow semantic versioning: ${IMAGE_VERSION}"
        fi
    fi
    
    # Validate email format
    if [[ -n "${REFLECTOR_SYSOP_EMAIL:-}" ]]; then
        if ! [[ "${REFLECTOR_SYSOP_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_warning "REFLECTOR_SYSOP_EMAIL may be invalid: ${REFLECTOR_SYSOP_EMAIL}"
        fi
    fi
fi

echo ""

# ======================================================================
# PORT VALIDATION
# ======================================================================
echo -e "${BOLD}[4/8] Validating port assignments...${RESET}"

if [[ -f "${INSTANCE_DIR}/.env" ]]; then
    source "${INSTANCE_DIR}/.env"
    
    # Check port range validity (1-65535)
    PORT_VARS=(
        "PORT_DEXTRA" "PORT_DPLUS" "PORT_DCS" "PORT_DMRPLUS" "PORT_MMDVM"
        "PORT_M17" "PORT_YSF" "PORT_P25" "PORT_NXDN" "PORT_URF"
        "PORT_TRANSCODER" "PORT_G3" "PORT_NNG_DASHBOARD" "PORT_NNG_VOICE"
        "PORT_NNG_CONTROL" "PORT_DASHBOARD_HTTP"
    )
    
    for port_var in "${PORT_VARS[@]}"; do
        port_value="${!port_var:-}"
        if [[ -n "${port_value}" ]]; then
            if [[ "${port_value}" -lt 1 ]] || [[ "${port_value}" -gt 65535 ]]; then
                log_error "Port out of range (1-65535): ${port_var}=${port_value}"
            else
                log_success "Port valid: ${port_var}=${port_value}"
            fi
        fi
    done
fi

echo ""

# ======================================================================
# DOCKER COMPOSE VALIDATION
# ======================================================================
echo -e "${BOLD}[5/8] Validating Docker Compose file...${RESET}"

if [[ ! -f "${INSTANCE_DIR}/docker-compose.yml" ]]; then
    log_error "Cannot validate Docker Compose - file missing"
else
    # Validate syntax using docker compose config
    if command -v docker &> /dev/null; then
        if docker compose -f "${INSTANCE_DIR}/docker-compose.yml" config > /dev/null 2>&1; then
            log_success "Docker Compose syntax valid"
        else
            log_error "Docker Compose syntax invalid (run: docker compose -f ${INSTANCE_DIR}/docker-compose.yml config)"
        fi
    else
        log_warning "Docker not available - cannot validate Compose file syntax"
    fi
fi

echo ""

# ======================================================================
# PORT CONFLICT DETECTION
# ======================================================================
echo -e "${BOLD}[6/8] Checking for port conflicts...${RESET}"

INSTANCES_DIR=$(dirname "${INSTANCE_DIR}")

if [[ -f "${INSTANCE_DIR}/.env" ]]; then
    source "${INSTANCE_DIR}/.env"
    CURRENT_INSTANCE="${INSTANCE_NAME:-unknown}"
    
    # Check against other instances
    CONFLICTS=0
    for other_instance in "${INSTANCES_DIR}"/*; do
        if [[ -d "${other_instance}" ]] && [[ "${other_instance}" != "${INSTANCE_DIR}" ]]; then
            if [[ -f "${other_instance}/.env" ]]; then
                OTHER_NAME=$(grep "^INSTANCE_NAME=" "${other_instance}/.env" | cut -d= -f2)
                OTHER_HTTP_PORT=$(grep "^PORT_DASHBOARD_HTTP=" "${other_instance}/.env" | cut -d= -f2)
                
                if [[ "${OTHER_HTTP_PORT}" == "${PORT_DASHBOARD_HTTP:-}" ]]; then
                    log_error "Port conflict with ${OTHER_NAME}: PORT_DASHBOARD_HTTP=${PORT_DASHBOARD_HTTP}"
                    CONFLICTS=$((CONFLICTS + 1))
                fi
            fi
        fi
    done
    
    if [[ ${CONFLICTS} -eq 0 ]]; then
        log_success "No port conflicts detected"
    fi
else
    log_warning "Cannot check port conflicts - .env file missing"
fi

echo ""

# ======================================================================
# FILE PERMISSIONS VALIDATION
# ======================================================================
echo -e "${BOLD}[7/8] Validating file permissions...${RESET}"

# Check if config files are readable
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${INSTANCE_DIR}/${file}" ]]; then
        if [[ ! -r "${INSTANCE_DIR}/${file}" ]]; then
            log_error "File not readable: ${file}"
        fi
    fi
done

# Check if data directories are writable
WRITABLE_DIRS=("data" "data/logs" "data/audio" "data/dashboard")
for dir in "${WRITABLE_DIRS[@]}"; do
    if [[ -d "${INSTANCE_DIR}/${dir}" ]]; then
        if [[ ! -w "${INSTANCE_DIR}/${dir}" ]]; then
            log_error "Directory not writable: ${dir}"
        fi
    fi
done

log_success "File permissions check complete"

echo ""

# ======================================================================
# DOCKER IMAGE AVAILABILITY
# ======================================================================
echo -e "${BOLD}[8/8] Checking Docker image availability...${RESET}"

if [[ -f "${INSTANCE_DIR}/.env" ]]; then
    source "${INSTANCE_DIR}/.env"
    
    if command -v docker &> /dev/null; then
        IMAGES=("urfd-urfd" "urfd-tcd" "urfd-dashboard")
        
        for image in "${IMAGES[@]}"; do
            full_image="${image}:${IMAGE_VERSION}"
            if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${full_image}\$"; then
                log_success "Image available: ${full_image}"
            else
                log_error "Image not found: ${full_image} (build it first with build-images.sh)"
            fi
        done
    else
        log_warning "Docker not available - cannot check image availability"
    fi
else
    log_warning "Cannot check images - .env file missing"
fi

echo ""

# ======================================================================
# VALIDATION SUMMARY
# ======================================================================
echo -e "${BOLD}Validation Summary${RESET}"
echo -e "Errors:   ${RED}${ERRORS}${RESET}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${RESET}"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    echo -e "${RED}✗ Validation FAILED - ${ERRORS} error(s) must be fixed before deployment${RESET}"
    exit 1
elif [[ ${WARNINGS} -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Validation passed with ${WARNINGS} warning(s) - review recommended${RESET}"
    exit 2
else
    echo -e "${GREEN}✓ All validations PASSED${RESET}"
    exit 0
fi
