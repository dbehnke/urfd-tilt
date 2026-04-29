#!/usr/bin/env bash
# Re-render generated production files from an instance .env file.
# Usage: render-instance-config.sh <instance-name|instance-dir> [--apply] [--skip-validation] [--instances-dir PATH]

set -euo pipefail

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

APPLY=false
SKIP_VALIDATION=false
INSTANCE_ARG=""

usage() {
    cat <<EOF
${BOLD}URFD Instance Config Renderer${RESET}

Re-renders generated production files after editing an instance .env file.

${BOLD}Usage:${RESET}
  $0 <instance-name|instance-dir> [OPTIONS]

${BOLD}Options:${RESET}
  --apply                 Run docker compose up -d after rendering
  --skip-validation       Skip validation after rendering
  --instances-dir PATH    Custom instances directory (default: ${INSTANCES_DIR})
  -h, --help              Show this help message

${BOLD}Examples:${RESET}
  $0 URF000
  $0 URF000 --apply
  $0 /opt/urfd-production/instances/URF000 --skip-validation

${BOLD}Generated files:${RESET}
  docker-compose.yml
  config/urfd.ini
  config/tcd.ini
  config/dashboard/config.yaml

Edit .env first, then run this script to apply those values to generated files.
EOF
    exit 0
}

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --apply)
            APPLY=true
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
            if [[ -z "${INSTANCE_ARG}" ]]; then
                INSTANCE_ARG="$1"
            else
                log_error "Too many arguments"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "${INSTANCE_ARG}" ]]; then
    log_error "Missing instance name or directory"
    echo "Usage: $0 <instance-name|instance-dir> [OPTIONS]"
    exit 1
fi

if [[ -d "${INSTANCE_ARG}" ]]; then
    TARGET_INSTANCE_DIR="$(cd "${INSTANCE_ARG}" && pwd)"
    INSTANCE_NAME="$(basename "${TARGET_INSTANCE_DIR}")"
else
    INSTANCE_NAME="${INSTANCE_ARG}"
    TARGET_INSTANCE_DIR="${INSTANCES_DIR}/${INSTANCE_NAME}"
fi

if [[ ! -d "${TARGET_INSTANCE_DIR}" ]]; then
    log_error "Instance directory not found: ${TARGET_INSTANCE_DIR}"
    exit 1
fi

if [[ ! -f "${TARGET_INSTANCE_DIR}/.env" ]]; then
    log_error "Missing instance environment file: ${TARGET_INSTANCE_DIR}/.env"
    exit 1
fi

log_step "Loading environment for ${INSTANCE_NAME}"
set +u
set -a
source "${TARGET_INSTANCE_DIR}/.env"
INSTANCE_DIR="${TARGET_INSTANCE_DIR}"
set +a
set -u

mkdir -p \
    "${TARGET_INSTANCE_DIR}/config" \
    "${TARGET_INSTANCE_DIR}/config/dashboard" \
    "${TARGET_INSTANCE_DIR}/data" \
    "${TARGET_INSTANCE_DIR}/data/logs" \
    "${TARGET_INSTANCE_DIR}/data/audio" \
    "${TARGET_INSTANCE_DIR}/data/dashboard"

substitute_vars() {
    local input_file="$1"
    local output_file="$2"

    if command -v envsubst >/dev/null 2>&1; then
        envsubst < "${input_file}" > "${output_file}"
    else
        eval "cat <<EOF
$(cat "${input_file}")
EOF
" > "${output_file}"
    fi
}

log_step "Rendering generated files"
substitute_vars "${TEMPLATES_DIR}/docker-compose.prod.yml" "${TARGET_INSTANCE_DIR}/docker-compose.yml"
log_success "Rendered docker-compose.yml"

substitute_vars "${TEMPLATES_DIR}/configs/urfd.ini.template" "${TARGET_INSTANCE_DIR}/config/urfd.ini"
log_success "Rendered config/urfd.ini"

substitute_vars "${TEMPLATES_DIR}/configs/tcd.ini.template" "${TARGET_INSTANCE_DIR}/config/tcd.ini"
log_success "Rendered config/tcd.ini"

substitute_vars "${TEMPLATES_DIR}/configs/dashboard.yaml.template" "${TARGET_INSTANCE_DIR}/config/dashboard/config.yaml"
log_success "Rendered config/dashboard/config.yaml"

touch \
    "${TARGET_INSTANCE_DIR}/config/urfd.whitelist" \
    "${TARGET_INSTANCE_DIR}/config/urfd.blacklist" \
    "${TARGET_INSTANCE_DIR}/config/urfd.interlink" \
    "${TARGET_INSTANCE_DIR}/config/urfd.terminal"

if [[ "${SKIP_VALIDATION}" == "false" ]]; then
    log_step "Validating rendered instance"
    if "${SCRIPT_DIR}/validate-instance.sh" "${TARGET_INSTANCE_DIR}"; then
        log_success "Validation passed"
    else
        log_error "Validation failed"
        exit 1
    fi
else
    log_warning "Validation skipped"
fi

if [[ "${APPLY}" == "true" ]]; then
    log_step "Applying rendered configuration"
    cd "${TARGET_INSTANCE_DIR}"
    docker compose up -d
    log_success "Instance applied"
else
    log_info "Rendered only. Run with --apply to execute docker compose up -d."
fi
