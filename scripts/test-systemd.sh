#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/test-systemd.sh [--dist DIR] [--image IMAGE] [--machine NAME] [--keep-machine] [--fail-on-service-failed]
DIST="./dist"
IMAGE="local/debian-trixie-systemd:latest"
MACHINE_NAME="urfd-podman"
KEEP_MACHINE=false
FAIL_ON_SERVICE_FAILED=false
SERVICES="${URFD_SERVICES:-urfd urfd-dashboard tcd}"
TIMEOUT=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist) DIST="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    --machine) MACHINE_NAME="$2"; shift 2;;
    --keep-machine) KEEP_MACHINE=true; shift;;
    --fail-on-service-failed) FAIL_ON_SERVICE_FAILED=true; shift;;
    -h|--help) sed -n '1,240p' "$0"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ ! -d "$DIST" ] || [ -z "$(ls -A "$DIST"/*.deb 2>/dev/null || true)" ]; then
  echo "ERROR: No .deb files found in $DIST" >&2
  exit 2
fi

CTR_NAME="urfd-test-ctr-$$"
ARTDIR="./artifacts"
mkdir -p "$ARTDIR"

OS="$(uname -s)"

# Ensure podman available
if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman not found in PATH" >&2
  exit 2
fi

start_podman_machine_if_needed() {
  if ! podman machine inspect "$MACHINE_NAME" >/dev/null 2>&1; then
    # podman machine init takes the name as a positional parameter
    podman machine init "$MACHINE_NAME" --cpus 2 --memory 2048
  fi
  # Start the machine but ignore error if it's already running
  podman machine start "$MACHINE_NAME" || true
}

if [ "$OS" = "Darwin" ]; then
  start_podman_machine_if_needed
fi

echo "Starting systemd-enabled container..."
podman run --name "$CTR_NAME" -d \
  --systemd=always \
  --tmpfs /run --tmpfs /run/lock \
  -v "$(realpath "$DIST")":/tmp/urfd-dist:ro \
  "$IMAGE" /sbin/init

# wait for systemd PID 1
echo "Waiting for systemd inside container (timeout ${TIMEOUT}s)..."
t=0
while true; do
  if podman exec "$CTR_NAME" test -f /proc/1/comm >/dev/null 2>&1; then
    COMM=$(podman exec "$CTR_NAME" cat /proc/1/comm || true)
    if [ "$COMM" = "systemd" ]; then
      echo "systemd detected"
      break
    fi
  fi
  sleep 1
  t=$((t+1))
  if [ $t -ge $TIMEOUT ]; then
    echo "ERROR: timed out waiting for systemd in container" >&2
    podman logs "$CTR_NAME" > "$ARTDIR/container-logs.log" || true
    podman inspect "$CTR_NAME" > "$ARTDIR/container-inspect.json" || true
    podman rm -f "$CTR_NAME" || true
    [ "$OS" = "Darwin" ] && [ "$KEEP_MACHINE" = false ] && podman machine stop "$MACHINE_NAME" || true
    exit 2
  fi
done

echo "Installing .deb packages (best-effort)..."
podman exec "$CTR_NAME" bash -lc 'set -e; dpkg -i /tmp/urfd-dist/*.deb || (apt-get update && apt-get -f install -y)'

podman exec "$CTR_NAME" bash -lc 'set -e; systemctl daemon-reload || true'

FAILED_SERVICES=0
for s in $SERVICES; do
  echo "Checking service: $s"
  podman exec "$CTR_NAME" bash -lc "if systemctl list-unit-files | grep -q \"^${s}\\.service\"; then
      systemctl enable --now ${s}.service || true
      systemctl status ${s}.service --no-pager --full > /tmp/${s}-status.log || true
      journalctl -u ${s}.service -n 500 --no-pager > /tmp/${s}-journal.log || true
      cat /tmp/${s}-status.log
    else
      echo \"UNIT_MISSING ${s}\" >&2
    fi"
  # copy logs out
  podman cp "$CTR_NAME":/tmp/${s}-journal.log "$ARTDIR/${s}-journal.log" 2>/dev/null || true
  podman cp "$CTR_NAME":/tmp/${s}-status.log "$ARTDIR/${s}-status.log" 2>/dev/null || true
  # check active state if present
  ACTIVE=$(podman exec "$CTR_NAME" systemctl is-active ${s}.service 2>/dev/null || echo "unknown")
  if [ "$ACTIVE" != "active" ] && [ "$ACTIVE" != "unknown" ]; then
    echo "Service ${s} state: $ACTIVE"
    FAILED_SERVICES=$((FAILED_SERVICES+1))
  fi
done

# Collect global journal and inspect
podman exec "$CTR_NAME" journalctl -b -o short-iso > /tmp/journal.log || true
podman cp "$CTR_NAME":/tmp/journal.log "$ARTDIR/journal.log" 2>/dev/null || true
podman inspect "$CTR_NAME" > "$ARTDIR/container-inspect.json" || true
podman logs "$CTR_NAME" > "$ARTDIR/container-stdout.log" || true

echo "Cleaning up container..."
podman rm -f "$CTR_NAME" || true

if [ "$OS" = "Darwin" ] && [ "$KEEP_MACHINE" = false ]; then
  echo "Stopping podman machine $MACHINE_NAME"
  podman machine stop "$MACHINE_NAME" || true
fi

if [ "$FAILED_SERVICES" -gt 0 ]; then
  echo "Note: $FAILED_SERVICES service(s) were not active after enable/start. Logs are in $ARTDIR"
  if [ "$FAIL_ON_SERVICE_FAILED" = true ]; then
    exit 1
  fi
fi

echo "Artifacts saved in $ARTDIR"
exit 0
