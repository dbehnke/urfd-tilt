#!/usr/bin/env bash
# Manage URFD production instance lifecycle
# Usage: manage-instance.sh <instance-name> <command>

set -euo pipefail

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

# Usage
usage() {
    cat <<EOF
${BOLD}URFD Instance Management${RESET}

Manage lifecycle of URFD production instances.

${BOLD}Usage:${RESET}
  $0 <instance-name> <command>

${BOLD}Commands:${RESET}
  start          Start the instance
  stop           Stop the instance
  restart        Restart the instance
  status         Show instance status
  logs           Follow instance logs (Ctrl+C to exit)
  logs-tail      Show last 100 log lines
  ps             Show running containers
  exec           Execute command in urfd container
  shell          Open bash shell in urfd container
  pull           Pull latest images (without restart)
  validate       Validate instance configuration
  info           Show instance information

${BOLD}Examples:${RESET}
  $0 URF001 start
  $0 URF001 status
  $0 URF001 logs
  $0 URF001 exec ps aux
  $0 URF001 shell

${BOLD}Systemd Integration:${RESET}
  If systemd service is installed, use systemctl instead:
    sudo systemctl start urfd-instance@URF001
    sudo systemctl stop urfd-instance@URF001
    sudo systemctl status urfd-instance@URF001

${BOLD}Environment Variables:${RESET}
  URFD_INSTANCES_DIR    Custom instances directory (default: /opt/urfd-production/instances)

EOF
    exit 0
}

# Logging functions
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
    echo -e "${CYAN}ℹ${RESET} $1"
}

# Parse arguments
if [[ $# -lt 1 ]]; then
    usage
fi

INSTANCE_NAME="$1"

if [[ "${INSTANCE_NAME}" == "-h" ]] || [[ "${INSTANCE_NAME}" == "--help" ]]; then
    usage
fi

if [[ $# -lt 2 ]]; then
    log_error "Missing command"
    echo ""
    echo "Usage: $0 <instance-name> <command>"
    echo "Use --help for available commands"
    exit 1
fi

COMMAND="$2"
shift 2  # Remove instance name and command, leaving additional args

INSTANCE_DIR="${INSTANCES_DIR}/${INSTANCE_NAME}"
COMPOSE_FILE="${INSTANCE_DIR}/docker-compose.yml"

# Validate instance exists
if [[ ! -d "${INSTANCE_DIR}" ]]; then
    log_error "Instance not found: ${INSTANCE_NAME}"
    log_info "Instance directory: ${INSTANCE_DIR}"
    log_info "Available instances:"
    if [[ -d "${INSTANCES_DIR}" ]]; then
        ls -1 "${INSTANCES_DIR}" 2>/dev/null || echo "  (none)"
    else
        echo "  (instances directory not found)"
    fi
    exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_error "Docker Compose file not found: ${COMPOSE_FILE}"
    log_info "Instance may be corrupted or incomplete"
    exit 1
fi

# Change to instance directory
cd "${INSTANCE_DIR}"

# Execute command
case "${COMMAND}" in
    start)
        log_info "Starting instance: ${INSTANCE_NAME}"
        docker compose up -d
        log_success "Instance started"
        
        # Show status after starting
        echo ""
        docker compose ps
        
        # Show dashboard URL if available
        if [[ -f ".env" ]]; then
            source .env
            if [[ -n "${PORT_DASHBOARD_HTTP:-}" ]]; then
                echo ""
                log_info "Dashboard: http://localhost:${PORT_DASHBOARD_HTTP}"
            fi
        fi
        ;;
    
    stop)
        log_info "Stopping instance: ${INSTANCE_NAME}"
        docker compose down
        log_success "Instance stopped"
        ;;
    
    restart)
        log_info "Restarting instance: ${INSTANCE_NAME}"
        docker compose restart
        log_success "Instance restarted"
        
        # Show status after restarting
        echo ""
        docker compose ps
        ;;
    
    status)
        echo -e "${BOLD}Instance: ${INSTANCE_NAME}${RESET}"
        echo ""
        
        # Show running containers
        docker compose ps
        
        # Show resource usage if containers are running
        if docker compose ps --quiet | grep -q .; then
            echo ""
            echo -e "${BOLD}Resource Usage:${RESET}"
            docker stats --no-stream $(docker compose ps --quiet)
        fi
        
        # Show instance info
        if [[ -f ".env" ]]; then
            source .env
            echo ""
            echo -e "${BOLD}Configuration:${RESET}"
            echo -e "  Version:   ${IMAGE_VERSION:-unknown}"
            echo -e "  Dashboard: http://localhost:${PORT_DASHBOARD_HTTP:-unknown}"
            echo -e "  Callsign:  ${REFLECTOR_CALLSIGN:-unknown}"
        fi
        ;;
    
    logs)
        log_info "Following logs for: ${INSTANCE_NAME} (Ctrl+C to exit)"
        echo ""
        docker compose logs -f "$@"
        ;;
    
    logs-tail)
        log_info "Last 100 lines of logs for: ${INSTANCE_NAME}"
        echo ""
        docker compose logs --tail=100 "$@"
        ;;
    
    ps)
        docker compose ps
        ;;
    
    exec)
        if [[ $# -eq 0 ]]; then
            log_error "Missing command to execute"
            echo "Usage: $0 ${INSTANCE_NAME} exec <command>"
            exit 1
        fi
        
        docker compose exec urfd "$@"
        ;;
    
    shell)
        log_info "Opening shell in urfd container (type 'exit' to leave)"
        docker compose exec urfd /bin/bash
        ;;
    
    pull)
        log_info "Pulling latest images for: ${INSTANCE_NAME}"
        docker compose pull
        log_success "Images updated"
        log_warning "Restart instance to use new images: $0 ${INSTANCE_NAME} restart"
        ;;
    
    validate)
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        if [[ -f "${SCRIPT_DIR}/validate-instance.sh" ]]; then
            "${SCRIPT_DIR}/validate-instance.sh" "${INSTANCE_DIR}"
        else
            log_error "Validation script not found: ${SCRIPT_DIR}/validate-instance.sh"
            exit 1
        fi
        ;;
    
    info)
        echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
        echo -e "${BOLD}         URFD Instance Information${RESET}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
        echo ""
        echo -e "${CYAN}Instance Name:${RESET}     ${INSTANCE_NAME}"
        echo -e "${CYAN}Instance Directory:${RESET} ${INSTANCE_DIR}"
        echo ""
        
        if [[ -f ".env" ]]; then
            source .env
            
            echo -e "${BOLD}Configuration:${RESET}"
            echo -e "  Image Version:    ${IMAGE_VERSION:-unknown}"
            echo -e "  Reflector:        ${REFLECTOR_CALLSIGN:-unknown}"
            echo -e "  Sysop:            ${REFLECTOR_SYSOP_EMAIL:-unknown}"
            echo -e "  Country:          ${REFLECTOR_COUNTRY:-unknown}"
            echo -e "  Modules:          ${REFLECTOR_MODULES:-unknown}"
            echo ""
            
            echo -e "${BOLD}Network Ports:${RESET}"
            echo -e "  Dashboard HTTP:   ${PORT_DASHBOARD_HTTP:-unknown}"
            echo -e "  DExtra (UDP):     ${PORT_DEXTRA:-unknown}"
            echo -e "  DPlus (UDP):      ${PORT_DPLUS:-unknown}"
            echo -e "  DMRPlus (UDP):    ${PORT_DMRPLUS:-unknown}"
            echo -e "  M17 (UDP):        ${PORT_M17:-unknown}"
            echo -e "  P25 (UDP):        ${PORT_P25:-unknown}"
            echo ""
            
            echo -e "${BOLD}URLs:${RESET}"
            echo -e "  Dashboard:        http://localhost:${PORT_DASHBOARD_HTTP}"
            echo -e "  Dashboard URL:    ${REFLECTOR_DASHBOARD_URL:-unknown}"
            echo ""
        else
            log_warning ".env file not found"
        fi
        
        echo -e "${BOLD}Container Status:${RESET}"
        docker compose ps
        echo ""
        
        echo -e "${BOLD}Disk Usage:${RESET}"
        du -sh "${INSTANCE_DIR}"
        du -sh "${INSTANCE_DIR}/data"/* 2>/dev/null || echo "  (no data directories)"
        echo ""
        
        # Check if systemd service exists
        if [[ -f "/etc/systemd/system/urfd-instance@${INSTANCE_NAME}.service" ]]; then
            echo -e "${BOLD}Systemd Service:${RESET}"
            echo -e "  Status: $(systemctl is-enabled urfd-instance@${INSTANCE_NAME} 2>/dev/null || echo 'not enabled')"
            echo ""
        fi
        ;;
    
    *)
        log_error "Unknown command: ${COMMAND}"
        echo ""
        echo "Available commands:"
        echo "  start, stop, restart, status, logs, logs-tail, ps,"
        echo "  exec, shell, pull, validate, info"
        echo ""
        echo "Use --help for more information"
        exit 1
        ;;
esac
