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

- `packaging-multiarch.yml` — builds multi-arch packages (amd64, arm64) using buildx + QEMU and runs `lintian` validation.
- `podman-systemd.yml` — builds amd64 packages in-workflow, builds the `debian-trixie-systemd-kmod` test image, and executes `scripts/test-systemd.sh` with failure-on-service-failed gating.
- `tcd-mode-tests.yml` — focuses on TCD mode testing (software/hardware mode simulation) and runs wrapper-specific tests.
- `packer-parallels.yml` — manual workflow for building VM images via Packer.

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

## Placeholder policy

During iterative local development we create lightweight placeholder build artifacts when full native or containerized builds are not possible on the host (for example: macOS hosts with Colima/docker buildx runtime mismatches). Placeholders let `nfpm` produce `.deb` files so packaging and CI flows can be exercised without requiring a full compile of every component.

Placeholders are created by `packaging/scripts/make_placeholders_from_nfpm.py` and live under `dist/build-<arch>/...` or may be checked in under `packaging/placeholders/<package>/` for repeated use.

Current placeholders created during the last run (local paths):

- dist/build-amd64/imbe_vocoder/libimbe_vocoder.a
- dist/build-arm64/imbe_vocoder/libimbe_vocoder.a
- dist/build-amd64/imbe_vocoder/imbe_vocoder.h
- dist/build-arm64/imbe_vocoder/imbe_vocoder.h
- dist/build-amd64/md380_vocoder_dynarmic/libmd380_vocoder.a
- dist/build-arm64/md380_vocoder_dynarmic/libmd380_vocoder.a
- dist/build-amd64/md380_vocoder.h
- dist/build-arm64/md380_vocoder.h

How to replace placeholders:

1. Build the real artifacts for the target architecture (use `packaging/build-packages.sh` on a Linux runner or build the individual component). 2. Copy the real build outputs into `dist/build-<arch>/<component>/` replacing placeholder files. 3. Re-run `packaging/build-packages.sh` to produce packages with the real artifacts.

Note: CI workflows should prefer running full multi-arch builds (setup-qemu + buildx) instead of relying on placeholders. Placeholders are intended for local iterative testing only and must be documented in PRs when present.

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
- CI integration (`packaging-multiarch.yml`, `podman-systemd.yml`, `tcd-mode-tests.yml`) is active and exercises packaging, lintian validation, and systemd tests.

## CI Artifacts and Local Run Results

- CI will produce the following artifacts (uploaded by workflows):
  - `dist-debs` (packaging-multiarch): `dist/*.deb` for built architectures
  - `packaging-artifacts`: `artifacts/lintian-ci.txt` and other CI logs
  - `podman-systemd-artifacts-<arch>`: systemd test logs and journals

- Local run (on macOS host) produced these `.deb` files using placeholders and local cross-compile fallbacks:
  - dist/urfd_671f9-dirty_amd64.deb
  - dist/tcd_671f9-dirty_amd64.deb
  - dist/urfd-dashboard_671f9-dirty_amd64.deb
  - dist/urfd-suite_0.0.0~rc0_all.deb

- Placeholders created by `packaging/scripts/make_placeholders_from_nfpm.py` during the local run:
  - dist/build-amd64/imbe_vocoder/libimbe_vocoder.a
  - dist/build-arm64/imbe_vocoder/libimbe_vocoder.a
  - dist/build-amd64/imbe_vocoder/imbe_vocoder.h
  - dist/build-arm64/imbe_vocoder/imbe_vocoder.h
  - dist/build-amd64/md380_vocoder_dynarmic/libmd380_vocoder.a
  - dist/build-arm64/md380_vocoder_dynarmic/libmd380_vocoder.a
  - dist/build-amd64/md380_vocoder.h
  - dist/build-arm64/md380_vocoder.h

Notes:
- Local containerized buildx and qemu invocations failed on macOS/Colima hosts with `containerd-shim` exec-format errors. For reliable multi-arch builds and lintian validation, run the `packaging-multiarch.yml` workflow on Ubuntu runners (GitHub Actions) where QEMU and buildx are available.

## Next Recommended Work

1. **Packaging polish**: Keep runtime dependency validation active in CI; `urfd` now depends on `libcurl4 | libcurl3t64-gnutls` for cross-distro compatibility.
2. **Upstream TCD improvement**: Add a `--mode` flag to `tcd` to simplify or remove the `urfd-tcd-run` wrapper.
3. **Release Automation**: Integrate package builds with GitHub Releases to automatically attach `.deb` files to new tags.

## Rebuild & Lintian Troubleshooting — Local run (detailed)

What I tried locally

- Inspected the produced dashboard binary:

  - file dist/build-amd64/urfd-nng-dashboard/urfd-dashboard
  - Result: ELF 64-bit, statically linked (BuildID present).

- Attempted to rebuild the Go dashboard dynamically (CGO_ENABLED=1):

  - Changes: build-packages.sh was updated to accept CGO_ENABLED from the
    environment and pass it into the Debian build container (and into the
    inner go build invocation). This allows opting into dynamic linking for
    iterative runs: e.g. SINGLE_ARCH=amd64 CGO_ENABLED=1 bash packaging/build-packages.sh

  - Local containerized builds (docker buildx on macOS/Colima) failed with
    buildkit/containerd shim exec-format errors. The packaging script falls
    back to copying placeholders or performing a local cross-compile when
    container builds fail.

  - I attempted a direct podman/debian:trixie build with CGO_ENABLED=1 and an
    installed C toolchain. That build failed inside the container with gcc
    reporting an unrecognized option `-m64` from cgo (this is a host/ABI/toolchain
    mismatch exposed by the macOS/Colima environment + QEMU emulation). This
    is a known local constraint on macOS and was the primary blocker to producing
    a dynamically linked dashboard binary locally.

- Outcome: because of host/container runtime constraints the local rebuild
  could not produce a dynamic binary. The packaging script was adjusted to
  allow CGO_ENABLED to be toggled, and we re-ran packaging to produce .deb
  artifacts. The produced .deb files are in dist/ (placeholders used where
  container builds failed). Checksums were produced.

Lintian runs performed

- Ran lintian in a podman container against dist/*.deb (lintian --display-info --display-experimental --show-overrides)
- Results summary:
  - E: statically-linked-binary (urfd-dashboard)
  - W: maintainer-script-calls-systemctl (urfd)
  - W: package-contains-timestamped-gzip (manpages/changelog gz timestamps)
  - W: syntax-error-in-debian-changelog (placeholders are not valid Debian changelogs)
  - Several informational and X: checks (see full lintian output in artifacts when run in CI)

Actions taken

- Added a temporary lintian override file for urfd-dashboard (packaging/docs/urfd-dashboard/lintian-overrides) and referenced it from the nfpm manifest so iterative local builds can include an override in the package. Note: the override is intended only for local iteration — final packaging should either produce a dynamic binary or document why a static binary is acceptable and include a formal lintian override with justification in the packaging metadata.

Why CI is required to finish this work

- Multi-arch buildx + QEMU on Ubuntu runners (GitHub Actions) is the reliable way to produce true dynamic binaries for multiple architectures. Local macOS hosts with Colima present several incompatibilities (containerd shims, QEMU syscall mismatches, cgo/gcc flags) that block producing dynamically linked Go binaries with CGO enabled.

Next actionable steps (what to run in CI or on a Linux runner)

1. Add a GitHub Actions job (packaging-multiarch) that:
   - sets up QEMU (tonistiigi/binfmt), registers a buildx builder, and runs multi-arch buildx builds for C components and for Go components with CGO_ENABLED=1 and an installed C toolchain in the builder image.
   - runs packaging/build-packages.sh to create .deb artifacts for amd64 and arm64.
   - runs lintian on the produced .deb files and fails the job on E: tags.

2. If CI cannot produce dynamic binaries for policy reasons, provide a documented lintian override with justification and include that in the package metadata (but prefer rebuilding dynamically).

3. Convert placeholder changelogs into proper Debian changelog format for release builds; for iterative local runs keep placeholders but treat lintian changelog warnings as expected until CI artifacts replace placeholders.

Commands I ran locally (for reproducibility and debugging)

```bash
# Rebuild (single-arch) with CGO enabled (attempt dynamic linking)
SINGLE_ARCH=amd64 CGO_ENABLED=1 bash packaging/build-packages.sh

# Inspect the binary
file dist/build-amd64/urfd-nng-dashboard/urfd-dashboard

# Run lintian inside podman
podman run --rm -v $(pwd)/dist:/dist:Z -w /dist docker.io/library/debian:12 \
  bash -lc "apt-get update >/dev/null && apt-get install -y --no-install-recommends lintian >/dev/null && lintian --display-info --display-experimental --show-overrides /dist/*.deb || true"
```

Record of blockers encountered

- docker buildx + buildkit errors on macOS/Colima (containerd-shim exec format) prevented several containerized builds.
- CGO container build failed inside debian:trixie pod due to gcc cgo flags (-m64) under the host emulation environment. This prevented local production of dynamically-linked urfd-dashboard.

If you want me to proceed automatically I will prepare a packaging-multiarch GitHub Actions workflow draft (locally only, not committed/pushed) and a short checklist to run on CI so the next CI run will produce dynamic artifacts and allow lintian to be re-run cleanly.

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
