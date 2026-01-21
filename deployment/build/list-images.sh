#!/bin/bash
# List available URFD production Docker images

set -euo pipefail

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_VERSIONS_FILE="${SCRIPT_DIR}/.image-versions"
INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

# Image names
IMAGES=(
    "urfd-common"
    "imbe-lib"
    "md380-lib"
    "urfd"
    "tcd"
    "dashboard"
    "allstar-nexus"
)

echo -e "${BOLD}URFD Production Images${RESET}"
echo ""

# Read built versions from .image-versions file
if [[ -f "${IMAGE_VERSIONS_FILE}" ]]; then
    echo -e "${CYAN}Built versions (from .image-versions):${RESET}"
    while IFS= read -r line; do
        # Parse: version|timestamp|component1,component2,...
        IFS='|' read -r version timestamp components <<< "$line"
        echo -e "  ${GREEN}${version}${RESET} - built $(date -r "${timestamp}" '+%Y-%m-%d %H:%M:%S')"
        echo -e "    ${GRAY}components: ${components}${RESET}"
    done < "${IMAGE_VERSIONS_FILE}"
    echo ""
else
    echo -e "${YELLOW}No .image-versions file found - no builds recorded yet${RESET}"
    echo ""
fi

# Query Docker for available images
echo -e "${CYAN}Available Docker images:${RESET}"
echo ""

for image in "${IMAGES[@]}"; do
    echo -e "${BOLD}${image}:${RESET}"
    
    # Get all tags for this image
    if tags=$(docker images --format "{{.Tag}}" "urfd-${image}" 2>/dev/null | grep -v '<none>' | sort -V -r); then
        if [[ -n "${tags}" ]]; then
            echo "${tags}" | while IFS= read -r tag; do
                # Get image creation date
                created=$(docker images --format "{{.CreatedAt}}" "urfd-${image}:${tag}" 2>/dev/null | head -n1)
                
                # Check if this is the latest tag
                latest_marker=""
                if [[ "${tag}" == "latest" ]]; then
                    latest_marker=" ${YELLOW}[latest]${RESET}"
                fi
                
                # Get image size
                size=$(docker images --format "{{.Size}}" "urfd-${image}:${tag}" 2>/dev/null | head -n1)
                
                echo -e "  ${GREEN}${tag}${RESET}${latest_marker} - ${created} (${size})"
            done
        else
            echo -e "  ${GRAY}(no tags found)${RESET}"
        fi
    else
        echo -e "  ${GRAY}(image not found)${RESET}"
    fi
    echo ""
done

# Check for running instances
if [[ -d "${INSTANCES_DIR}" ]]; then
    echo -e "${CYAN}Running instances:${RESET}"
    
    instance_found=false
    for instance_dir in "${INSTANCES_DIR}"/*; do
        if [[ -d "${instance_dir}" ]]; then
            instance_name=$(basename "${instance_dir}")
            
            # Check if docker-compose.yml exists
            if [[ -f "${instance_dir}/docker-compose.yml" ]]; then
                # Try to detect version from .env file
                version="unknown"
                if [[ -f "${instance_dir}/.env" ]]; then
                    if grep -q "^IMAGE_VERSION=" "${instance_dir}/.env" 2>/dev/null; then
                        version=$(grep "^IMAGE_VERSION=" "${instance_dir}/.env" | cut -d= -f2)
                    fi
                fi
                
                # Check if instance is running
                status="${GRAY}stopped${RESET}"
                if docker compose -f "${instance_dir}/docker-compose.yml" ps --quiet 2>/dev/null | grep -q .; then
                    status="${GREEN}running${RESET}"
                fi
                
                echo -e "  ${BOLD}${instance_name}${RESET} - version ${version} [${status}]"
                instance_found=true
            fi
        fi
    done
    
    if [[ "${instance_found}" == "false" ]]; then
        echo -e "  ${GRAY}(no instances deployed)${RESET}"
    fi
    echo ""
else
    echo -e "${YELLOW}Instances directory not found: ${INSTANCES_DIR}${RESET}"
    echo ""
fi

echo -e "${GRAY}Use ${BOLD}./build-images.sh <version>${GRAY} to build new images${RESET}"
echo -e "${GRAY}Use ${BOLD}./cleanup-images.sh${GRAY} to remove old images${RESET}"
