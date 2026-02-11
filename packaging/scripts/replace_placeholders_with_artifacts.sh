#!/usr/bin/env bash
set -euo pipefail

# replace_placeholders_with_artifacts.sh
# Copy real build artifacts into dist/build-<arch>/... replacing placeholder files
# Usage: ./packaging/scripts/replace_placeholders_with_artifacts.sh --src-dir /path/to/artifacts --arch amd64

usage() {
  cat <<EOF
Usage: $0 --src-dir PATH [--arch amd64|arm64|all]
Copies matching artifacts from --src-dir into dist/build-<arch>/ locations based on packaging/nfpm/*.yaml src mappings.
EOF
  exit 1
}

SRC_DIR=""
ARCH="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src-dir) SRC_DIR="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$SRC_DIR" ]]; then
  usage
fi

if [[ "$ARCH" = "all" ]]; then
  ARCHS=(amd64 arm64)
else
  ARCHS=($ARCH)
fi

ROOT="$(pwd)"
NFPM_DIR="$ROOT/packaging/nfpm"

echo "Using src dir: $SRC_DIR"

for manifest in "$NFPM_DIR"/*.yaml; do
  echo "Processing manifest: $manifest"
  # extract src: lines
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*src:[[:space:]]*(.*)$ ]]; then
      raw=${BASH_REMATCH[1]}
      # strip surrounding single or double quotes safely
      first_char=${raw:0:1}
      last_char=${raw: -1}
      if [[ "$first_char" == '"' && "$last_char" == '"' ]]; then
        raw="${raw:1:-1}"
      elif [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
        raw="${raw:1:-1}"
      fi
    for a in "${ARCHS[@]}"; do
      # Replace literal ${ARCH} and ${PKG_VERSION} tokens in the nfpm src string.
      # Use escaped dollar/braces in the replacement to avoid accidental shell
      # interpolation when the src contains ${...} placeholders.
      target_path="${raw//\$\{ARCH\}/$a}"
      target_path="${target_path//\$\{PKG_VERSION\}/$(basename "$ROOT") }"
        # normalize
        # realpath -m is not portable on macOS; use python to normalize paths portably
        target_path=$(python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))" "$ROOT" "$target_path")
        # compute candidate source inside SRC_DIR (try relative path same structure)
        candidate1=$(python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], os.path.relpath(sys.argv[2], sys.argv[3]))))" "$SRC_DIR" "$target_path" "$ROOT")
        candidate2=$(python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], os.path.basename(sys.argv[2]))))" "$SRC_DIR" "$target_path")
        if [[ -f "$candidate1" ]]; then
          echo "Copying $candidate1 -> $target_path"
          mkdir -p "$(dirname "$target_path")"
          cp -a "$candidate1" "$target_path"
        elif [[ -f "$candidate2" ]]; then
          echo "Copying $candidate2 -> $target_path"
          mkdir -p "$(dirname "$target_path")"
          cp -a "$candidate2" "$target_path"
        fi
      done
    fi
  done < "$manifest"
done

echo "Replacement complete. Please re-run: SINGLE_ARCH=<arch> bash packaging/build-packages.sh to rebuild packages with real artifacts."
