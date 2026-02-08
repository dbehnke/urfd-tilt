#!/bin/bash
set -euo pipefail

TMPROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

echo "[test] preparing isolated test root in $TMPROOT"
mkdir -p "$TMPROOT/bin" "$TMPROOT/dev/serial/by-id" "$TMPROOT/etc/urfd"
cp packaging/bin/urfd-tcd-run "$TMPROOT/bin/urfd-tcd-run"
chmod +x "$TMPROOT/bin/urfd-tcd-run"

cat > "$TMPROOT/bin/tcd" <<'EOF'
#!/bin/sh
echo "FAKE TCD CALLED" >&2
echo "ARGS: $@" >&2
exit 0
EOF
chmod +x "$TMPROOT/bin/tcd"

touch "$TMPROOT/etc/urfd/tcd.ini"

echo "[test1] no hardware present -> expect software"
OUT=$(URFD_DEV_ROOT="$TMPROOT/dev" URFD_TCD_INI="$TMPROOT/etc/urfd/tcd.ini" PATH="$TMPROOT/bin:$PATH" "$TMPROOT/bin/urfd-tcd-run" 2>&1 || true)
echo "$OUT"
if ! echo "$OUT" | grep -q "selected mode=software"; then
  echo "Wrapper did not select software mode when no hardware present" >&2
  exit 2
fi

echo "[test2] simulate hardware by creating /dev/serial/by-id/*ftdi* -> expect hardware"
touch "$TMPROOT/dev/serial/by-id/usb-FTDI_FT232R-FTDI_TEST"

OUT2=$(URFD_DEV_ROOT="$TMPROOT/dev" URFD_TCD_INI="$TMPROOT/etc/urfd/tcd.ini" PATH="$TMPROOT/bin:$PATH" "$TMPROOT/bin/urfd-tcd-run" 2>&1 || true)
echo "$OUT2"
if ! echo "$OUT2" | grep -q "selected mode=hardware"; then
  echo "Wrapper did not select hardware mode when device present" >&2
  exit 3
fi

echo "All wrapper tests passed"
exit 0
