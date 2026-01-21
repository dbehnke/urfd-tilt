#!/usr/bin/env bash
# Cleanup old URFD production Docker images
# Requires bash 4+ for associative arrays

set -euo pipefail

# Check bash version
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: This script requires bash 4 or later (you have ${BASH_VERSION})"
    echo "On macOS, install with: brew install bash"
    exit 1
fi

# Color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_VERSIONS_FILE="${SCRIPT_DIR}/.image-versions"
INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

# Default settings
KEEP_VERSIONS=3
DRY_RUN=true

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

# Usage message
usage() {
    cat <<EOF
${BOLD}URFD Production Image Cleanup${RESET}

Usage: $0 [OPTIONS]

Options:
  --keep N        Keep N most recent versions (default: ${KEEP_VERSIONS})
  --dry-run       Show what would be deleted without deleting (default)
  --force         Actually delete images (requires confirmation)
  -h, --help      Show this help message

Examples:
  $0                    # Dry-run, keep 3 most recent
  $0 --keep 5           # Dry-run, keep 5 most recent
  $0 --force            # Actually delete (with confirmation)
  $0 --keep 2 --force   # Keep 2 most recent and delete

${YELLOW}Warning:${RESET} This will remove Docker images to free up disk space.
Images used by running instances are protected and will not be deleted.
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep)
            KEEP_VERSIONS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            DRY_RUN=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${RESET}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate keep count
if ! [[ "${KEEP_VERSIONS}" =~ ^[0-9]+$ ]] || [[ "${KEEP_VERSIONS}" -lt 1 ]]; then
    echo -e "${RED}Error: --keep must be a positive integer${RESET}"
    exit 1
fi

echo -e "${BOLD}URFD Production Image Cleanup${RESET}"
echo ""
echo -e "Keep versions: ${GREEN}${KEEP_VERSIONS}${RESET}"
echo -e "Mode: ${YELLOW}$(${DRY_RUN} && echo "DRY-RUN" || echo "DELETE")${RESET}"
echo ""

# Get versions in use by running instances
declare -A PROTECTED_VERSIONS
if [[ -d "${INSTANCES_DIR}" ]]; then
    echo -e "${CYAN}Checking running instances...${RESET}"
    for instance_dir in "${INSTANCES_DIR}"/*; do
        if [[ -d "${instance_dir}" ]]; then
            instance_name=$(basename "${instance_dir}")
            
            # Try to detect version from .env file
            if [[ -f "${instance_dir}/.env" ]]; then
                if grep -q "^IMAGE_VERSION=" "${instance_dir}/.env" 2>/dev/null; then
                    version=$(grep "^IMAGE_VERSION=" "${instance_dir}/.env" | cut -d= -f2)
                    PROTECTED_VERSIONS["${version}"]=1
                    echo -e "  ${GREEN}Protected:${RESET} ${version} (used by ${instance_name})"
                fi
            fi
        fi
    done
    echo ""
fi

# Get all versions from .image-versions file
declare -a ALL_VERSIONS=()
if [[ -f "${IMAGE_VERSIONS_FILE}" ]]; then
    while IFS= read -r line; do
        # Parse: version|timestamp|components
        IFS='|' read -r version timestamp components <<< "$line"
        ALL_VERSIONS+=("${version}")
    done < "${IMAGE_VERSIONS_FILE}"
else
    echo -e "${YELLOW}No .image-versions file found${RESET}"
    echo ""
fi

# Sort versions (newest first) using semantic versioning
if [[ ${#ALL_VERSIONS[@]} -gt 0 ]]; then
    IFS=$'\n' SORTED_VERSIONS=($(printf '%s\n' "${ALL_VERSIONS[@]}" | sort -V -r))
    unset IFS
else
    SORTED_VERSIONS=()
fi

# Determine which versions to delete
declare -a VERSIONS_TO_DELETE=()
version_idx=0
for version in "${SORTED_VERSIONS[@]}"; do
    # Skip if protected
    if [[ -n "${PROTECTED_VERSIONS[${version}]:-}" ]]; then
        echo -e "${GREEN}Keeping:${RESET} ${version} (in use by instance)"
        continue
    fi
    
    # Keep N most recent versions
    if [[ ${version_idx} -lt ${KEEP_VERSIONS} ]]; then
        echo -e "${GREEN}Keeping:${RESET} ${version} (within keep limit)"
        version_idx=$((version_idx + 1))
        continue
    fi
    
    # Mark for deletion
    VERSIONS_TO_DELETE+=("${version}")
    echo -e "${RED}Deleting:${RESET} ${version}"
    version_idx=$((version_idx + 1))
done

echo ""

# Exit if nothing to delete
if [[ ${#VERSIONS_TO_DELETE[@]} -eq 0 ]]; then
    echo -e "${GREEN}No images to delete${RESET}"
    exit 0
fi

# Confirm deletion if not dry-run
if [[ "${DRY_RUN}" == "false" ]]; then
    echo -e "${YELLOW}About to delete ${#VERSIONS_TO_DELETE[@]} version(s)${RESET}"
    echo -e "${RED}This action cannot be undone!${RESET}"
    echo ""
    read -p "Type 'yes' to confirm deletion: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        echo -e "${YELLOW}Deletion cancelled${RESET}"
        exit 0
    fi
    echo ""
fi

# Delete images
for version in "${VERSIONS_TO_DELETE[@]}"; do
    echo -e "${CYAN}Processing version: ${version}${RESET}"
    
    for image in "${IMAGES[@]}"; do
        image_name="urfd-${image}:${version}"
        
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_name}\$"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                echo -e "  ${GRAY}Would delete: ${image_name}${RESET}"
            else
                echo -e "  ${RED}Deleting: ${image_name}${RESET}"
                if docker rmi "${image_name}" 2>/dev/null; then
                    echo -e "    ${GREEN}✓ Deleted${RESET}"
                else
                    echo -e "    ${YELLOW}⚠ Failed to delete (may be in use)${RESET}"
                fi
            fi
        fi
    done
    
    # Remove from .image-versions file if not dry-run
    if [[ "${DRY_RUN}" == "false" ]] && [[ -f "${IMAGE_VERSIONS_FILE}" ]]; then
        # Create temp file without this version
        grep -v "^${version}|" "${IMAGE_VERSIONS_FILE}" > "${IMAGE_VERSIONS_FILE}.tmp" || true
        mv "${IMAGE_VERSIONS_FILE}.tmp" "${IMAGE_VERSIONS_FILE}"
        echo -e "  ${GRAY}Removed from .image-versions${RESET}"
    fi
    
    echo ""
done

if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}DRY-RUN complete - no images were actually deleted${RESET}"
    echo -e "${GRAY}Use ${BOLD}--force${GRAY} to actually delete images${RESET}"
else
    echo -e "${GREEN}Cleanup complete${RESET}"
    
    # Optionally prune dangling images
    echo ""
    echo -e "${CYAN}Checking for dangling images...${RESET}"
    if dangling=$(docker images -f "dangling=true" -q); then
        if [[ -n "${dangling}" ]]; then
            echo -e "${YELLOW}Found dangling images. Run 'docker image prune' to remove them.${RESET}"
        else
            echo -e "${GREEN}No dangling images found${RESET}"
        fi
    fi
fi
