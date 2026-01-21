# URFD Production Deployment - Implementation Plan

**Status**: Approved for Implementation  
**Created**: 2026-01-20  
**Last Updated**: 2026-01-20

## Executive Summary

This plan creates a **production-ready multi-instance deployment system** within the `urfd-tilt` repository, organized in a `deployment/` directory. It supports:

- ✅ Multiple independent reflector instances (URF000, URF001, URF002, etc.)
- ✅ Version-tagged Docker images (independent versioning per service)
- ✅ Port offset strategy (+100 increments)
- ✅ Template-based configuration with all fields documented
- ✅ Systemd service management (optional)
- ✅ AllStar Nexus (USRP) multi-instance support (converted from host networking)
- ✅ Build images on production server
- ✅ Image version tracking and cleanup

---

## Design Decisions (Confirmed)

1. ✅ **Instance Location**: `/opt/urfd-production/instances/` with configurable override via `URFD_INSTANCES_DIR`
2. ✅ **AllStar AMI Host**: Configurable in deploy script, defaults to `host.docker.internal`
3. ✅ **Config Templates**: Start with core fields (~20 per config), iterate and expand later
4. ✅ **Systemd**: Auto-install with `--systemd` flag in deploy-instance.sh
5. ✅ **Script Detection**: All scripts detect their own location, work from anywhere
6. ✅ **Version Format**: Enforce semantic versioning (v1.2.3 or v1.2.3-suffix)

---

## Directory Structure

```
urfd-tilt/
├── deployment/                              # NEW: Production deployment
│   ├── README.md                           # Production deployment guide
│   ├── build/                              # Image building
│   │   ├── build-images.sh                 # Build all images with version tag
│   │   ├── list-images.sh                  # List available image versions
│   │   ├── cleanup-images.sh               # Remove old/unused images
│   │   └── .image-versions                 # Track built versions
│   │
│   ├── templates/                          # Instance templates
│   │   ├── docker-compose.prod.yml         # Production compose template
│   │   ├── .env.template                   # Environment variables template
│   │   ├── configs/
│   │   │   ├── urfd.ini.template          # URFD config (all fields documented)
│   │   │   ├── tcd.ini.template           # TCD config (all fields documented)
│   │   │   ├── dashboard.yaml.template    # Dashboard config (all fields documented)
│   │   │   └── allstar-nexus.yaml.template # AllStar config (all fields documented)
│   │   └── systemd/
│   │       └── urfd-instance@.service     # Systemd service template
│   │
│   ├── scripts/                            # Management scripts
│   │   ├── deploy-instance.sh              # Deploy new instance
│   │   ├── manage-instance.sh              # Start/stop/status/logs
│   │   ├── upgrade-instance.sh             # Upgrade instance versions
│   │   ├── calculate-ports.sh              # Port calculation helper
│   │   └── validate-instance.sh            # Validate instance config
│   │
│   └── instances/                          # Deployed instances (git-ignored)
│       ├── urf000/                         # Instance directory
│       │   ├── docker-compose.yml          # Generated from template
│       │   ├── .env                        # Instance-specific variables
│       │   ├── config/                     # Instance configs
│       │   │   ├── urfd.ini
│       │   │   ├── tcd.ini
│       │   │   ├── dashboard/config.yaml
│       │   │   └── allstar-nexus/config.yaml
│       │   └── data/                       # Runtime data
│       │       ├── logs/
│       │       ├── audio/
│       │       ├── dashboard/
│       │       └── allstar-nexus/
│       ├── urf001/
│       └── urf002/
│
├── (existing development files...)
```

---

## Image Dependency Tree

```
urfd-common (base)
├── imbe-lib (vocoder library)
├── md380-lib (vocoder library)
├── urfd (reflector) - depends on urfd-common
├── tcd (transcoder) - depends on urfd-common + COPIES from imbe-lib + md380-lib
├── dashboard (web UI) - depends on urfd-common
└── allstar-nexus (optional USRP) - independent multi-stage build
```

**Build Order Required**:
1. `urfd-common` - Base image with all build tools
2. `imbe-lib` + `md380-lib` - Vocoder libraries (parallel builds)
3. `urfd`, `tcd`, `dashboard` - Main services (tcd needs vocoder artifacts)
4. `allstar-nexus` - Optional (independent)

---

## Port Allocation Strategy

| Service/Protocol | URF000 (offset=0) | URF001 (offset=100) | URF002 (offset=200) |
|-----------------|-------------------|---------------------|---------------------|
| **Dashboard**   | 8080              | 8180                | 8280                |
| **AllStar**     | 8090              | 8190                | 8290                |
| **DExtra**      | 30001             | 30101               | 30201               |
| **DPlus**       | 20001             | 20101               | 20201               |
| **DCS**         | 30051             | 30151               | 30251               |
| **DMRPlus**     | 8880              | 8980                | 9080                |
| **MMDVM**       | 62030             | 62130               | 62230               |
| **M17**         | 17000             | 17100               | 17200               |
| **YSF**         | 42000             | 42100               | 42200               |
| **P25**         | 41000             | 41100               | 41200               |
| **NXDN**        | 41400             | 41500               | 41600               |
| **URF**         | 10017             | 10117               | 10217               |
| **G3 Terminal** | 40000             | 40100               | 40200               |
| **Transcoder**  | 10100 (internal)  | 10100 (internal)    | 10100 (internal)    |
| **NNG Dashboard**| 5555 (internal)  | 5555 (internal)     | 5555 (internal)     |
| **NNG Voice**   | 5556 (internal)   | 5556 (internal)     | 5556 (internal)     |
| **NNG Voice Ctrl**| 6556 (internal) | 6556 (internal)     | 6556 (internal)     |

**Note**: Internal ports don't need offset since each instance has isolated Docker networks.

---

## AllStar Nexus Multi-Instance Support

### Problem
AllStar Nexus currently uses `network_mode: host`, which prevents multi-instance deployment.

### Solution
Convert to bridge networking with explicit port mappings:

**OLD (host mode - single instance only)**:
```yaml
allstar-nexus:
  network_mode: host
  environment:
    - AMI_HOST=127.0.0.1
```

**NEW (bridge mode - multi-instance compatible)**:
```yaml
allstar-nexus:
  ports:
    - "${ALLSTAR_PORT}:8080"
  environment:
    - AMI_HOST=${ASTERISK_HOST}  # defaults to host.docker.internal
```

### Configuration
- AllStar Nexus listens on configurable port (default 8080 internal)
- AMI connection to Asterisk can be:
  - **Local Asterisk**: Use `host.docker.internal` (Docker Desktop/Colima)
  - **Remote Asterisk**: Use remote IP address
- Port offset applies to AllStar web UI: 8080 → 8180 → 8280

---

## Version Management

### Version Format Validation
**Regex**: `^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$`

**Valid Examples**:
- `v1.0.0`
- `v1.2.3`
- `v1.8.0-dev`
- `v2.0.0-rc1`
- `v1.7.5-alpha`

**Invalid Examples**:
- `1.0.0` (missing 'v' prefix)
- `v1.0` (missing patch version)
- `v1.0.0.1` (too many version parts)
- `latest` (not semantic version)

### .image-versions Format
```
v1.7.5,2026-01-15T10:30:00Z,urfd tcd dashboard allstar-nexus
v1.8.0-dev,2026-01-20T14:22:00Z,urfd tcd dashboard allstar-nexus
v1.8.0-rc1,2026-01-18T09:15:00Z,urfd tcd dashboard allstar-nexus
```

### Per-Service Versioning
Each instance can mix versions independently:

```bash
# URF000 - Bleeding edge
URFD_VERSION=v1.8.0-dev
TCD_VERSION=v1.8.0-dev
DASHBOARD_VERSION=v1.8.0-dev
ALLSTAR_VERSION=v0.2.0-dev

# URF001 - Stable mix
URFD_VERSION=v1.7.5
TCD_VERSION=v1.7.5
DASHBOARD_VERSION=v1.7.4  # Dashboard on older version
ALLSTAR_VERSION=v0.1.8
```

---

## Complete File List (21 Files)

### Phase 1: Foundation & Build System (5 files)

#### 1. `deployment/.gitignore`
- Ignore `instances/` directory
- Ignore `.image-versions` (or track it?)
- Keep templates and scripts

#### 2. `deployment/build/build-images.sh`
**Purpose**: Build all Docker images with version tag

**Features**:
- Script directory detection (works from anywhere)
- Semantic version validation (v1.2.3 or v1.2.3-alpha)
- Build in dependency order
- Tag all images with version
- Update `.image-versions` tracker
- `--also-tag-latest` flag
- Colored output for build progress

**Usage**: 
```bash
./build-images.sh v1.8.0 [--also-tag-latest]
```

**Build Process**:
1. Validate version format
2. Check submodules initialized
3. Build urfd-common:VERSION
4. Build imbe-lib:VERSION and md380-lib:VERSION (parallel)
5. Build urfd:VERSION and dashboard:VERSION (parallel)
6. Build tcd:VERSION (requires vocoder libs)
7. Build allstar-nexus:VERSION (optional)
8. Update .image-versions
9. Optionally tag as :latest

#### 3. `deployment/build/list-images.sh`
**Purpose**: List available built images

**Features**:
- Read `.image-versions` file
- Query Docker for available tags
- Show which versions are running in instances
- Flag latest version

**Usage**: 
```bash
./list-images.sh
```

**Output Example**:
```
Available image versions:
  v1.7.5 (built 2026-01-15 10:30:00)
  v1.8.0-dev (built 2026-01-20 14:22:00) [latest]
  v1.8.0-rc1 (built 2026-01-18 09:15:00)

Image details:
  urfd: v1.7.5, v1.8.0-dev, v1.8.0-rc1, latest
  tcd: v1.7.5, v1.8.0-dev, v1.8.0-rc1, latest
  dashboard: v1.7.5, v1.8.0-dev, v1.8.0-rc1, latest
  allstar-nexus: v0.1.8, v0.2.0-dev
```

#### 4. `deployment/build/cleanup-images.sh`
**Purpose**: Remove old/unused images

**Features**:
- Keep N most recent versions (default: 3)
- Protect versions used by running instances
- Dry-run mode (default)
- Interactive confirmation
- `--force` flag

**Usage**: 
```bash
./cleanup-images.sh [--keep N] [--dry-run|--force]
```

**Process**:
1. Parse .image-versions
2. Identify versions to keep (N most recent)
3. Check running instances for versions in use
4. Build list of images to remove
5. Show what will be deleted (dry-run) or prompt confirmation
6. Remove Docker images

#### 5. `deployment/build/.image-versions`
**Purpose**: Track built image versions

**Format**: CSV with version, timestamp, image list

**Example**:
```
v1.7.5,2026-01-15T10:30:00Z,urfd tcd dashboard allstar-nexus
v1.8.0-dev,2026-01-20T14:22:00Z,urfd tcd dashboard allstar-nexus
```

---

### Phase 2: Templates (7 files)

#### 6. `deployment/templates/docker-compose.prod.yml`
**Purpose**: Production docker-compose template

**Key Features**:
- Environment variable substitution
- Versioned image tags: `${URFD_VERSION}`
- Container naming: `${INSTANCE_NAME}-urfd`
- All ports with ${} variables
- AllStar with bridge networking (no host mode)
- Restart policies: `unless-stopped`
- Optional resource limits (commented)
- Optional healthchecks (commented)

**Services**: urfd, tcd, dashboard, allstar-nexus (optional)

**Template Variables**:
- `${INSTANCE_NAME}` - Instance identifier
- `${URFD_VERSION}`, `${TCD_VERSION}`, `${DASHBOARD_VERSION}`, `${ALLSTAR_VERSION}`
- All port variables (DASHBOARD_PORT, DEXTRA_PORT, etc.)
- `${ASTERISK_HOST}` - For AllStar AMI connection

#### 7. `deployment/templates/.env.template`
**Purpose**: Environment variables template

**Sections**:

1. **Instance Identification**:
   - INSTANCE_NAME
   - CALLSIGN

2. **Service Versions**:
   - URFD_VERSION
   - TCD_VERSION
   - DASHBOARD_VERSION
   - ALLSTAR_VERSION

3. **Port Configuration**:
   - PORT_OFFSET
   - Calculated ports (DASHBOARD_PORT, DEXTRA_PORT, etc.)

4. **AllStar Configuration**:
   - ASTERISK_HOST
   - AMI_PORT
   - AMI_USERNAME
   - AMI_PASSWORD

5. **Metadata**:
   - SYSOP_EMAIL
   - COUNTRY
   - SPONSOR
   - DASHBOARD_URL
   - BOOTSTRAP_NODE

#### 8. `deployment/templates/configs/urfd.ini.template`
**Purpose**: URFD configuration template

**Approach**: Core fields first (~20), iterate later

**Core Sections** (with inline documentation):

1. **[Names]**:
   - Callsign = ${CALLSIGN}
   - SysopEmail = ${SYSOP_EMAIL}
   - Country = ${COUNTRY}
   - Sponsor = ${SPONSOR}
   - DashboardUrl = ${DASHBOARD_URL}
   - Bootstrap = ${BOOTSTRAP_NODE}

2. **[IP Addresses]**:
   - IPv4Binding = 0.0.0.0
   - IPv6Binding (optional, commented)

3. **[Modules]**:
   - Modules = ADMSZ
   - DescriptionA, DescriptionD, DescriptionM, DescriptionS, DescriptionZ

4. **[Dashboard]**:
   - Enable = true
   - NNGAddr = tcp://127.0.0.1:5555
   - Interval = 10
   - NNGDebug = false
   - ControlNNGEnable = true
   - ControlNNGAddr = tcp://127.0.0.1:5556

5. **[Audio]**:
   - Enable = true
   - path = /usr/local/bin/audio/

6. **[Transcoder]**:
   - Port = 10100
   - BindingAddress = 0.0.0.0
   - Modules = A

7. **Protocol Sections**: [DCS], [DExtra], [DPlus], [M17], [MMDVM], [DMRPlus], [YSF], [P25], [NXDN], [URF], [G3]
   - Each with Port and protocol-specific settings

8. **[Files]**:
   - PidPath, XmlPath, WhitelistPath, BlacklistPath, InterlinkPath, G3TerminalPath

**Documentation**: Each field has inline comment explaining its purpose

**TODO Section**: List additional fields to be added in future iterations

#### 9. `deployment/templates/configs/tcd.ini.template`
**Purpose**: TCD configuration template

**Core Fields** (with inline documentation):

1. **Connection Settings**:
   - ServerAddress = 127.0.0.1
   - Port = 10100

2. **Module Configuration**:
   - Modules = ADMSZ

3. **Audio Gains**:
   - DStarGainIn = 16
   - DStarGainOut = -16
   - DmrYsfGainIn = -3
   - DmrYsfGainOut = 0
   - UsrpTxGain = 12
   - UsrpRxGain = -6

4. **AGC Settings**:
   - AGC = true
   - AGCTargetLevel = -18.0

**Documentation**: Explain each gain setting and what it affects

#### 10. `deployment/templates/configs/dashboard.yaml.template`
**Purpose**: Dashboard configuration template

**Core Fields** (with inline documentation):

1. **server**:
   - addr: ":8080"
   - nng_url: "tcp://urfd:5555"
   - db_path: "data/dashboard.db"

2. **reflector**:
   - name: "${CALLSIGN} Dashboard"
   - description: "${SPONSOR}"
   - modules: { A: "Module A", D: "Module D", M: "Module M", S: "Module S", Z: "Module Z" }

3. **logging**:
   - level: "info"
   - console: true

4. **audio**:
   - enable: true
   - path: "/usr/local/bin/audio"

5. **voice**:
   - enable: true
   - reflector_addr: "tcp://urfd:5556"
   - control_addr: "tcp://urfd:6556"
   - transmit_password: ""
   - max_clients: 100
   - opus_bitrate: 12000
   - max_tx_duration: 120

**Variable Substitution**: ${CALLSIGN}, ${SPONSOR}

#### 11. `deployment/templates/configs/allstar-nexus.yaml.template`
**Purpose**: AllStar Nexus configuration template

**Core Fields** (with inline documentation):

1. **Server Configuration**:
   - port: 8080
   - app_env: production

2. **Branding**:
   - title: "Allstar Nexus - ${CALLSIGN}"
   - subtitle: ""

3. **Database**:
   - db_path: data/allstar.db
   - astdb_path: data/astdb.txt
   - astdb_url: http://allmondb.allstarlink.org/
   - astdb_update_hours: 24

4. **Security**:
   - jwt_secret: (generate random)
   - token_ttl_seconds: 86400

5. **AMI Configuration**:
   - ami_enabled: true
   - ami_host: ${ASTERISK_HOST}
   - ami_port: ${AMI_PORT}
   - ami_username: ${AMI_USERNAME}
   - ami_password: ${AMI_PASSWORD}
   - ami_events: "on"
   - ami_retry_interval: 15s
   - ami_retry_max: 60s

6. **Node Configuration**:
   - nodes: [] (to be configured)

7. **Feature Toggles**:
   - disable_link_poller: false
   - allow_anon_dashboard: true

8. **Discord** (optional, disabled by default)
9. **Gamification** (optional, disabled by default)

**Documentation**: Explain bridge networking vs host mode, AMI connection options

#### 12. `deployment/templates/systemd/urfd-instance@.service`
**Purpose**: Systemd service template

**Features**:
- Parameterized service (%i = instance name)
- Depends on docker.service
- Waits for docker to be ready
- Auto-restart on failure
- Uses docker-compose in instance directory

**Template**:
```ini
[Unit]
Description=URFD Reflector Instance %i
After=docker.service
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/urfd-production/instances/%i
ExecStartPre=/usr/bin/docker-compose pull -q
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
ExecReload=/usr/bin/docker-compose restart
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
```

**Installation**:
```bash
sudo cp deployment/templates/systemd/urfd-instance@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

**Usage**:
```bash
sudo systemctl start urfd-instance@urf000
sudo systemctl enable urfd-instance@urf001
sudo systemctl status urfd-instance@urf002
```

---

### Phase 3: Deployment Scripts (3 files)

#### 13. `deployment/scripts/calculate-ports.sh`
**Purpose**: Calculate port mappings for offset

**Features**:
- Takes PORT_OFFSET as parameter
- Outputs all port variables
- Validates offset is valid number
- Can output as .env format or shell export

**Usage**: 
```bash
./calculate-ports.sh 100
./calculate-ports.sh 200 --export  # For sourcing in shell
```

**Output**:
```
DASHBOARD_PORT=8180
ALLSTAR_PORT=8190
DEXTRA_PORT=30101
DPLUS_PORT=20101
DCS_PORT=30151
DMRPLUS_PORT=8980
MMDVM_PORT=62130
M17_PORT=17100
YSF_PORT=42100
P25_PORT=41100
NXDN_PORT=41500
URF_PORT=10117
G3_PORT=40100
```

**Port Calculation Logic**:
```bash
BASE_PORTS=(
  "DASHBOARD:8080"
  "ALLSTAR:8090"
  "DEXTRA:30001"
  "DPLUS:20001"
  "DCS:30051"
  "DMRPLUS:8880"
  "MMDVM:62030"
  "M17:17000"
  "YSF:42000"
  "P25:41000"
  "NXDN:41400"
  "URF:10017"
  "G3:40000"
)

PORT_OFFSET=${1:-0}

for port_def in "${BASE_PORTS[@]}"; do
  name="${port_def%%:*}"
  base="${port_def##*:}"
  calculated=$((base + PORT_OFFSET))
  echo "${name}_PORT=${calculated}"
done
```

#### 14. `deployment/scripts/validate-instance.sh`
**Purpose**: Validate instance configuration

**Features**:
- Validates instance before deployment
- Checks configuration completeness
- Verifies port availability
- Detects conflicts

**Usage**: 
```bash
./validate-instance.sh <instance-name>
```

**Checks Performed**:
1. Instance directory exists
2. Required files present:
   - docker-compose.yml
   - .env
   - config/urfd.ini
   - config/tcd.ini
   - config/dashboard/config.yaml
   - config/allstar-nexus/config.yaml (if USRP enabled)
3. .env has all required variables
4. Versions exist as Docker images
5. Ports not in use by other processes
6. Config syntax valid (basic check)
7. No port conflicts with other instances

**Exit Codes**:
- 0 = valid
- 1 = validation errors
- 2 = missing files
- 3 = port conflicts

**Output Example**:
```
Validating instance: urf001
✓ Instance directory exists
✓ docker-compose.yml present
✓ .env file present
✓ All required config files present
✓ All required environment variables set
✓ Docker images exist (urfd:v1.7.5, tcd:v1.7.5, dashboard:v1.7.5)
✓ All ports available
✓ No conflicts with other instances
✓ Configuration syntax valid

Instance urf001 is valid and ready to deploy.
```

#### 15. `deployment/scripts/deploy-instance.sh`
**Purpose**: Deploy new instance from templates

**Features**:
- Interactive mode (prompts for values)
- Non-interactive mode (all flags provided)
- Script directory detection
- Semantic version validation
- Port availability check
- Template variable substitution
- Auto-calculate ports from offset
- Generate all config files
- Optional: start instance after deploy
- Optional: install systemd service with `--systemd`
- Validation before deployment

**Usage**:
```bash
./deploy-instance.sh \
  --name urf001 \
  --callsign URF001 \
  --offset 100 \
  --urfd-version v1.7.5 \
  --tcd-version v1.7.5 \
  --dashboard-version v1.7.5 \
  --email sysop@example.com \
  --country US \
  --sponsor "Your Organization" \
  --url http://server.com:8180 \
  [--enable-usrp] \
  [--allstar-version v0.1.8] \
  [--asterisk-host host.docker.internal] \
  [--ami-port 5038] \
  [--ami-username admin] \
  [--ami-password secret] \
  [--start] \
  [--systemd]
```

**Actions**:
1. Parse command-line arguments
2. Interactive prompts for missing required values
3. Validate version formats (semantic versioning)
4. Check that Docker images exist for specified versions
5. Calculate all ports based on offset
6. Check port availability
7. Create instance directory structure
8. Generate .env file from template (substitute variables)
9. Generate docker-compose.yml from template
10. Generate config files from templates
11. Create empty data directories
12. Run validation (validate-instance.sh)
13. Optionally start instance
14. Optionally install systemd service
15. Print deployment summary and next steps

**Script Directory Detection**:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
```

**Template Substitution Example**:
```bash
# Read template
template=$(cat "$TEMPLATE_FILE")

# Substitute variables
output="${template//\$\{CALLSIGN\}/$CALLSIGN}"
output="${output//\$\{SYSOP_EMAIL\}/$SYSOP_EMAIL}"
# ... etc

# Write output
echo "$output" > "$OUTPUT_FILE"
```

**Deployment Summary Output**:
```
========================================
Instance Deployment Complete!
========================================

Instance Name: urf001
Callsign: URF001
Port Offset: 100

Services:
  URFD: v1.7.5
  TCD: v1.7.5
  Dashboard: v1.7.5

Ports:
  Dashboard: http://localhost:8180
  DExtra: 30101/udp
  DPlus: 20101/udp
  M17: 17100/udp
  ...

Location: /opt/urfd-production/instances/urf001

Next Steps:
  1. Review configuration in /opt/urfd-production/instances/urf001/config/
  2. Start instance: ./deployment/scripts/manage-instance.sh urf001 start
  3. View logs: ./deployment/scripts/manage-instance.sh urf001 logs -f
  4. Access dashboard: http://localhost:8180

Systemd service installed: urfd-instance@urf001
  Enable on boot: sudo systemctl enable urfd-instance@urf001
  Start now: sudo systemctl start urfd-instance@urf001
```

---

### Phase 4: Management Tools (2 files)

#### 16. `deployment/scripts/manage-instance.sh`
**Purpose**: Manage instance lifecycle

**Features**:
- Script directory detection
- Validates instance exists
- Wraps docker-compose commands
- Adds convenience commands

**Usage**:
```bash
./manage-instance.sh <instance-name> <command> [args]
```

**Commands**:
- `start` - Start all services
- `stop` - Stop all services
- `restart` - Restart all services
- `status` - Show container status
- `logs [svc]` - Show logs (use -f to follow)
- `ps` - List containers
- `pull` - Pull image updates
- `exec <svc>` - Execute shell in service
- `top` - Show resource usage

**Examples**:
```bash
./manage-instance.sh urf000 start
./manage-instance.sh urf001 logs urfd -f
./manage-instance.sh urf002 exec urfd /bin/bash
./manage-instance.sh urf000 top
./manage-instance.sh urf001 status
```

**Implementation**:
```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="${URFD_INSTANCES_DIR:-/opt/urfd-production/instances}"

INSTANCE_NAME="$1"
COMMAND="$2"
shift 2
ARGS="$@"

INSTANCE_DIR="$INSTANCES_DIR/$INSTANCE_NAME"

# Validate instance exists
if [[ ! -d "$INSTANCE_DIR" ]]; then
  echo "Error: Instance '$INSTANCE_NAME' not found at $INSTANCE_DIR"
  exit 1
fi

cd "$INSTANCE_DIR"

case "$COMMAND" in
  start)
    docker-compose up -d
    ;;
  stop)
    docker-compose down
    ;;
  restart)
    docker-compose restart
    ;;
  status)
    docker-compose ps
    ;;
  logs)
    docker-compose logs $ARGS
    ;;
  ps)
    docker-compose ps
    ;;
  pull)
    docker-compose pull
    ;;
  exec)
    docker-compose exec $ARGS
    ;;
  top)
    docker-compose top
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Available commands: start, stop, restart, status, logs, ps, pull, exec, top"
    exit 1
    ;;
esac
```

#### 17. `deployment/scripts/upgrade-instance.sh`
**Purpose**: Upgrade instance to new versions

**Features**:
- Validate new versions exist
- Backup current .env
- Update version variables
- Pull new images
- Optional restart
- Rollback on failure

**Usage**:
```bash
./upgrade-instance.sh <instance-name> \
  [--urfd-version v1.8.0] \
  [--tcd-version v1.8.0] \
  [--dashboard-version v1.8.0] \
  [--allstar-version v0.2.0] \
  [--restart] \
  [--rollback-on-fail]
```

**Actions**:
1. Validate instance exists
2. Check new versions are valid format (semantic versioning)
3. Check Docker images exist locally for new versions
4. Backup .env to .env.backup-TIMESTAMP
5. Update version variables in .env file
6. Pull new images
7. Optionally restart instance
8. Verify containers started successfully
9. On failure: optionally rollback to backup

**Example Output**:
```
Upgrading instance: urf001

Current versions:
  URFD: v1.7.5
  TCD: v1.7.5
  Dashboard: v1.7.5

New versions:
  URFD: v1.8.0
  TCD: v1.8.0
  Dashboard: v1.8.0

✓ Versions validated
✓ Backup created: .env.backup-20260120-143022
✓ Version variables updated
✓ Pulling new images...
  urfd:v1.8.0 - pulled
  tcd:v1.8.0 - pulled
  dashboard:v1.8.0 - pulled
✓ Restarting instance...
✓ All containers running

Upgrade complete!
```

---

### Phase 5: Documentation (2 files)

#### 18. `deployment/README.md`
**Purpose**: Complete production deployment guide

**Table of Contents**:

1. **Overview**
   - What this deployment system provides
   - Multi-instance architecture
   - Version management

2. **Prerequisites**
   - Docker and Docker Compose installed
   - Git submodules initialized
   - Sufficient disk space
   - Port availability

3. **Quick Start**
   - Build first image version
   - Deploy first instance
   - Verify it's running

4. **Building Images**
   - How to build new versions
   - Version naming conventions
   - Viewing available images
   - Cleaning up old images

5. **Deploying Instances**
   - Step-by-step instance deployment
   - Configuration options
   - Port planning
   - AllStar Nexus setup

6. **Managing Instances**
   - Starting/stopping instances
   - Viewing logs
   - Upgrading versions
   - Backup and restore

7. **Systemd Integration**
   - Installing systemd services
   - Auto-start on boot
   - Service management

8. **Configuration Reference**
   - URFD configuration fields
   - TCD configuration fields
   - Dashboard configuration fields
   - AllStar Nexus configuration fields

9. **Port Reference**
   - Standard port assignments
   - Port offset calculation
   - Multi-instance port table

10. **Upgrading Instances**
    - Building new versions
    - Upgrading specific services
    - Rolling back upgrades

11. **Troubleshooting**
    - Common issues
    - Port conflicts
    - Docker networking
    - AllStar Nexus connectivity

12. **Production Best Practices**
    - Firewall configuration
    - Reverse proxy setup (nginx/Caddy)
    - SSL/TLS certificates
    - Monitoring and alerting
    - Backup strategies

13. **Migration from Development**
    - How to transition from Tilt development to production
    - Preserving data and configs

**Format**: Comprehensive with code examples, tables, and step-by-step instructions

#### 19. **Update to main `README.md`**
**Changes**:
- Add "Production Deployment" section after "Troubleshooting"
- Link to `deployment/README.md`
- Brief overview
- Note difference between development (Tilt) and production (docker-compose)

**Example Addition**:
```markdown
## Production Deployment

This repository includes a **production-ready multi-instance deployment system** for running multiple URFD reflectors on a single server or across multiple servers.

For complete production deployment documentation, see [deployment/README.md](deployment/README.md).

### Key Features

- **Multi-instance support**: Run URF000, URF001, URF002 on different port ranges
- **Version management**: Independent versioning per service (urfd, tcd, dashboard, allstar-nexus)
- **Template-based configuration**: Deploy new instances from templates
- **Systemd integration**: Auto-start instances on boot
- **AllStar Nexus support**: Multi-instance USRP support with bridge networking

### Quick Production Start

```bash
# Build production images
./deployment/build/build-images.sh v1.8.0

# Deploy your first instance
./deployment/scripts/deploy-instance.sh \
  --name urf001 \
  --callsign URF001 \
  --offset 100 \
  --urfd-version v1.8.0 \
  --email sysop@example.com \
  --start

# Manage instance
./deployment/scripts/manage-instance.sh urf001 status
```

**Development vs Production**:
- **Development**: Use `tilt up` for local development with hot-reload
- **Production**: Use deployment scripts for versioned, multi-instance deployments
```

---

### Phase 6: Repository Configuration (2 files)

#### 20. `.gitignore` updates
Add to root `.gitignore`:
```
# Production deployment instances (local data)
deployment/instances/
```

**Note**: `deployment/build/.image-versions` should be tracked (not ignored) so we have a record of built versions in the repository.

#### 21. `docker-compose.usrp.yml` update
**Changes**:
- Remove `network_mode: host`
- Add explicit port mapping for AllStar
- Update environment variables for bridge networking

**Before**:
```yaml
services:
  allstar-nexus:
    image: allstar-nexus
    container_name: allstar-nexus
    network_mode: host
    environment:
      - URFD_HOST=localhost
    restart: unless-stopped
```

**After**:
```yaml
services:
  allstar-nexus:
    image: allstar-nexus
    container_name: allstar-nexus
    ports:
      - "8090:8080/tcp"  # AllStar web UI
    environment:
      - URFD_HOST=urfd
      - AMI_HOST=host.docker.internal  # For local Asterisk, or use remote IP
    depends_on:
      - urfd
    volumes:
      - ./config/allstar-nexus:/app/config:ro
      - ./data/allstar-nexus:/app/data
    restart: unless-stopped
```

**Purpose**: Make AllStar compatible with multi-instance deployment and consistent with production templates.

---

## Implementation Order

### Step 1: Create Directory Structure
```bash
mkdir -p deployment/{build,templates/{configs,systemd},scripts}
```

### Step 2: Build System (Phase 1)
1. Create `deployment/.gitignore`
2. Create `deployment/build/build-images.sh`
3. Create `deployment/build/list-images.sh`
4. Create `deployment/build/cleanup-images.sh`
5. Test image building with versioning

### Step 3: Templates (Phase 2)
1. Create `deployment/templates/docker-compose.prod.yml`
2. Create `deployment/templates/.env.template`
3. Create `deployment/templates/configs/urfd.ini.template`
4. Create `deployment/templates/configs/tcd.ini.template`
5. Create `deployment/templates/configs/dashboard.yaml.template`
6. Create `deployment/templates/configs/allstar-nexus.yaml.template`
7. Create `deployment/templates/systemd/urfd-instance@.service`

### Step 4: Port Calculation (Phase 3 - Part 1)
1. Create `deployment/scripts/calculate-ports.sh`
2. Test port calculation logic

### Step 5: Deployment (Phase 3 - Part 2)
1. Create `deployment/scripts/validate-instance.sh`
2. Create `deployment/scripts/deploy-instance.sh`
3. Test full deployment workflow

### Step 6: Management (Phase 4)
1. Create `deployment/scripts/manage-instance.sh`
2. Create `deployment/scripts/upgrade-instance.sh`
3. Test instance lifecycle

### Step 7: Documentation (Phase 5)
1. Write `deployment/README.md`
2. Update main `README.md`

### Step 8: Cleanup (Phase 6)
1. Update `.gitignore`
2. Update `docker-compose.usrp.yml`

---

## Testing Plan

### Test Scenarios

#### 1. Build Images
- ✅ Build v1.0.0 successfully
- ✅ Build v1.0.1-dev successfully
- ✅ Reject invalid version format
- ✅ Verify all images tagged correctly
- ✅ Verify `.image-versions` updated

#### 2. Deploy Instance
- ✅ Deploy URF000 with offset 0
- ✅ Deploy URF001 with offset 100
- ✅ Verify no port conflicts
- ✅ Verify configs generated correctly
- ✅ Verify variable substitution worked

#### 3. AllStar Nexus Bridge Mode
- ✅ Deploy instance with `--enable-usrp`
- ✅ Verify AllStar container starts
- ✅ Verify it can connect to Asterisk at `host.docker.internal`
- ✅ Test with remote Asterisk IP

#### 4. Instance Management
- ✅ Start/stop/restart instances
- ✅ View logs
- ✅ Upgrade URF000 to newer version
- ✅ Rollback URF000 to previous version

#### 5. Systemd Integration
- ✅ Install systemd service for URF001
- ✅ Verify auto-start on boot
- ✅ Test `systemctl start/stop/status urfd-instance@urf001`

#### 6. Port Conflicts
- ✅ Deploy URF002 with same offset as URF001
- ✅ Verify validation catches port conflict
- ✅ Verify deployment aborted

#### 7. Version Validation
- ✅ Try to deploy with invalid version format
- ✅ Try to upgrade to non-existent version
- ✅ Verify semantic version enforcement

---

## Environment Variables Reference

### Instance Configuration
```bash
INSTANCE_NAME=urf000           # Instance identifier
CALLSIGN=URF000                # Reflector callsign
SYSOP_EMAIL=sysop@example.com  # Contact email
COUNTRY=US                      # Two-letter country code
SPONSOR="Your Organization"     # Sponsor name
DASHBOARD_URL=http://...        # Public dashboard URL
BOOTSTRAP_NODE=""               # DHT bootstrap (optional)
```

### Service Versions
```bash
URFD_VERSION=v1.8.0            # URFD image version
TCD_VERSION=v1.8.0             # TCD image version
DASHBOARD_VERSION=v1.8.0       # Dashboard image version
ALLSTAR_VERSION=v0.2.0         # AllStar Nexus version (if enabled)
```

### Port Configuration
```bash
PORT_OFFSET=0                   # Port offset (0, 100, 200, etc.)

# Calculated ports (auto-generated)
DASHBOARD_PORT=8080
ALLSTAR_PORT=8090
DEXTRA_PORT=30001
DPLUS_PORT=20001
DCS_PORT=30051
DMRPLUS_PORT=8880
MMDVM_PORT=62030
M17_PORT=17000
YSF_PORT=42000
P25_PORT=41000
NXDN_PORT=41400
URF_PORT=10017
G3_PORT=40000
```

### AllStar Nexus Configuration
```bash
ASTERISK_HOST=host.docker.internal  # Asterisk AMI host
AMI_PORT=5038                       # Asterisk AMI port
AMI_USERNAME=admin                  # AMI username
AMI_PASSWORD=secret                 # AMI password
```

---

## Outstanding Questions

Before implementation proceeds, these questions need answers:

1. **Default Instance Location**: Confirm `/opt/urfd-production/instances/` is the default, overridable via `URFD_INSTANCES_DIR` environment variable?
   - **Answer**: ___________

2. **Template Variable Format**: Should we use `${VARIABLE}` or `{{VARIABLE}}` for substitution? (`${VAR}` is bash-compatible, `{{VAR}}` is more template-esque)
   - **Answer**: ___________

3. **Config Template Iteration**: For the config templates, should I:
   - Create initial version with ~20 core fields per config
   - Add TODO comments where additional fields should be added later
   - Include link/reference to full source config examples?
   - **Answer**: ___________

4. **Systemd Service User**: Should the systemd service run as:
   - Root (typical for docker-compose)
   - Specific user (e.g., `urfd` user)
   - Current user who deployed the instance?
   - **Answer**: ___________

5. **Image Build Caching**: Should `build-images.sh` use Docker BuildKit and caching strategies, or keep it simple for now?
   - **Answer**: ___________

6. **Deployment Backup**: Should `deploy-instance.sh` backup any existing instance directory before overwriting, or fail if instance already exists?
   - **Answer**: ___________

7. **Image Versions Tracking**: Should `.image-versions` be:
   - Git-tracked (checked in to repo)
   - Git-ignored (local only)
   - **Answer**: ___________

---

## Implementation Status

- [ ] Phase 1: Foundation & Build System (5 files)
- [ ] Phase 2: Templates (7 files)
- [ ] Phase 3: Deployment Scripts (3 files)
- [ ] Phase 4: Management Tools (2 files)
- [ ] Phase 5: Documentation (2 files)
- [ ] Phase 6: Repository Configuration (2 files)

**Total Files**: 21

---

## Notes

- This plan prioritizes **simplicity** and **maintainability** over complexity
- Start with core functionality, iterate to add advanced features
- Config templates start with ~20 core fields, expand in future iterations
- All scripts use directory detection to work from anywhere
- Semantic versioning enforced throughout
- AllStar Nexus converted to bridge networking for multi-instance support

---

**Next Steps**: Answer outstanding questions, then proceed with implementation phase-by-phase.
