#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
NFPM_DIR="$SCRIPT_DIR/nfpm"
ARCHS=(amd64 arm64)
# Allow quick single-arch runs for development: set SINGLE_ARCH=amd64 (or arm64)
if [ -n "${SINGLE_ARCH:-}" ]; then
    ARCHS=("$SINGLE_ARCH")
    echo "[INFO] SINGLE_ARCH set: building for ${ARCHS[*]} only"
fi

    # Only include C services that have builder Dockerfiles present in src/
    # imbe_vocoder and md380_vocoder_dynarmic are optional components and
    # their Dockerfiles are not present in this repo; exclude them to avoid
    # noisy warnings during iterative packaging runs.
    C_SERVICES=(urfd tcd)
GO_SERVICES=(allstar-nexus urfd-nng-dashboard)
ALL_PACKAGES=("${C_SERVICES[@]}" "${GO_SERVICES[@]}")
META_PACKAGE="urfd-suite"

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*"
}

    TEMP_CONFIGS=()

cleanup() {
    log_info "Cleaning up..."
    # TEMP_CONFIGS may be unset or empty if packaging failed early; guard safely
    for config in "${TEMP_CONFIGS[@]:-}"; do
        [[ -n "$config" && -f "$config" ]] && rm -f "$config"
    done
}

trap cleanup EXIT

main() {
    log_info "Starting package build process..."

    # Capture version from git
    PKG_VERSION="$(bash "$PROJECT_ROOT/scripts/version.sh")"
    log_info "Package version: $PKG_VERSION"

    # Locate nfpm binary (used for packaging). Prefer PATH, then GOPATH/GOBIN locations.
    NFPM_BIN=""
    if command -v nfpm >/dev/null 2>&1; then
        NFPM_BIN="$(command -v nfpm)"
    else
        # Try common Go install locations
        GOPATH_BIN="$(go env GOPATH 2>/dev/null || true)/bin"
        GOBIN="$(go env GOBIN 2>/dev/null || true)"
        if [[ -x "$GOBIN/nfpm" ]]; then
            NFPM_BIN="$GOBIN/nfpm"
        elif [[ -x "$GOPATH_BIN/nfpm" ]]; then
            NFPM_BIN="$GOPATH_BIN/nfpm"
        fi
    fi
    if [[ -z "$NFPM_BIN" ]]; then
        log_error "nfpm not found in PATH or GOPATH/GOBIN. Install it with: 'go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest' or 'brew install goreleaser/tap/nfpm'"
        exit 1
    fi
    log_info "Using nfpm: $NFPM_BIN"

    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    for ARCH in "${ARCHS[@]}"; do
        log_info "=== Building for architecture: $ARCH ==="

        BUILD_DIR="$DIST_DIR/build-$ARCH"
        mkdir -p "$BUILD_DIR"

        for SERVICE in "${C_SERVICES[@]}"; do
            log_info "Building C++ service: $SERVICE ($ARCH)"

            DOCKERFILE="$PROJECT_ROOT/src/$SERVICE/Dockerfile.builder"
            if [[ ! -f "$DOCKERFILE" ]]; then
                DOCKERFILE="$PROJECT_ROOT/src/$SERVICE/Dockerfile"
            fi

            if [[ ! -f "$DOCKERFILE" ]]; then
                log_warn "Dockerfile not found for $SERVICE; skipping C++ build for this service"
                continue
            fi

            # Use repository root as build context so Dockerfiles that COPY from
            # `src/...` paths resolve correctly (some builder Dockerfiles expect
            # the repo root context). This keeps compatibility with multi-service
            # builder Dockerfiles.
            if ! docker buildx build \
                --platform "linux/$ARCH" \
                -f "$DOCKERFILE" \
                --output "type=local,dest=$BUILD_DIR/$SERVICE" \
                "$PROJECT_ROOT"; then
                    # Don't fail the entire packaging run for a single service
                    # during iterative development. Continue and allow nfpm to
                    # package any artifacts that were produced successfully.
                    log_warn "Failed to build $SERVICE for $ARCH; attempting placeholder fallback"
                    # If a placeholder bundle exists in packaging/placeholders,
                    # copy it into the expected build output so nfpm can still
                    # create packages during iterative development/testing.
                    PLACEHOLDER_DIR="$PROJECT_ROOT/packaging/placeholders/$SERVICE"
                    if [[ -d "$PLACEHOLDER_DIR" ]]; then
                        mkdir -p "$BUILD_DIR/$SERVICE"
                        cp -a "$PLACEHOLDER_DIR/." "$BUILD_DIR/$SERVICE/" || true
                        chmod +x "$BUILD_DIR/$SERVICE/"* || true
                        log_info "Copied placeholder artifacts for $SERVICE -> $BUILD_DIR/$SERVICE"
                        # continue to next service (packaging will pick this up)
                        continue
                    fi
                    log_warn "No placeholder available for $SERVICE; continuing to next service"
                    continue
                fi
        done

    for SERVICE in "${GO_SERVICES[@]}"; do
        log_info "Building Go service: $SERVICE ($ARCH)"

            SERVICE_DIR="$PROJECT_ROOT/src/$SERVICE"
            # Default binary name is the service basename, but some packages
            # expect a different final binary name (eg. `urfd-nng-dashboard`
            # package installs `/usr/bin/urfd-dashboard`). Handle known
            # exceptions here so nfpm paths match the produced artifacts.
            case "$SERVICE" in
                "urfd-nng-dashboard") BINARY_NAME="urfd-dashboard" ;;
                *) BINARY_NAME=$(basename "$SERVICE") ;;
            esac

        # Ensure per-service build output directory exists
        mkdir -p "$BUILD_DIR/$SERVICE"

            # Determine the package path to build. Prefer a root-level main
            # package, otherwise look for a `cmd/*` subdirectory that contains
            # a main.go entrypoint (common in monorepos).
            BUILD_PKG=""
            if compgen -G "$SERVICE_DIR"/*.go >/dev/null 2>&1; then
                BUILD_PKG="."
            elif [[ -d "$SERVICE_DIR/cmd" ]]; then
                for d in "$SERVICE_DIR/cmd"/*; do
                    if [[ -f "$d/main.go" ]]; then
                        BUILD_PKG="./cmd/$(basename "$d")"
                        break
                    fi
                done
            fi
            if [[ -z "$BUILD_PKG" ]]; then
                log_error "No Go entrypoint found for $SERVICE in $SERVICE_DIR"
                exit 1
            fi

            log_info "Building package path: $BUILD_PKG -> $BUILD_DIR/$SERVICE/$BINARY_NAME"

            # Build Go binaries inside a Debian trixie container to ensure
            # the produced binaries are linked against the same libc/libstdc++
            # versions that we target at runtime. This avoids host-toolchain
            # mismatches (macOS host, newer glibc, etc.). The container will
            # write the binary to the $BUILD_DIR/$SERVICE directory via a bind mount.
            mkdir -p "$BUILD_DIR/$SERVICE"
            log_info "Building $SERVICE inside debian:trixie for linux/$ARCH"
            # Precompute the Go tarball name on the host so we don't rely on
            # variable assignment/expansion inside the inner quoted docker
            # command (which would be evaluated inside the container only).
            GO_TARBALL_HOST="go1.25.6.linux-${ARCH}.tar.gz"
            # Mount the service source and the absolute build output directory
            # directly. Previously we prefixed the absolute $BUILD_DIR with
            # "$(pwd)/" which produced an incorrect host path and caused
            # some Go build outputs to be written to the container-only
            # filesystem (empty host directory). Use the absolute path as
            # produced earlier so the container writes into the real
            # $DIST_DIR/build-<arch> location.
            if ! docker run --rm --platform "linux/$ARCH" \
                -e CGO_ENABLED="${CGO_ENABLED:-0}" \
                -v "$SERVICE_DIR":/src:ro \
                -v "$BUILD_DIR/$SERVICE":/out:rw \
                -w /src \
                debian:trixie bash -lc "set -euo pipefail; \
                    apt-get update; \
                    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                        ca-certificates build-essential wget curl >/dev/null; \
                    # Install Go 1.25.6 to ensure reproducible toolchain and
                    # avoid host/go-version mismatches. Use the official tarball
                    # from go.dev and extract to /usr/local/go.
                    curl -fsSL \"https://go.dev/dl/${GO_TARBALL_HOST}\" -o /tmp/go.tgz; \
                    rm -rf /usr/local/go; mkdir -p /usr/local; tar -C /usr/local -xzf /tmp/go.tgz; \
                    export PATH=/usr/local/go/bin:$PATH; \
                    # Allow overriding CGO_ENABLED from the environment for iterative
                    # development. Default is 0 (static). Set CGO_ENABLED=1 to enable
                    # cgo and dynamic linking when a C toolchain is available.
                    CGO_FLAG="${CGO_ENABLED:-0}"; \
                    echo \"[INFO] Building with CGO_ENABLED=\$CGO_FLAG inside container\"; \
                    GOOS=linux GOARCH=${ARCH} CGO_ENABLED=\$CGO_FLAG /usr/local/go/bin/go build -ldflags='-s -w' -o /out/${BINARY_NAME} ${BUILD_PKG}"; then
                log_warn "Failed to build $SERVICE for $ARCH inside debian:trixie; attempting local cross-compile fallback"
                # Fallback: try local Go cross-compile (GOOS=linux GOARCH) if available.
                if command -v go >/dev/null 2>&1; then
                    log_info "Attempting local cross-compile for $SERVICE -> $BUILD_DIR/$SERVICE/$BINARY_NAME"
                    # Ensure output directory exists
                    mkdir -p "$BUILD_DIR/$SERVICE"
                    if (cd "$SERVICE_DIR" && env GOOS=linux GOARCH=${ARCH} CGO_ENABLED=0 go build -ldflags='-s -w' -o "$BUILD_DIR/$SERVICE/$BINARY_NAME" $BUILD_PKG) 2>/tmp/go-build-err.log; then
                        log_info "Local cross-compile succeeded for $SERVICE"
                    else
                        log_warn "Local cross-compile failed for $SERVICE (see /tmp/go-build-err.log); continuing"
                        cat /tmp/go-build-err.log || true
                        continue
                    fi
                else
                    log_warn "Local go tool not found; cannot cross-compile $SERVICE. Continuing."
                    continue
                fi
            fi
        done
    done

    log_info "=== Creating DEB packages ==="

    for PKG in "${ALL_PACKAGES[@]}"; do
        for ARCH in "${ARCHS[@]}"; do
            NFPM_CONFIG="$NFPM_DIR/$PKG.yaml"

            if [[ ! -f "$NFPM_CONFIG" ]]; then
                log_warn "nfpm config not found: $NFPM_CONFIG, skipping..."
                continue
            fi

            log_info "Creating package: $PKG ($ARCH)"

            BUILD_DIR="$DIST_DIR/build-$ARCH/$PKG"

            # If build artifacts for this package are missing, attempt to use
            # a local placeholder bundle (packaging/placeholders/<pkg>) so
            # iterative packaging runs can produce .deb artifacts even when
            # full builds fail on the current host (eg. macOS/Colima platform
            # mismatches). If no placeholder exists, skip packaging for this
            # package and continue.
            if [[ ! -d "$BUILD_DIR" ]] || [[ -z "$(ls -A "$BUILD_DIR" 2>/dev/null)" ]]; then
                PLACEHOLDER_DIR="$PROJECT_ROOT/packaging/placeholders/$PKG"
                if [[ -d "$PLACEHOLDER_DIR" ]]; then
                    log_warn "Build artifacts missing for $PKG ($BUILD_DIR); copying placeholder from $PLACEHOLDER_DIR"
                    mkdir -p "$BUILD_DIR"
                    cp -a "$PLACEHOLDER_DIR/." "$BUILD_DIR/" || true
                    chmod +x "$BUILD_DIR/"* || true
                    log_info "Copied placeholder artifacts for $PKG -> $BUILD_DIR"
                else
                    log_warn "Build artifacts missing for $PKG ($BUILD_DIR) and no placeholder found; skipping package creation"
                    continue
                fi
            fi

            # Prepare per-package docs to avoid nfpm content collisions when the
            # same source doc files are referenced by multiple package manifests.
            # Create per-package copies and ensure gzip files are produced without
            # embedded timestamps (lintian warns on timestamped gz files).
            PER_PKG_DOC_DIR="$DIST_DIR/docs/$PKG"
            mkdir -p "$PER_PKG_DOC_DIR"
            # Copy COPYRIGHT if present
            if [[ -f "$PROJECT_ROOT/packaging/docs/COPYRIGHT" ]]; then
                cp "$PROJECT_ROOT/packaging/docs/COPYRIGHT" "$PER_PKG_DOC_DIR/COPYRIGHT" || true
            fi

            # Handle changelog: prefer the uncompressed file if available, and
            # always produce a gzipped changelog with gzip -n to avoid timestamp
            # metadata that lintian flags.
                if [[ -f "$PROJECT_ROOT/packaging/docs/changelog.Debian" ]]; then
                cp "$PROJECT_ROOT/packaging/docs/changelog.Debian" "$PER_PKG_DOC_DIR/changelog.Debian" || true
                # Use maximal compression and omit timestamp metadata to satisfy lintian
                gzip -9 -n -c "$PROJECT_ROOT/packaging/docs/changelog.Debian" > "$PER_PKG_DOC_DIR/changelog.Debian.gz" || true
            elif [[ -f "$PROJECT_ROOT/packaging/docs/changelog.Debian.gz" ]]; then
                # Re-compress without timestamps and with maximal compression
                gunzip -c "$PROJECT_ROOT/packaging/docs/changelog.Debian.gz" 2>/dev/null | gzip -9 -n -c > "$PER_PKG_DOC_DIR/changelog.Debian.gz" || cp "$PROJECT_ROOT/packaging/docs/changelog.Debian.gz" "$PER_PKG_DOC_DIR/changelog.Debian.gz" || true
            fi

            # Normalise manpages: ensure per-package manpage .1.gz files are
            # created without timestamps. Accept either compressed or plain
            # source manpages in packaging/docs/manpages.
            if [[ -d "$PROJECT_ROOT/packaging/docs/manpages" ]]; then
                mkdir -p "$PER_PKG_DOC_DIR/manpages"
                for m in "$PROJECT_ROOT/packaging/docs/manpages"/*; do
                    [ -e "$m" ] || continue
                    name=$(basename "$m")
                    if [[ "$name" == *.gz ]]; then
                        # source is compressed; recompress without timestamps and with maximal compression
                        gunzip -c "$m" 2>/dev/null | gzip -9 -n -c > "$PER_PKG_DOC_DIR/manpages/$name" || cp "$m" "$PER_PKG_DOC_DIR/manpages/$name" || true
                    else
                        # source is plain; create a .gz without timestamps using maximal compression
                        gzip -9 -n -c "$m" > "$PER_PKG_DOC_DIR/manpages/$name.gz" || true
                    fi
                done
            fi

            TEMP_CONFIG="$DIST_DIR/${PKG}-${ARCH}.yaml"
            # Expand variables in the nfpm config into a temp file for packaging
            # and rewrite any shared packaging/docs/* paths to the per-package
            # copies created above to avoid content-collision errors from nfpm.
            sed -e "s/\${ARCH}/$ARCH/g" \
                -e "s/\${PKG_VERSION}/$PKG_VERSION/g" \
                -e "s#packaging/docs/COPYRIGHT#${PER_PKG_DOC_DIR}/COPYRIGHT#g" \
                -e "s#packaging/docs/changelog.Debian#${PER_PKG_DOC_DIR}/changelog.Debian#g" \
                -e "s#packaging/docs/changelog.Debian.gz#${PER_PKG_DOC_DIR}/changelog.Debian.gz#g" \
                -e "s#packaging/docs/manpages/#${PER_PKG_DOC_DIR}/manpages/#g" \
                "$NFPM_CONFIG" > "$TEMP_CONFIG"
            TEMP_CONFIGS+=("$TEMP_CONFIG")

            "$NFPM_BIN" pkg \
                -f "$TEMP_CONFIG" \
                -p deb \
                --target "$DIST_DIR" || {
                log_error "Failed to create package $PKG for $ARCH"
                exit 1
            }
        done
    done

    log_info "=== Building meta-package ($META_PACKAGE) ==="

    META_CONFIG="$NFPM_DIR/$META_PACKAGE.yaml"

    if [[ -f "$META_CONFIG" ]]; then
        "$NFPM_BIN" pkg \
            -f "$META_CONFIG" \
            -p deb \
            --target "$DIST_DIR" || {
            log_error "Failed to create meta-package"
            exit 1
        }
    else
        log_warn "Meta-package config not found: $META_CONFIG"
    fi

    log_info "=== Build complete ==="
    log_info "Packages available in: $DIST_DIR"
    ls -lh "$DIST_DIR"/*.deb 2>/dev/null || true

    return 0
}

main "$@"
