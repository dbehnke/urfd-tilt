# URFD Production Deployment Guide

This directory contains tools for building, deploying, and managing production URFD instances with proper isolation, port management, and systemd integration.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Building Images](#building-images)
- [Deploying Instances](#deploying-instances)
- [Managing Instances](#managing-instances)
- [Upgrading Instances](#upgrading-instances)
- [Multi-Instance Deployment](#multi-instance-deployment)
- [Port Reference](#port-reference)
- [Configuration Details](#configuration-details)
- [Systemd Integration](#systemd-integration)
- [Troubleshooting](#troubleshooting)

## Overview

The URFD production deployment system enables you to:

- **Build versioned Docker images** for all URFD components (urfd, tcd, dashboard, allstar-nexus)
- **Deploy multiple isolated instances** on a single server with automatic port management
- **Manage instance lifecycle** (start, stop, restart, status, logs)
- **Upgrade instances** safely with automatic backups and validation
- **Integrate with systemd** for automatic startup and management

### Architecture

Each URFD instance includes:
- **urfd**: Main reflector application
- **tcd**: Transcoder service
- **dashboard**: Web-based monitoring interface
- **allstar-nexus** (optional): AllStar network bridge

Instances are isolated using Docker Compose with bridge networking and unique port offsets.

## Quick Start

```bash
# 1. Build Docker images
cd deployment/build
./build-images.sh v1.0.0

# 2. Deploy your first instance
cd ../scripts
./deploy-instance.sh URF000 v1.0.0 --systemd --start

# 3. Check status
./manage-instance.sh URF000 status

# 4. View logs
./manage-instance.sh URF000 logs

# 5. Access dashboard
# Open http://your-server:10080 in browser
```

## Prerequisites

### System Requirements

- **Operating System**: Linux (tested on Ubuntu 20.04+, Debian 11+)
- **Docker**: Version 20.10 or later
- **Docker Compose**: Version 2.0 or later (V2 plugin recommended)
- **Bash**: Version 4.0 or later (for cleanup script)
- **Git**: For managing submodules
- **Root Access**: Required for systemd integration

### Required Tools

```bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install additional tools
sudo apt-get update
sudo apt-get install -y git gettext-base jq

# Verify installations
docker --version
docker compose version
bash --version
```

### Directory Setup

By default, instances are deployed to `/opt/urfd-production/instances/`. You can override this with the `URFD_INSTANCES_DIR` environment variable.

```bash
# Create instance directory (default location)
sudo mkdir -p /opt/urfd-production/instances
sudo chown $USER:$USER /opt/urfd-production/instances

# Or use custom location
export URFD_INSTANCES_DIR=/home/urfd/instances
mkdir -p $URFD_INSTANCES_DIR
```

## Building Images

### Build All Images

```bash
cd deployment/build
./build-images.sh <version>
```

**Version format**: `v1.2.3` or `v1.2.3-beta1`

Example:
```bash
./build-images.sh v1.0.0
./build-images.sh v1.1.0-rc1
```

This builds 7 Docker images:
1. `urfd-base` - Base image with common dependencies
2. `urfd` - Main reflector
3. `tcd` - Transcoder
4. `dashboard-base` - Dashboard base image
5. `dashboard-client` - Dashboard frontend
6. `dashboard-server` - Dashboard backend
7. `allstar-nexus` - AllStar bridge (optional)

Build metadata is stored in `deployment/build/.image-versions`.

### List Available Images

```bash
./list-images.sh
```

Shows:
- Built versions from `.image-versions`
- Available Docker image tags
- Running instances and their versions

### Cleanup Old Images

```bash
# Dry run (recommended first)
./cleanup-images.sh

# Keep last 3 versions (default)
./cleanup-images.sh --execute

# Keep last 5 versions
./cleanup-images.sh --keep 5 --execute
```

**Safety features**:
- Dry-run mode by default (`--execute` required for actual deletion)
- Protects images used by running instances
- Keeps N most recent versions
- Requires bash 4+ for associative arrays

## Deploying Instances

### Deploy a New Instance

```bash
cd deployment/scripts
./deploy-instance.sh <instance-name> <version> [options]
```

**Instance naming**: Must match pattern `URF[0-9]{3}` (e.g., URF000, URF001, URF999)

**Options**:
- `--systemd` - Install systemd service
- `--start` - Start instance after deployment
- `--skip-validation` - Skip configuration validation
- `--instances-dir <path>` - Override instance directory

### Basic Deployment

```bash
./deploy-instance.sh URF000 v1.0.0
```

Creates:
```
/opt/urfd-production/instances/URF000/
├── .env                          # Environment variables
├── docker-compose.yml            # Docker Compose configuration
├── configs/
│   ├── urfd.ini                  # URFD configuration
│   ├── tcd.ini                   # Transcoder configuration
│   ├── dashboard.yaml            # Dashboard configuration
│   └── allstar-nexus.yaml        # AllStar Nexus configuration
├── logs/                         # Application logs
└── data/                         # Database files
```

### Full Deployment with Systemd

```bash
./deploy-instance.sh URF000 v1.0.0 --systemd --start
```

Creates instance + installs systemd service + starts instance.

### Customize Configuration

After deployment, edit the configuration files:

```bash
cd /opt/urfd-production/instances/URF000

# Edit environment variables
nano .env

# Edit URFD configuration
nano configs/urfd.ini

# Edit transcoder settings
nano configs/tcd.ini

# Edit dashboard configuration
nano configs/dashboard.yaml

# Apply changes
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 restart
```

**Important**: After editing `.env`, regenerate config files:
```bash
cd /opt/urfd-production/instances/URF000
source .env
envsubst < configs/urfd.ini > configs/urfd.ini.tmp && mv configs/urfd.ini.tmp configs/urfd.ini
# Repeat for other config files or redeploy
```

## Managing Instances

The `manage-instance.sh` script provides comprehensive instance management.

### Start/Stop/Restart

```bash
./manage-instance.sh URF000 start
./manage-instance.sh URF000 stop
./manage-instance.sh URF000 restart
```

### Check Status

```bash
./manage-instance.sh URF000 status
```

Shows:
- Container status and uptime
- Resource usage (CPU, memory, network)
- Key configuration settings
- Port mappings

### View Logs

```bash
# Follow logs (Ctrl+C to exit)
./manage-instance.sh URF000 logs

# Show last 100 lines
./manage-instance.sh URF000 logs-tail

# Show last 50 lines
./manage-instance.sh URF000 logs-tail 50

# View specific service logs
cd /opt/urfd-production/instances/URF000
docker compose logs -f urfd
docker compose logs -f tcd
docker compose logs -f dashboard
```

### Show Running Containers

```bash
./manage-instance.sh URF000 ps
```

### Execute Commands

```bash
# Run single command
./manage-instance.sh URF000 exec ls -la /app

# Open interactive shell
./manage-instance.sh URF000 shell
```

### Validate Configuration

```bash
./manage-instance.sh URF000 validate
```

Performs 8 validation checks:
1. Directory structure
2. Configuration file existence
3. Environment variable validation
4. Port range validation
5. Docker Compose syntax
6. Port conflict detection
7. File permissions
8. Docker image availability

### Show Instance Info

```bash
./manage-instance.sh URF000 info
```

Shows complete instance details:
- Instance identification
- Version and image info
- Port mappings (all 16 ports)
- Configuration summary
- File locations

### Pull Latest Images

```bash
./manage-instance.sh URF000 pull
```

Updates Docker images to latest version (respects version tag in `.env`).

## Upgrading Instances

### Upgrade to New Version

```bash
cd deployment/scripts
./upgrade-instance.sh <instance-name> <new-version> [options]
```

**Options**:
- `--auto-restart` - Restart instance after upgrade
- `--no-backup` - Skip automatic backup
- `--skip-validation` - Skip configuration validation
- `--instances-dir <path>` - Override instance directory

### Standard Upgrade

```bash
# Build new version first
cd ../build
./build-images.sh v1.1.0

# Upgrade instance
cd ../scripts
./upgrade-instance.sh URF000 v1.1.0 --auto-restart
```

**Upgrade process**:
1. Validates instance exists and version format
2. Checks Docker image availability
3. Creates automatic backup (`.backups/backup-YYYYMMDD-HHMMSS/`)
4. Updates `.env` with new version
5. Regenerates config files from templates
6. Validates upgraded configuration
7. Optionally restarts instance

### Manual Restart After Upgrade

```bash
./upgrade-instance.sh URF000 v1.1.0

# Review changes, then restart
./manage-instance.sh URF000 restart
```

### Rollback After Upgrade

If upgrade fails, rollback using the automatic backup:

```bash
cd /opt/urfd-production/instances/URF000

# List backups
ls -la .backups/

# Restore from backup
cp -r .backups/backup-20260121-143022/.env .env
cp -r .backups/backup-20260121-143022/configs/* configs/

# Restart with old version
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 restart
```

## Multi-Instance Deployment

Deploy multiple isolated instances on a single server.

### Port Offset Calculation

Each instance uses a unique port offset based on instance number:

**Formula**: `OFFSET = INSTANCE_NUMBER × 100`

Examples:
- URF000 → offset 0 → ports start at base values
- URF001 → offset 100 → ports +100
- URF002 → offset 200 → ports +200

### Deploy Multiple Instances

```bash
cd deployment/scripts

# Deploy first instance (URF000)
./deploy-instance.sh URF000 v1.0.0 --systemd --start

# Deploy second instance (URF001)
./deploy-instance.sh URF001 v1.0.0 --systemd --start

# Deploy third instance (URF002)
./deploy-instance.sh URF002 v1.0.0 --systemd --start
```

### View All Instances

```bash
# List running containers
docker ps --filter "name=urf"

# Check systemd services
systemctl list-units "urfd-instance@*"

# View specific instance
systemctl status urfd-instance@URF001
```

### Manage Multiple Instances

```bash
# Start all instances
for i in URF000 URF001 URF002; do
    ./manage-instance.sh $i start
done

# Check status of all instances
for i in URF000 URF001 URF002; do
    echo "=== $i ==="
    ./manage-instance.sh $i status
    echo
done

# Stop all instances
for i in URF000 URF001 URF002; do
    ./manage-instance.sh $i stop
done
```

## Port Reference

### Base Ports (URF000, offset 0)

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| Dashboard HTTP | 10080 | TCP | Web interface |
| Dashboard HTTPS | 10443 | TCP | Secure web interface |
| AMI | 5038 | TCP | Asterisk Manager Interface |
| DExtra | 30001 | UDP | DExtra protocol |
| DPlus | 20001 | UDP | DPlus protocol |
| DCS | 30051 | UDP | DCS protocol |
| DMR | 8880 | UDP | DMR protocol |
| DMRPlus | 8880 | UDP | DMRPlus protocol (same as DMR) |
| NXDN | 41400 | UDP | NXDN protocol |
| P25 | 41000 | UDP | P25 protocol |
| YSF | 42000 | UDP | YSF protocol |
| M17 | 17000 | UDP | M17 protocol |
| URF | 10017 | UDP | URF protocol |
| Inter-linking | 10018 | UDP | Inter-reflector linking |

### Port Calculation for Other Instances

**URF001** (offset +100):
- Dashboard HTTP: 10180
- Dashboard HTTPS: 10543
- DExtra: 30101
- DPlus: 20101
- etc.

**URF002** (offset +200):
- Dashboard HTTP: 10280
- Dashboard HTTPS: 10643
- DExtra: 30201
- DPlus: 20201
- etc.

### Verify Port Assignments

```bash
./manage-instance.sh URF001 info | grep -A 20 "Port Mappings"
```

## Configuration Details

### Environment Variables (.env)

The `.env` file contains ~50 configuration variables organized into sections:

**Instance Identification**:
- `INSTANCE_NAME` - Instance identifier (e.g., URF000)
- `INSTANCE_DIR` - Instance directory path
- `IMAGE_VERSION` - Docker image version

**Port Mappings** (16 ports):
- `DASHBOARD_HTTP_PORT`, `DASHBOARD_HTTPS_PORT`
- `AMI_PORT`
- Protocol ports: `DEXTRA_PORT`, `DPLUS_PORT`, `DCS_PORT`, `DMR_PORT`, etc.

**Reflector Configuration**:
- `REFLECTOR_CALLSIGN` - Your callsign (e.g., W1ABC)
- `REFLECTOR_EMAIL` - Contact email
- `REFLECTOR_COUNTRY` - Country name
- `REFLECTOR_SPONSOR` - Sponsor/operator name
- `REFLECTOR_MODULES` - Enabled modules (e.g., ABCD)
- Protocol enable flags: `ENABLE_DEXTRA`, `ENABLE_DPLUS`, etc.

**Transcoder Settings**:
- Audio gain adjustments for different modes
- AGC (Automatic Gain Control) settings

**Dashboard Configuration**:
- Server settings
- Voice feature flags
- Recording settings

**Database Settings**:
- User database URL and refresh interval
- NXDN/DMR/P25/M17 database URLs and intervals

### Configuration Templates

Templates are in `deployment/templates/configs/`:
- `urfd.ini.template` - URFD reflector configuration
- `tcd.ini.template` - Transcoder configuration
- `dashboard.yaml.template` - Dashboard configuration
- `allstar-nexus.yaml.template` - AllStar Nexus configuration

Templates use bash variable substitution (`${VARIABLE}` format) and are processed during deployment.

### Regenerate Configurations

After modifying `.env`:

```bash
cd /opt/urfd-production/instances/URF000
source .env

# Process templates
for template in /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/templates/configs/*.template; do
    filename=$(basename "$template" .template)
    envsubst < "$template" > "configs/$filename"
done

# Restart to apply
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 restart
```

Or redeploy the instance (preserves data and logs):
```bash
# Backup current config
cp .env .env.backup

# Redeploy
./deploy-instance.sh URF000 v1.0.0

# Restore custom settings
# (merge .env.backup changes into new .env)
```

## Systemd Integration

### Install Systemd Service

```bash
# During deployment
./deploy-instance.sh URF000 v1.0.0 --systemd

# Or manually after deployment
cd /opt/urfd-production/instances/URF000
sudo cp /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/templates/systemd/urfd-instance@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable urfd-instance@URF000
```

### Manage via Systemd

```bash
# Start instance
sudo systemctl start urfd-instance@URF000

# Stop instance
sudo systemctl stop urfd-instance@URF000

# Restart instance
sudo systemctl restart urfd-instance@URF000

# Check status
sudo systemctl status urfd-instance@URF000

# View logs
sudo journalctl -u urfd-instance@URF000 -f

# Enable automatic startup
sudo systemctl enable urfd-instance@URF000

# Disable automatic startup
sudo systemctl disable urfd-instance@URF000
```

### Reload Configuration

When configuration files change:

```bash
sudo systemctl reload urfd-instance@URF000
```

This runs `docker compose up -d` to apply changes without full restart.

### Systemd Service Details

The systemd service template (`urfd-instance@.service`):
- **Type**: oneshot with RemainAfterExit
- **User**: root (required for Docker)
- **Working Directory**: `/opt/urfd-production/instances/%i`
- **Start**: `docker compose up -d`
- **Stop**: `docker compose down`
- **Reload**: `docker compose up -d`
- **Security**: ProtectSystem=strict, ProtectHome=true, NoNewPrivileges=true

## Troubleshooting

### Instance Won't Start

**Check logs**:
```bash
./manage-instance.sh URF000 logs-tail
```

**Common issues**:
1. **Port conflicts**: Another service using the same port
   ```bash
   # Check what's using a port
   sudo lsof -i :10080
   
   # Kill conflicting process or change port in .env
   ```

2. **Missing Docker images**: Image not built
   ```bash
   # Verify image exists
   docker images | grep urfd
   
   # Build if missing
   cd deployment/build
   ./build-images.sh v1.0.0
   ```

3. **Permission issues**: Can't access instance directory
   ```bash
   # Fix permissions
   sudo chown -R $USER:$USER /opt/urfd-production/instances/URF000
   ```

4. **Invalid configuration**: Syntax errors in config files
   ```bash
   # Validate configuration
   ./validate-instance.sh URF000
   
   # Check Docker Compose syntax
   cd /opt/urfd-production/instances/URF000
   docker compose config
   ```

### Validation Failures

```bash
# Run full validation
./validate-instance.sh URF000

# Check specific issues
cd /opt/urfd-production/instances/URF000

# Verify .env file
cat .env | grep -v '^#' | grep -v '^$'

# Test Docker Compose
docker compose config

# Check port conflicts
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Container Health Issues

```bash
# Check container status
./manage-instance.sh URF000 ps

# View resource usage
docker stats urf000-urfd-1 urf000-tcd-1 urf000-dashboard-1

# Inspect container
docker inspect urf000-urfd-1

# Check container logs
docker logs urf000-urfd-1

# Restart unhealthy container
docker restart urf000-urfd-1
```

### Network Connectivity

**Dashboard not accessible**:
```bash
# Check if dashboard is running
curl http://localhost:10080

# Check firewall
sudo ufw status
sudo ufw allow 10080/tcp

# Check Docker network
docker network inspect urf000_default
```

**Reflector not receiving connections**:
```bash
# Verify UDP ports are open
sudo ufw allow 30001/udp  # DExtra
sudo ufw allow 20001/udp  # DPlus
sudo ufw allow 30051/udp  # DCS
# etc.

# Test port connectivity
nc -u -l -p 30001  # Listen on DExtra port
```

### Upgrade Problems

**Upgrade failed - rollback**:
```bash
cd /opt/urfd-production/instances/URF000

# Find backup
ls -la .backups/

# Restore
cp -r .backups/backup-20260121-143022/* .

# Restart
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 restart
```

**Configuration mismatch after upgrade**:
```bash
# Regenerate configs from templates
cd /opt/urfd-production/instances/URF000
source .env

for template in /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/templates/configs/*.template; do
    filename=$(basename "$template" .template)
    envsubst < "$template" > "configs/$filename"
done

./manage-instance.sh URF000 restart
```

### Database Issues

**Database not updating**:
```bash
# Check database URLs in .env
grep DATABASE /opt/urfd-production/instances/URF000/.env

# Manually trigger refresh (restart reflector)
./manage-instance.sh URF000 restart

# Check logs for database errors
./manage-instance.sh URF000 logs | grep -i database
```

### Disk Space

**Instance using too much disk**:
```bash
# Check disk usage
du -sh /opt/urfd-production/instances/*
du -sh /opt/urfd-production/instances/URF000/*

# Clean up logs
cd /opt/urfd-production/instances/URF000
docker compose down
rm -rf logs/*
docker compose up -d

# Clean up old backups
rm -rf .backups/backup-202601*

# Prune Docker resources
docker system prune -a
```

### Getting Help

**Enable debug logging**:
```bash
# Edit .env
cd /opt/urfd-production/instances/URF000
nano .env

# Set log level
LOG_LEVEL=debug

# Restart
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 restart
```

**Collect diagnostic information**:
```bash
# System info
docker version
docker compose version
uname -a

# Instance info
./manage-instance.sh URF000 info
./manage-instance.sh URF000 status

# Recent logs
./manage-instance.sh URF000 logs-tail 200 > /tmp/urfd-debug.log
```

**Check project documentation**:
- Main README: `/Users/dbehnke/development/urfd-dev/urfd-tilt/README.md`
- Deployment plan: `.opencode/plans/production-deployment.md`

## Advanced Topics

### Custom Instance Directories

```bash
# Use custom location
export URFD_INSTANCES_DIR=/home/urfd/instances

# Deploy to custom location
./deploy-instance.sh URF000 v1.0.0 --instances-dir /home/urfd/instances

# Manage instance in custom location
./manage-instance.sh URF000 status --instances-dir /home/urfd/instances
```

### Monitoring and Alerting

**Integration with monitoring systems**:

```bash
# Health check endpoint
curl http://localhost:10080/api/health

# Export metrics
curl http://localhost:10080/api/metrics

# Monitor via systemd
sudo systemctl status urfd-instance@URF000

# Email alerts on failure
sudo systemctl edit urfd-instance@URF000
# Add:
# [Unit]
# OnFailure=status-email@%i.service
```

### Backup and Restore

**Manual backup**:
```bash
cd /opt/urfd-production/instances
tar czf URF000-backup-$(date +%Y%m%d).tar.gz URF000/
```

**Automated backups**:
```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * cd /opt/urfd-production/instances && tar czf /backups/URF000-$(date +\%Y\%m\%d).tar.gz URF000/
```

**Restore from backup**:
```bash
cd /opt/urfd-production/instances
tar xzf /backups/URF000-20260121.tar.gz
cd /Users/dbehnke/development/urfd-dev/urfd-tilt/deployment/scripts
./manage-instance.sh URF000 start
```

### Performance Tuning

**Resource limits**:
```bash
# Edit docker-compose.yml
cd /opt/urfd-production/instances/URF000
nano docker-compose.yml

# Add under services.urfd:
#     deploy:
#       resources:
#         limits:
#           cpus: '2.0'
#           memory: 2G
#         reservations:
#           cpus: '1.0'
#           memory: 512M

# Restart
docker compose up -d
```

**Log rotation**:
```bash
# Configure Docker log rotation
nano docker-compose.yml

# Under services.urfd.logging:
#     driver: "json-file"
#     options:
#       max-size: "10m"
#       max-file: "3"
```

---

## Quick Reference

### Common Commands

```bash
# Build images
cd deployment/build && ./build-images.sh v1.0.0

# Deploy instance
cd deployment/scripts && ./deploy-instance.sh URF000 v1.0.0 --systemd --start

# Check status
./manage-instance.sh URF000 status

# View logs
./manage-instance.sh URF000 logs

# Restart instance
./manage-instance.sh URF000 restart

# Upgrade instance
./upgrade-instance.sh URF000 v1.1.0 --auto-restart

# Validate configuration
./validate-instance.sh URF000

# Access dashboard
# http://your-server:10080
```

### File Locations

- **Scripts**: `deployment/scripts/`
- **Templates**: `deployment/templates/`
- **Build tools**: `deployment/build/`
- **Instances**: `/opt/urfd-production/instances/` (default)
- **Systemd service**: `/etc/systemd/system/urfd-instance@.service`

### Support

For issues, questions, or contributions, refer to the main project repository and documentation.
