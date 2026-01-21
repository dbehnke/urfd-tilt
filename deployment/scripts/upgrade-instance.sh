#!/usr/bin/env bash
# Upgrade URFD production instance to a new version
# Usage: upgrade-instance.sh <instance-name> <new-version> [options]

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
INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

# Default options
CREATE_BACKUP=true
AUTO_RESTART=false
SKIP_VALIDATION=false

# Usage
usage() {
    cat <<EOF
${BOLD}URFD Instance Upgrade${RESET}

Upgrade an existing URFD production instance to a new version.

${BOLD}Usage:${RESET}
  $0 <instance-name> <new-version> [OPTIONS]

${BOLD}Arguments:${RESET}
  instance-name    Instance to upgrade (e.g., URF001)
  new-version      Target version tag (e.g., v1.1.0, v2.0.0-rc1)

${BOLD}Options:${RESET}
  --no-backup          Skip configuration backup (not recommended)
  --auto-restart       Automatically restart instance after upgrade
  --skip-validation    Skip validation after upgrade (not recommended)
  -h, --help           Show this help message

${BOLD}Examples:${RESET}
  $0 URF001 v1.1.0
  $0 URF042 v2.0.0-rc1 --auto-restart
  $0 URF999 v1.8.5 --no-backup --skip-validation

${BOLD}What This Script Does:${RESET}
  1. Validates current instance and new version
  2. Creates backup of current configuration
  3. Checks if new Docker images are available
  4. Updates .env file with new version
  5. Regenerates configuration files (preserving customizations)
  6. Validates the upgraded configuration
  7. Optionally restarts the instance with new version

${BOLD}Safety Features:${RESET}
  - Automatic configuration backup before upgrade
  - Rollback instructions provided if upgrade fails
  - Validation ensures upgrade is safe
  - Instance keeps running during upgrade process
  - Manual restart required by default (use --auto-restart to override)

${BOLD}Backup Location:${RESET}
  Backups are stored in: <instance-dir>/.backups/<timestamp>/

${BOLD}Important Notes:${RESET}
  - Docker images for the new version must be built beforehand
  - Custom configuration changes in .env are preserved
  - Template-generated configs are regenerated (manual edits lost)
  - Review the upgrade before restarting the instance

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
NEW_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        --auto-restart)
            AUTO_RESTART=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "${INSTANCE_NAME}" ]]; then
                INSTANCE_NAME="$1"
            elif [[ -z "${NEW_VERSION}" ]]; then
                NEW_VERSION="$1"
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
if [[ -z "${INSTANCE_NAME}" ]] || [[ -z "${NEW_VERSION}" ]]; then
    log_error "Missing required arguments"
    echo ""
    echo "Usage: $0 <instance-name> <new-version> [OPTIONS]"
    echo "Use --help for more information"
    exit 1
fi

INSTANCE_DIR="${INSTANCES_DIR}/${INSTANCE_NAME}"

echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}           URFD Instance Upgrade${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""

# ======================================================================
# STEP 1: VALIDATE INSTANCE AND VERSION
# ======================================================================
log_step "Step 1/7: Validating instance and version"

# Check instance exists
if [[ ! -d "${INSTANCE_DIR}" ]]; then
    log_error "Instance not found: ${INSTANCE_NAME}"
    log_info "Instance directory: ${INSTANCE_DIR}"
    exit 1
fi
log_success "Instance exists: ${INSTANCE_NAME}"

# Load current configuration
if [[ ! -f "${INSTANCE_DIR}/.env" ]]; then
    log_error ".env file not found in instance"
    exit 1
fi

source "${INSTANCE_DIR}/.env"
CURRENT_VERSION="${IMAGE_VERSION}"

echo ""
echo -e "${CYAN}Current version:${RESET} ${CURRENT_VERSION}"
echo -e "${CYAN}Target version:${RESET}  ${NEW_VERSION}"
echo ""

# Validate new version format
if ! [[ "${NEW_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
    log_warning "Version doesn't follow semantic versioning: ${NEW_VERSION}"
fi

# Check if already on target version
if [[ "${CURRENT_VERSION}" == "${NEW_VERSION}" ]]; then
    log_warning "Instance is already on version ${NEW_VERSION}"
    read -p "Continue anyway? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Upgrade cancelled"
        exit 0
    fi
fi

log_success "Version validation complete"

echo ""

# ======================================================================
# STEP 2: CHECK DOCKER IMAGES
# ======================================================================
log_step "Step 2/7: Checking Docker image availability"

if command -v docker &> /dev/null; then
    IMAGES=("urfd-urfd" "urfd-tcd" "urfd-dashboard")
    MISSING_IMAGES=()
    
    for image in "${IMAGES[@]}"; do
        full_image="${image}:${NEW_VERSION}"
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${full_image}\$"; then
            log_success "Image available: ${full_image}"
        else
            log_error "Image not found: ${full_image}"
            MISSING_IMAGES+=("${full_image}")
        fi
    done
    
    if [[ ${#MISSING_IMAGES[@]} -gt 0 ]]; then
        log_error "Missing Docker images for version ${NEW_VERSION}"
        log_info "Build images first: cd deployment/build && ./build-images.sh ${NEW_VERSION}"
        exit 1
    fi
else
    log_warning "Docker not available - cannot verify images"
fi

echo ""

# ======================================================================
# STEP 3: CREATE BACKUP
# ======================================================================
if [[ "${CREATE_BACKUP}" == "true" ]]; then
    log_step "Step 3/7: Creating configuration backup"
    
    BACKUP_DIR="${INSTANCE_DIR}/.backups/$(date +%Y%m%d-%H%M%S)-v${CURRENT_VERSION}"
    mkdir -p "${BACKUP_DIR}"
    
    # Backup configuration files
    cp -r "${INSTANCE_DIR}/.env" "${BACKUP_DIR}/"
    cp -r "${INSTANCE_DIR}/docker-compose.yml" "${BACKUP_DIR}/"
    cp -r "${INSTANCE_DIR}/config" "${BACKUP_DIR}/"
    
    log_success "Backup created: ${BACKUP_DIR}"
    log_info "Rollback: cp -r ${BACKUP_DIR}/* ${INSTANCE_DIR}/"
else
    log_step "Step 3/7: Skipping backup (--no-backup)"
    log_warning "No backup created - cannot rollback if upgrade fails"
    BACKUP_DIR="(none)"
fi

echo ""

# ======================================================================
# STEP 4: UPDATE VERSION IN .ENV
# ======================================================================
log_step "Step 4/7: Updating version configuration"

# Update IMAGE_VERSION in .env
sed -i.upgrade-bak "s|^IMAGE_VERSION=.*|IMAGE_VERSION=${NEW_VERSION}|" "${INSTANCE_DIR}/.env"
rm -f "${INSTANCE_DIR}/.env.upgrade-bak"

log_success "Updated .env: IMAGE_VERSION=${NEW_VERSION}"

echo ""

# ======================================================================
# STEP 5: REGENERATE CONFIGURATION FILES
# ======================================================================
log_step "Step 5/7: Regenerating configuration files"

# Reload environment with new version
source "${INSTANCE_DIR}/.env"

TEMPLATES_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"

# Function to perform variable substitution
substitute_vars() {
    local input_file="$1"
    local output_file="$2"
    
    if command -v envsubst &> /dev/null; then
        envsubst < "${input_file}" > "${output_file}"
    else
        eval "cat <<EOF
$(cat "${input_file}")
EOF
" > "${output_file}"
    fi
}

# Regenerate docker-compose.yml
substitute_vars "${TEMPLATES_DIR}/docker-compose.prod.yml" "${INSTANCE_DIR}/docker-compose.yml"
log_success "Updated: docker-compose.yml"

# Regenerate config files
substitute_vars "${TEMPLATES_DIR}/configs/urfd.ini.template" "${INSTANCE_DIR}/config/urfd.ini"
log_success "Updated: config/urfd.ini"

substitute_vars "${TEMPLATES_DIR}/configs/tcd.ini.template" "${INSTANCE_DIR}/config/tcd.ini"
log_success "Updated: config/tcd.ini"

substitute_vars "${TEMPLATES_DIR}/configs/dashboard.yaml.template" "${INSTANCE_DIR}/config/dashboard/config.yaml"
log_success "Updated: config/dashboard/config.yaml"

log_warning "Template-generated configs have been regenerated"
log_info "Manual edits to INI/YAML files are lost (not .env customizations)"
log_info "Restore from backup if needed: ${BACKUP_DIR}"

echo ""

# ======================================================================
# STEP 6: VALIDATE UPGRADE
# ======================================================================
if [[ "${SKIP_VALIDATION}" == "false" ]]; then
    log_step "Step 6/7: Validating upgraded configuration"
    
    if "${SCRIPT_DIR}/validate-instance.sh" "${INSTANCE_DIR}"; then
        log_success "Validation passed"
    else
        EXIT_CODE=$?
        if [[ ${EXIT_CODE} -eq 2 ]]; then
            log_warning "Validation passed with warnings"
        else
            log_error "Validation failed"
            log_info "Review errors above"
            
            if [[ "${CREATE_BACKUP}" == "true" ]]; then
                log_info "Rollback: cp -r ${BACKUP_DIR}/* ${INSTANCE_DIR}/"
            fi
            exit 1
        fi
    fi
else
    log_step "Step 6/7: Skipping validation (--skip-validation)"
    log_warning "Configuration not validated - upgrade may fail"
fi

echo ""

# ======================================================================
# STEP 7: RESTART INSTANCE
# ======================================================================
if [[ "${AUTO_RESTART}" == "true" ]]; then
    log_step "Step 7/7: Restarting instance with new version"
    
    cd "${INSTANCE_DIR}"
    docker compose pull
    docker compose up -d
    
    log_success "Instance restarted with version ${NEW_VERSION}"
    
    # Show status
    echo ""
    docker compose ps
else
    log_step "Step 7/7: Upgrade complete (not restarted)"
    log_info "Instance is still running old version: ${CURRENT_VERSION}"
    log_info "Restart to apply upgrade: cd ${INSTANCE_DIR} && docker compose up -d"
    log_info "Or use manage script: ${SCRIPT_DIR}/manage-instance.sh ${INSTANCE_NAME} restart"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}✓ Upgrade Complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${CYAN}Instance:${RESET}         ${INSTANCE_NAME}"
echo -e "${CYAN}Old Version:${RESET}      ${CURRENT_VERSION}"
echo -e "${CYAN}New Version:${RESET}      ${NEW_VERSION}"
echo -e "${CYAN}Backup:${RESET}           ${BACKUP_DIR}"
echo ""

if [[ "${AUTO_RESTART}" == "false" ]]; then
    echo -e "${BOLD}Next Steps:${RESET}"
    echo "  1. Review the upgrade: ${INSTANCE_DIR}"
    echo "  2. Restart the instance: cd ${INSTANCE_DIR} && docker compose up -d"
    echo "  3. Verify functionality: ${SCRIPT_DIR}/manage-instance.sh ${INSTANCE_NAME} status"
    echo "  4. Check logs: ${SCRIPT_DIR}/manage-instance.sh ${INSTANCE_NAME} logs"
    echo ""
    echo -e "${BOLD}Rollback (if needed):${RESET}"
    echo "  cp -r ${BACKUP_DIR}/* ${INSTANCE_DIR}/"
    echo "  cd ${INSTANCE_DIR} && docker compose up -d"
    echo ""
else
    echo -e "${BOLD}Post-Upgrade:${RESET}"
    echo "  1. Verify functionality: ${SCRIPT_DIR}/manage-instance.sh ${INSTANCE_NAME} status"
    echo "  2. Check logs: ${SCRIPT_DIR}/manage-instance.sh ${INSTANCE_NAME} logs"
    echo ""
    
    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        echo -e "${BOLD}Rollback (if needed):${RESET}"
        echo "  cp -r ${BACKUP_DIR}/* ${INSTANCE_DIR}/"
        echo "  cd ${INSTANCE_DIR} && docker compose restart"
        echo ""
    fi
fi
