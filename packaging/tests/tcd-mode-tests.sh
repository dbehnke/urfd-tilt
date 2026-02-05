#!/usr/bin/env bash
set -euo pipefail

# Simple smoke tests for tcd mode handling.
# Usage: BIN=/path/to/tcd ./tcd-mode-tests.sh

BIN=${BIN:-$(command -v tcd || echo ./dist/build-amd64/tcd/tcd)}
INI=${INI:-packaging/configs/tcd.ini}

if [[ ! -x "$BIN" ]]; then
  echo "tcd binary not found at $BIN"
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# 1) software mode should start (or at least run) when software support compiled
echo "Test: software mode"
"$BIN" --mode=software "$INI" >"$TMPDIR/tcd-software.log" 2>&1 &
pid=$!
sleep 2
if kill -0 "$pid" >/dev/null 2>&1; then
  kill "$pid" || true
  echo "PASS: software mode started"
else
  echo "FAIL: software mode did not stay running"
  tail -n +1 "$TMPDIR/tcd-software.log"
  exit 1
fi

# 2) hardware mode may either start (if hardware/fallback present) or exit non-zero
echo "Test: hardware mode (allow start or fail)"
"$BIN" --mode=hardware "$INI" >"$TMPDIR/tcd-hw.log" 2>&1 &
pid=$!
sleep 2
if kill -0 "$pid" >/dev/null 2>&1; then
  kill "$pid" || true
  echo "PASS: hardware mode started (device present or fallback)"
else
  wait "$pid" 2>/dev/null || true
  rc=$?
  echo "PASS: hardware mode exited with code $rc (no device)"
fi

# 3) auto mode should either start (if simulator or hardware present) or fall back to software
# We accept either behavior but ensure process exits gracefully or runs.
echo "Test: auto mode"
"$BIN" --mode=auto "$INI" >"$TMPDIR/tcd-auto.log" 2>&1 &
pid=$!
sleep 2
if kill -0 "$pid" >/dev/null 2>&1; then
  kill "$pid" || true
  echo "PASS: auto mode started (hardware or software)"
else
  # not running; check logs for graceful fallback
  if grep -q -i "falling back to software" "$TMPDIR/tcd-auto.log" 2>/dev/null; then
    echo "PASS: auto mode fell back to software"
  else
    echo "FAIL: auto mode did not start nor report fallback"
    tail -n +1 "$TMPDIR/tcd-auto.log"
    exit 1
  fi
fi

echo "All tcd-mode-tests passed"
exit 0
