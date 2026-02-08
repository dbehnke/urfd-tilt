# Packaging Guide

This document describes the packaging implementation and how-to for maintainers: building multi-arch Debian packages, running package tests locally, CI behavior, and notes about the TCD wrapper. It is an implementation guide intended to complement `PACKAGING_PLAN.md`.

## Overview

- Goal: produce reproducible, multi-arch Debian packages for URFD and related components (urfd, tcd, urfd-dashboard, allstar-nexus) and optional vocoder libraries.
- Versioning: semantic versioning is sourced from git tags using `scripts/version.sh`. The packaging system injects `${PKG_VERSION}` into nfpm configs and passes `BUILD_VERSION` into builds.
- Packaging toolchain: nfpm for .deb generation, Docker buildx for C++ multi-arch builds, native Go cross-compilation for Go binaries where appropriate.
- Systemd integration: packages install systemd unit files into `/usr/lib/systemd/system/` and create runtime directories under `/var/lib/urfd` and `/var/log/urfd`.

## Quickstart — Build Packages Locally

Prereqs:

- Docker (with buildx and QEMU for multi-arch builds) or podman
- nfpm (install: `cargo install --locked nfpm` or use package)
- go 1.25.x (for native Go builds)
- bash, make

Typical steps:

1. Get a semantic version:

```bash
./scripts/version.sh
# or via Taskfile
task version
```

2. Build packages (multi-arch default):

```bash
# Builds amd64 and arm64 packages and places .deb files in dist/
bash packaging/build-packages.sh

# For single-arch development/testing
SINGLE_ARCH=amd64 bash packaging/build-packages.sh
```

3. Inspect output in `dist/`.

Notes:

- `build-packages.sh` reads the version from `scripts/version.sh` and substitutes `${PKG_VERSION}` into nfpm configs.
- If you need to pass a specific build version to Docker builds, the repos/Dockerfiles accept `ARG BUILD_VERSION` (Tilt/Tiltfile and deployment scripts also pass `BUILD_VERSION`).

## Testing Packages Locally

1. Basic package tests:

```bash
bash packaging/test-packages.sh  # expects .deb files in dist/
```

2. Full systemd integration test (requires podman/docker with systemd support):

```bash
bash scripts/test-systemd.sh --dist ./dist --image <optional_test_image>
```

3. Manual install in a disposable Debian container (example):

```bash
docker run -it --privileged --rm -v $(pwd)/dist:/tmp/dist debian:trixie /bin/bash
dpkg -i /tmp/dist/*.deb || apt-get update && apt-get install -f -y
systemctl start urfd.service
journalctl -u urfd -f
```

Notes:

- We maintain two test images under `scripts/docker/`: `debian-trixie-systemd.Dockerfile` and `debian-trixie-systemd-kmod.Dockerfile` (the latter contains `kmod` for tests that need `/sbin/rmmod`).
- Common failure reasons: missing runtime libraries, QEMU emulation issues on GH runners, and insufficient capabilities for systemd inside containers. Use the `-kmod` variant if tests touch kernel module removal.

## CI Summary

Current GitHub workflows (see `.github/workflows/`):

- `podman-systemd.yml` — builds multi-arch packages and runs the systemd package test harness (builds with buildx + QEMU, uploads `dist/` artifacts, runs `scripts/test-systemd.sh`)
- `tcd-mode-tests.yml` — focuses on TCD mode testing (software/hardware mode simulation) and runs wrapper-specific tests
- `packer-parallels.yml` — manual workflow for building VM images via Packer

In CI the `build-packages.sh` script is used as the canonical packaging pipeline. Artifacts are uploaded for each architecture.

Recommendations:

- Add `lintian` checks on the produced `.deb` files as a CI step to catch packaging policy issues.
- Ensure buildx builders are registered and QEMU is set up on runners for multi-arch builds.

## TCD Wrapper (`urfd-tcd-run`) — Why it exists

The `tcd` binary supports software and hardware vocoding. Upstream changes to `tcd` to add a first-class `--mode`/`--auto` flag would simplify packaging by removing the need for a wrapper script. Until then we provide `packaging/bin/urfd-tcd-run` which:

- auto-detects attached FTDI hardware and chooses hardware mode when present
- falls back to software mode when hardware is not present
- honors `URFD_TCD_MODE` env var to override detection

The wrapper is installed to `/usr/libexec/urfd/urfd-tcd-run` and systemd unit `urfd-tcd.service` invokes it. Unit and wrapper tests live in `packaging/tests/run-urfd-tcd-wrapper-test.sh` and `packaging/tests/tcd-mode-tests.sh`.

Recommended upstream work: add `--mode` or `--auto` to `tcd` so wrapper can be removed or simplified.

## Where artifacts live

- Build artifacts: `dist/` (contains architecture subdirs and `.deb` files)
- Build logs and test artifacts: `artifacts/` (CI/test output)

## Linting and Validation

- Use `lintian` to validate `.deb` files locally:

```bash
lintian dist/*.deb
```

- Validate package installation in a clean container (Debian Trixie) to ensure runtime deps are accurate.

## Troubleshooting

- Q: `systemd` failing inside container tests
  - A: Ensure your test image uses a systemd-enabled base (`debian-trixie-systemd`) and consider `--privileged` or `--cap-add=SYS_ADMIN` if running locally.

- Q: `rmmod: not found` during tests
  - A: Use the `-kmod` test image (`debian-trixie-systemd-kmod.Dockerfile`) which provides `kmod`.

- Q: Packages missing runtime libs
  - A: Confirm `packaging/nfpm/*.yaml` declares the correct dependencies (libnng, libcurl, libopus, libogg, etc.). Test install in a clean VM/container.

## Recent Changes & Status

- Phases 1-6 from `PACKAGING_PLAN.md` are implemented: version injection, systemd units, nfpm configs, builder Dockerfiles, `build-packages.sh`, and CI workflows.
- CI integration (`podman-systemd.yml`, `tcd-mode-tests.yml`) is active and exercises packaging and systemd tests.

## Next Recommended Work

1. Add `lintian` validation to CI
2. Consider adding release automation (build packages on tag and attach to GitHub release)
3. Upstream `tcd` improvement: `--mode` flag to simplify wrapper

---

For more details, see `PACKAGING_PLAN.md` and the packaging directory:

```
packaging/
  build-packages.sh
  test-packages.sh
  nfpm/
  systemd/
  configs/
  scripts/
```
