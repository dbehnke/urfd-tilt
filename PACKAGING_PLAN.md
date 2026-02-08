# URFD Semantic Versioning, Debian Packaging & systemd Plan

## Overview

Add semantic versioning, `--version` flags, Debian packages (arm64/amd64 for Trixie), systemd services, and centralized config at `/etc/urfd/` — while keeping Tilt compatibility.

**Decisions made:**
- Single version from `urfd-tilt` git tags (all components share one version)
- Standard `git describe --abbrev=5` format: `v1.0.0` at tag, `v1.0.0-2-35dc1` ahead, `v1.0.0-2-35dc1-dirty` if dirty
- Protocol version (3.1.4 in CVersion) stays separate from package version
- Local build scripts first; CI/CD as follow-up

---

## Phase 1: Version Infrastructure

### 1.1 Create version script
**New file:** `scripts/version.sh`
```bash
#!/bin/bash
git describe --tags --always --dirty --abbrev=5 --match "v*" 2>/dev/null \
  | sed 's/-g\([0-9a-f]\)/-\1/' || echo "v0.0.0-dev"
```
Strips the `g` prefix from git hash. Output: `v1.0.0`, `v1.0.0-2-35dc1`, `v1.0.0-2-35dc1-dirty`.

### 1.2 urfd (C++) — add `--version` flag
**Modify:** `src/urfd/reflector/Makefile`
- Add `BUILD_VERSION ?= dev` and `-DBUILD_VERSION=\"$(BUILD_VERSION)\"` to CFLAGS

**Modify:** `src/urfd/reflector/Main.cpp`
- Add `#ifndef BUILD_VERSION` / `#define BUILD_VERSION "dev"` / `#endif` near top
- Before the argc==2 config check, add:
```cpp
if (argc == 2 && std::string(argv[1]) == "--version") {
    std::cout << "urfd " << BUILD_VERSION << " (protocol " << g_Version << ")" << std::endl;
    return EXIT_SUCCESS;
}
```
- Keep `CVersion g_Version(3,1,4)` untouched (protocol version)

### 1.3 tcd (C++) — add `--version` flag
**Modify:** `src/tcd/Makefile`
- Add `BUILD_VERSION ?= dev` and `-DBUILD_VERSION=\"$(BUILD_VERSION)\"` to CFLAGS

**Modify:** `src/tcd/Main.cpp`
- Add BUILD_VERSION define fallback
- Add `--version` handling before argc check
- Update hardcoded `"0.1.0"` string to use `BUILD_VERSION`

### 1.4 dashboard (Go) — add `-version` flag
**Modify:** `src/urfd-nng-dashboard/cmd/dashboard/main.go`
- Add `showVersion := flag.Bool("version", false, "Print version and exit")`
- After `flag.Parse()`, check and print `Version`, `Commit`, `Date`, then exit

### 1.5 allstar-nexus (Go) — add `--version` flag
**Modify:** `src/allstar-nexus/main.go`
- Add version flag, print `buildVersion` and `buildTime`, then exit

### 1.6 Update Dockerfiles to pass version
**Modify:** `docker/urfd.Dockerfile`, `docker/tcd.Dockerfile`, `docker/dashboard.Dockerfile`, `docker/allstar-nexus.Dockerfile`
- Add `ARG BUILD_VERSION=dev` and pass to make/go-build commands

### 1.7 Update Tiltfile
**Modify:** `Tiltfile`
- Add `build_args={'BUILD_VERSION': 'dev-tilt'}` to each `docker_build()` call

### 1.8 Update build-images.sh
**Modify:** `deployment/build/build-images.sh`
- Pass `--build-arg BUILD_VERSION=${VERSION}` to all docker builds

---

## Phase 2: systemd Service Files

**New files in** `packaging/systemd/`:

### 2.1 `urfd.service`
- `After=network-online.target`, `Wants=network-online.target`
- `User=urfd`, `Group=urfd`
- `ExecStart=/usr/bin/urfd /etc/urfd/urfd.ini`
- Security hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`
- `ReadWritePaths=/var/log/urfd /var/lib/urfd /var/run`

### 2.2 `urfd-tcd.service`
- `Requires=urfd.service`, `After=network-online.target urfd.service`
- `ExecStart=/usr/bin/tcd /etc/urfd/tcd.ini`
- `ExecStartPre=-/sbin/rmmod ftdi_sio` (for hardware vocoders)

### 2.3 `urfd-dashboard.service`
- `Requires=urfd.service`, `After=network-online.target urfd.service`
- `ExecStart=/usr/bin/urfd-dashboard -config /etc/urfd/dashboard.yaml`
- `WorkingDirectory=/var/lib/urfd`

### 2.4 `urfd-allstar-nexus.service`
- `After=network-online.target urfd.service` (After but not Requires — optional)
- `ExecStart=/usr/bin/allstar-nexus --config /etc/urfd/allstar-nexus.yaml`

All services: `Restart=always`, `RestartSec=5`, journal logging, `WantedBy=multi-user.target`.

---

## Phase 3: Default Config Files

**New files in** `packaging/configs/`:

### 3.1 `urfd.ini`
- Based on `config/defaults/urfd.ini`
- Paths adjusted: PID → `/var/run/urfd.pid`, logs → `/var/log/urfd/`, audio → `/var/lib/urfd/audio/`
- NNG: `tcp://127.0.0.1:5555` (localhost for bare-metal)

### 3.2 `tcd.ini`
- Based on `config/defaults/tcd.ini`
- `ServerAddress = 127.0.0.1` (connects to local urfd)

### 3.3 `dashboard.yaml`
- Based on `config/dashboard/config.yaml`
- `nng_url: tcp://127.0.0.1:5555`, `db_path: /var/lib/urfd/dashboard.db`
- Voice addrs: `tcp://127.0.0.1:5556`, `tcp://127.0.0.1:6556`

### 3.4 `allstar-nexus.yaml`
- Based on `src/allstar-nexus/config.yaml.example`
- Paths adjusted for `/etc/urfd/` and `/var/lib/urfd/`

---

## Phase 4: Debian Packaging with nfpm

### 4.1 Package scripts
**New files in** `packaging/scripts/`:
- `preinstall.sh` — create `urfd` system user/group
- `postinstall.sh` — `systemctl daemon-reload`, print setup instructions
- `preremove.sh` — stop and disable services
- `postremove.sh` — `daemon-reload`; on purge: remove `/etc/urfd`, `/var/log/urfd`, `/var/lib/urfd`, user/group

### 4.2 nfpm configs
**New files in** `packaging/nfpm/`:

| Config | Package | Binaries | Depends |
|--------|---------|----------|---------|
| `urfd.yaml` | `urfd` | urfd, urfd-inicheck, urfd-dbutil | libnng1, libcurl4t64, libopus0, libogg0, libfmt-dev, systemd |
| `urfd-tcd.yaml` | `urfd-tcd` | tcd | urfd, systemd |
| `urfd-nng-dashboard.yaml` | `urfd-dashboard` | urfd-dashboard | urfd, systemd |
| `urfd-allstar-nexus.yaml` | `urfd-allstar-nexus` | allstar-nexus | systemd (Recommends: urfd) |
| `urfd-server.yaml` | `urfd-server` | (none — meta-package) | urfd, urfd-tcd, urfd-dashboard |
| `urfd-suite.yaml` | `urfd-suite` | (none — meta-package) | urfd, urfd-dashboard, tcd |

**Note:** `urfd-nng-dashboard.yaml` creates the `urfd-dashboard` package. The file is named after the source repository (urfd-nng-dashboard) but produces a package named after the installed binary (urfd-dashboard).

**Meta-packages:**
- `urfd-server` — Full server deployment with directory creation (/var/log/urfd, /var/lib/urfd)
- `urfd-suite` — Lightweight dependencies-only package, depends on `tcd` instead of `urfd-tcd`

Each config specifies: binary → `/usr/bin/`, service → `/usr/lib/systemd/system/`, config → `/etc/urfd/` (noreplace), dirs `/var/log/urfd`, `/var/lib/urfd`.

### 4.3 Builder Dockerfiles for extracting binaries
**New files in** `packaging/`:

`Dockerfile.urfd-builder` — multi-stage: compile urfd/inicheck/dbutil in debian:trixie, copy to scratch for `--output type=local` extraction.

`Dockerfile.tcd-builder` — multi-stage: build vocoder libs, compile tcd, extract.

### 4.4 Master build script
**New file:** `packaging/build-packages.sh`

Captures version from `scripts/version.sh` and exports as `PKG_VERSION` for nfpm substitution.

For each arch (amd64, arm64):
1. Build C++ binaries via `docker buildx build --platform linux/$ARCH` with builder Dockerfiles
2. Build Go binaries via `GOOS=linux GOARCH=$ARCH CGO_ENABLED=0 go build` (native cross-compile)
3. Run `nfpm pkg -f packaging/nfpm/$PKG.yaml -p deb` for each package (after sed replacement of `${ARCH}` and `${PKG_VERSION}`)
4. Build meta-packages (arch: all)

Output: `dist/*.deb`

---

## Phase 5: Package Tests

### 5.1 Test script
**New file:** `packaging/test-packages.sh`

Runs in a Debian Trixie container:
- Install .deb files with `dpkg -i` + `apt-get install -f`
- Verify `urfd --version`, `tcd --version`, `urfd-dashboard -version`, `allstar-nexus --version`
- Verify files exist: `/etc/urfd/*.ini`, `/usr/lib/systemd/system/urfd*.service`
- Verify `urfd` user/group created
- Verify systemd dependency ordering in service files
- Verify config files marked `conffiles` (not overwritten on upgrade)

### 5.2 Test Dockerfile
**New file:** `packaging/Dockerfile.test`
```dockerfile
FROM debian:trixie
COPY dist/*.deb /tmp/
RUN dpkg -i /tmp/*.deb || apt-get install -f -y
RUN urfd --version && tcd --version
# ... additional assertions
```

---

## Phase 6: Taskfile Integration

**Modify:** `Taskfile.yml`
- Add `version` task: runs `scripts/version.sh`
- Add `build-packages` task: runs `packaging/build-packages.sh`
- Add `test-packages` task: runs test Dockerfile

---

## Files Summary

### New files (in urfd-tilt)
```
scripts/version.sh
packaging/
  build-packages.sh
  test-packages.sh
  Dockerfile.urfd-builder
  Dockerfile.tcd-builder
  Dockerfile.test
  nfpm/
    urfd.yaml
    urfd-tcd.yaml
    urfd-nng-dashboard.yaml
    urfd-allstar-nexus.yaml
    urfd-server.yaml
    urfd-suite.yaml
  systemd/
    urfd.service
    urfd-tcd.service
    urfd-dashboard.service
    urfd-allstar-nexus.service
  scripts/
    preinstall.sh
    postinstall.sh
    preremove.sh
    postremove.sh
  configs/
    urfd.ini
    tcd.ini
    dashboard.yaml
    allstar-nexus.yaml
```

### Modified files (in urfd-tilt)
```
Tiltfile                          — add BUILD_VERSION build args
Taskfile.yml                      — add version/packaging tasks
docker/urfd.Dockerfile            — add ARG BUILD_VERSION
docker/tcd.Dockerfile             — add ARG BUILD_VERSION
docker/dashboard.Dockerfile       — add ARG BUILD_VERSION
docker/allstar-nexus.Dockerfile   — add ARG BUILD_VERSION
deployment/build/build-images.sh  — pass BUILD_VERSION to all builds
```

### Modified files (in submodules)
```
src/urfd/reflector/Main.cpp       — add --version flag, BUILD_VERSION define
src/urfd/reflector/Makefile       — add BUILD_VERSION to CFLAGS
src/tcd/Main.cpp                  — add --version flag, BUILD_VERSION define
src/tcd/Makefile                  — add BUILD_VERSION to CFLAGS
src/urfd-nng-dashboard/cmd/dashboard/main.go — add -version flag
src/allstar-nexus/main.go         — add --version flag
```

## Verification

1. **Version flags:** Build locally with Tilt, exec into each container, run `--version` → should show `dev-tilt`
2. **Tagged build:** Tag `v1.0.0`, run `packaging/build-packages.sh` → produces .deb files in `dist/`
3. **Package install test:** Run `packaging/test-packages.sh` via Docker → all assertions pass
4. **Dirty detection:** Make a local change without committing, build → version ends in `-dirty`
5. **Tilt compatibility:** `tilt up` still works as before with no regressions
6. **systemd ordering:** Install packages on a Trixie VM, `systemctl start urfd-tcd` → automatically starts urfd first
7. **Config preservation:** Install package, edit `/etc/urfd/urfd.ini`, upgrade package → edited config preserved

## Implementation Progress

- [x] Phase 1: Version Infrastructure
- [x] Phase 2: systemd Service Files
- [x] Phase 3: Default Config Files
- [x] Phase 4: Debian Packaging with nfpm
- [x] Phase 5: Package Tests (partial)
- [x] Phase 6: Taskfile Integration
- [x] CI Integration: Completed and integrated with GitHub Actions

**Implementation Guide:**
- Complete implementation and deployment guide documented in `PACKAGING.md`
- Covers building, testing, CI pipeline details, and installation procedures

### Recent Updates (Completed)

**Phase 6 Completion:**
- Added `version`, `build-packages`, `test-packages`, and `test-systemd` tasks to root [Taskfile.yml](Taskfile.yml)
- All nfpm configs now use `${PKG_VERSION}` placeholder (replaced from `0.0.0`)
- [packaging/build-packages.sh](packaging/build-packages.sh) captures version via `scripts/version.sh` and injects into all packages

**Config Cleanup:**
- Removed `packaging/nfpm/urfd-dashboard.yaml` (expected wrong binary name `urfd-nng-dashboard`)
- Kept `packaging/nfpm/urfd-nng-dashboard.yaml` (expects correct binary name `urfd-dashboard`)

**Meta-Package Documentation:**
- Added inline documentation to [urfd-server.yaml](packaging/nfpm/urfd-server.yaml) and [urfd-suite.yaml](packaging/nfpm/urfd-suite.yaml)
- Documented their different use cases (full server vs lightweight dependencies-only)

Current status (what works now)

- Packaging: multi-arch packages build locally — `packaging/build-packages.sh` produces `dist/*.deb` (tested for `arm64`).
- Runtime deps: `packaging/nfpm/urfd.yaml` depends on `libcurl3t64-gnutls` and other runtime libs; `postinstall.sh` creates `/var/lib/urfd` so `urfd-dashboard` can `chdir` successfully.
- Systemd test harness: `scripts/test-systemd.sh` runs a systemd-enabled Debian Trixie container (podman/docker), installs `dist/*.deb`, enables/starts units and collects logs into `./artifacts/`.
- Service behavior: `urfd`, `urfd-dashboard`, and `urfd-tcd` start in the test container; runtime issues (missing libs, working dirs) were resolved in packaging and test harness.
- TCD wrapper: added `packaging/bin/urfd-tcd-run` (installed to `/usr/libexec/urfd/`) and updated `packaging/systemd/urfd-tcd.service` to call it; wrapper auto-detects hardware vs software vocoding and supports `URFD_TCD_MODE`, `URFD_TCD_INI`, `URFD_DEV_ROOT` for testing. See test harness in [`packaging/tests/run-urfd-tcd-wrapper-test.sh`](packaging/tests/run-urfd-tcd-wrapper-test.sh).
- Tests: added an isolated wrapper test `packaging/tests/run-urfd-tcd-wrapper-test.sh` (runs without root) and iterated the test harness to pre-install/fix runtime deps when needed.

What remains / possible next steps

1) CI integration (high priority) — add jobs to:
  - Build multi-arch packages via `packaging/build-packages.sh` and upload artifacts.
  - Run `scripts/test-systemd.sh` in CI using the systemd test image; ensure qemu/buildx registration on runners.
  - Run the wrapper unit test `packaging/tests/run-urfd-tcd-wrapper-test.sh` on Linux runners.

2) Test image improvements (recommended) — update `scripts/docker/debian-trixie-systemd.Dockerfile` to include `kmod` (so `/sbin/rmmod` exists) and common runtime packages to make tests deterministic.

3) Packaging polish — audit package dependencies and file locations:
  - Confirm `libcurl3t64-gnutls` is the correct dependency across supported distros or provide alternative transitional deps.
  - Consider additional package validation and linting.

4) Upstream change for tcd (long-term): add built-in auto-detection and `--mode` flag so the wrapper can be simplified or removed; add unit/integration tests in `src/tcd`.

6) Documentation: update `PACKAGING_PLAN.md` (this file), `src/tcd/README.md`, and packaging README with notes about `URFD_TCD_MODE` and the wrapper test so maintainers can reproduce locally.

Files of interest to review next

- `packaging/build-packages.sh`
- `packaging/nfpm/urfd.yaml`
- `packaging/nfpm/tcd.yaml`
- `packaging/scripts/postinstall.sh`
- `scripts/test-systemd.sh`
- `scripts/docker/debian-trixie-systemd.Dockerfile`
- `packaging/bin/urfd-tcd-run`
- `packaging/tests/run-urfd-tcd-wrapper-test.sh`
