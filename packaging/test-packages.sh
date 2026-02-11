#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"

if [ ! -d "$DIST_DIR" ] || [ -z "$(ls -A $DIST_DIR 2>/dev/null)" ]; then
    echo "No packages found in $DIST_DIR. Run packaging/build-packages.sh first." >&2
    exit 1
fi

IMAGE_TAG="urfd-packages-test:latest"

echo "Building test image $IMAGE_TAG"
docker build -t "$IMAGE_TAG" -f "$SCRIPT_DIR/Dockerfile.test" "$PROJECT_ROOT" \
  || { echo "Failed to build test image"; exit 1; }

echo "Running container to execute package tests"
docker run --rm "$IMAGE_TAG"

echo "Test image run complete"

# Run additional host-side tcd mode tests (fast smoke tests)
if [ -x "$SCRIPT_DIR/tests/tcd-mode-tests.sh" ]; then
  echo "Running host-side tcd mode smoke tests"
  (cd "$PROJECT_ROOT" && "$SCRIPT_DIR/tests/tcd-mode-tests.sh") || {
    echo "tcd mode tests failed" >&2
    exit 1
  }
  echo "Host-side tcd mode tests passed"
fi
