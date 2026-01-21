#!/bin/bash
#
# build-images.sh - Build all URFD Docker images with version tags
#
# This script builds production-ready Docker images for all URFD services
# with proper versioning and dependency order.
#
# Usage:
#   ./build-images.sh <version> [--also-tag-latest]
#
# Example:
#   ./build-images.sh v1.8.0
#   ./build-images.sh v1.8.0-dev --also-tag-latest
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory (works from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/.image-versions"

# Parse arguments
VERSION=""
TAG_LATEST=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --also-tag-latest)
      TAG_LATEST=true
      shift
      ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
      else
        echo -e "${RED}Error: Unknown argument: $1${NC}"
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate version provided
if [[ -z "$VERSION" ]]; then
  echo -e "${RED}Error: Version argument required${NC}"
  echo ""
  echo "Usage: $0 <version> [--also-tag-latest]"
  echo ""
  echo "Example:"
  echo "  $0 v1.8.0"
  echo "  $0 v1.8.0-dev --also-tag-latest"
  exit 1
fi

# Validate semantic versioning format: v1.2.3 or v1.2.3-suffix
VERSION_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$'
if [[ ! "$VERSION" =~ $VERSION_REGEX ]]; then
  echo -e "${RED}Error: Invalid version format: $VERSION${NC}"
  echo ""
  echo "Version must follow semantic versioning:"
  echo "  vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-SUFFIX"
  echo ""
  echo "Valid examples:"
  echo "  v1.0.0"
  echo "  v1.2.3"
  echo "  v1.8.0-dev"
  echo "  v2.0.0-rc1"
  echo "  v1.7.5-alpha"
  exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}URFD Production Image Builder${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Version:${NC} $VERSION"
echo -e "${GREEN}Tag as latest:${NC} $TAG_LATEST"
echo -e "${GREEN}Project root:${NC} $PROJECT_ROOT"
echo ""

# Check if submodules are initialized
echo -e "${YELLOW}Checking git submodules...${NC}"
cd "$PROJECT_ROOT"

# Git submodule status output:
# ' ' = initialized, '-' = not initialized, '+' = different commit
if git submodule status | grep -q '^-'; then
  echo -e "${RED}Error: Git submodules not initialized${NC}"
  echo ""
  echo "Run the following command to initialize submodules:"
  echo "  git submodule update --init --recursive"
  exit 1
fi

echo -e "${GREEN}✓ Submodules initialized${NC}"
echo ""

# Build images in dependency order
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Building Images${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Track build start time
BUILD_START=$(date +%s)

# 1. Build urfd-common (base image)
echo -e "${YELLOW}[1/6] Building urfd-common:${VERSION}${NC}"
docker build \
  -t "urfd-common:${VERSION}" \
  -f "$PROJECT_ROOT/common.Dockerfile" \
  "$PROJECT_ROOT"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "urfd-common:${VERSION}" "urfd-common:latest"
fi

echo -e "${GREEN}✓ urfd-common:${VERSION} built${NC}"
echo ""

# 2. Build vocoder libraries (parallel would be nice, but keep it simple)
echo -e "${YELLOW}[2/6] Building imbe-lib:${VERSION}${NC}"
docker build \
  -t "imbe-lib:${VERSION}" \
  -f "$PROJECT_ROOT/docker/imbe.Dockerfile" \
  "$PROJECT_ROOT/src/imbe_vocoder"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "imbe-lib:${VERSION}" "imbe-lib:latest"
fi

echo -e "${GREEN}✓ imbe-lib:${VERSION} built${NC}"
echo ""

echo -e "${YELLOW}[3/6] Building md380-lib:${VERSION}${NC}"
docker build \
  -t "md380-lib:${VERSION}" \
  -f "$PROJECT_ROOT/docker/md380.Dockerfile" \
  "$PROJECT_ROOT/src/md380_vocoder_dynarmic"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "md380-lib:${VERSION}" "md380-lib:latest"
fi

echo -e "${GREEN}✓ md380-lib:${VERSION} built${NC}"
echo ""

# 3. Build urfd (main reflector)
echo -e "${YELLOW}[4/6] Building urfd:${VERSION}${NC}"
docker build \
  -t "urfd:${VERSION}" \
  -f "$PROJECT_ROOT/docker/urfd.Dockerfile" \
  "$PROJECT_ROOT/src/urfd"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "urfd:${VERSION}" "urfd:latest"
fi

echo -e "${GREEN}✓ urfd:${VERSION} built${NC}"
echo ""

# 4. Build tcd (transcoder - needs vocoder libs)
echo -e "${YELLOW}[5/6] Building tcd:${VERSION}${NC}"
docker build \
  -t "tcd:${VERSION}" \
  --build-arg IMBE_VERSION="${VERSION}" \
  --build-arg MD380_VERSION="${VERSION}" \
  -f "$PROJECT_ROOT/docker/tcd.Dockerfile" \
  "$PROJECT_ROOT"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "tcd:${VERSION}" "tcd:latest"
fi

echo -e "${GREEN}✓ tcd:${VERSION} built${NC}"
echo ""

# 5. Build dashboard
echo -e "${YELLOW}[6/6] Building dashboard:${VERSION}${NC}"
docker build \
  -t "dashboard:${VERSION}" \
  -f "$PROJECT_ROOT/docker/dashboard.Dockerfile" \
  "$PROJECT_ROOT/src/urfd-nng-dashboard"

if [[ "$TAG_LATEST" == true ]]; then
  docker tag "dashboard:${VERSION}" "dashboard:latest"
fi

echo -e "${GREEN}✓ dashboard:${VERSION} built${NC}"
echo ""

# Optional: Build allstar-nexus if it exists
if [[ -d "$PROJECT_ROOT/src/allstar-nexus" ]]; then
  echo -e "${YELLOW}[OPTIONAL] Building allstar-nexus:${VERSION}${NC}"
  docker build \
    -t "allstar-nexus:${VERSION}" \
    -f "$PROJECT_ROOT/docker/allstar-nexus.Dockerfile" \
    "$PROJECT_ROOT/src/allstar-nexus"
  
  if [[ "$TAG_LATEST" == true ]]; then
    docker tag "allstar-nexus:${VERSION}" "allstar-nexus:latest"
  fi
  
  echo -e "${GREEN}✓ allstar-nexus:${VERSION} built${NC}"
  echo ""
  
  ALLSTAR_BUILT=true
else
  ALLSTAR_BUILT=false
fi

# Calculate build time
BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
BUILD_MINUTES=$((BUILD_DURATION / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

# Update .image-versions file
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
IMAGE_LIST="urfd tcd dashboard"
if [[ "$ALLSTAR_BUILT" == true ]]; then
  IMAGE_LIST="$IMAGE_LIST allstar-nexus"
fi

echo "${VERSION},${TIMESTAMP},${IMAGE_LIST}" >> "$VERSIONS_FILE"

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Build Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Version:${NC} $VERSION"
echo -e "${GREEN}Build time:${NC} ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
echo ""
echo -e "${GREEN}Images built:${NC}"
echo "  • urfd-common:${VERSION}"
echo "  • imbe-lib:${VERSION}"
echo "  • md380-lib:${VERSION}"
echo "  • urfd:${VERSION}"
echo "  • tcd:${VERSION}"
echo "  • dashboard:${VERSION}"
if [[ "$ALLSTAR_BUILT" == true ]]; then
  echo "  • allstar-nexus:${VERSION}"
fi

if [[ "$TAG_LATEST" == true ]]; then
  echo ""
  echo -e "${GREEN}Also tagged as 'latest'${NC}"
fi

echo ""
echo -e "${GREEN}Build information saved to:${NC} $VERSIONS_FILE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. List available images: ./deployment/build/list-images.sh"
echo "  2. Deploy an instance: ./deployment/scripts/deploy-instance.sh --name urf000 --version $VERSION ..."
echo ""
