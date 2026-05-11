# URF259 Deployment Guide

This directory contains the complete, self-contained configuration for deploying **URF259** on the `whocares` host.

## Goal

Deploy URF259 from a fresh repo clone **without local modifications** — only secrets and host-specific values need to be provided at deploy time.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Compose stack: `urf259-urfd`, `urf259-tcd`, `urf259-dashboard` |
| `config/production/urfd.ini` | URFD reflector config (+2 port offset, single module A, USRP enabled) |
| `config/production/tcd.ini` | Transcoder config (connects to URFD on 127.0.0.1:10102) |
| `config/dashboard/config.yaml` | Dashboard config (NNG via `host.docker.internal`, port 6544) |

## Prerequisites

- Docker and Docker Compose installed on `whocares`
- Images `urfd`, `tcd`, `dashboard` built or pulled (tagged `latest` or explicit version)
- Host networking available (urfd and tcd use `network_mode: host`)

## Quick Deploy

```bash
# 1. Clone or pull the repo
git clone <repo-url> /tmp/urfd-tilt
cd /tmp/urfd-tilt

# 2. Copy URF259 deployment to target directory
mkdir -p /home/dbehnke/urf259
cp -r deployment/urf259/* /home/dbehnke/urf259/

# 3. Create required data directories
mkdir -p /home/dbehnke/urf259/data/logs
mkdir -p /home/dbehnke/urf259/data/audio
mkdir -p /home/dbehnke/urf259/data/dashboard

# 4. Set secrets (DO NOT commit these)
# Edit config/production/urfd.ini:
#   - SysopEmail (if different from default)
# Edit config/dashboard/config.yaml:
#   - qrz_username
#   - qrz_password

# 5. Start the stack
cd /home/dbehnke/urf259
IMAGE_VERSION=latest docker compose -p urf259 up -d
```

## Networking Model

| Service | Network Mode | Notes |
|---------|-------------|-------|
| `urfd` | `host` | Binds all protocol ports directly on host |
| `tcd` | `host` | Connects to URFD transcoder on `127.0.0.1:10102` |
| `dashboard` | bridge | Publishes `6544:6544`, reaches URFD via `host.docker.internal` |

## Port Reference

Key ports (all +2 offset from standard):
- Dashboard HTTP: `6544/tcp`
- URFD NNG Dashboard: `55552/tcp`
- Transcoder: `10102/tcp`
- Protocol UDP ports: `30052`, `30002`, `20002`, `8882`, `17002`, `62032`, `41402`, `41002`, `10012`, `42002`
- USRP: `34002/udp` (RX), `32002/udp` (TX)

## Upgrade from Zombie Containers

The current URF259 runs as the `zombie` Compose project with `urfd-combined` image.

### Pre-upgrade checklist

1. **Backup current state:**
   ```bash
   ssh whocares
   cd /home/dbehnke/urfd-docker/zombie
   mkdir -p backups/$(date +%Y%m%d-%H%M%S)
   cp docker-compose.yml backups/$(date +%Y%m%d-%H%M%S)/
   docker compose -p zombie ps > backups/$(date +%Y%m%d-%H%M%S)/compose-ps.txt
   ```

2. **Verify new images exist:**
   ```bash
   docker images | grep -E '^(urfd|tcd|dashboard)'
   ```

3. **Copy new configs:**
   ```bash
   mkdir -p /home/dbehnke/urf259
   cp -r deployment/urf259/* /home/dbehnke/urf259/
   # Edit secrets in config files
   ```

### Cutover procedure

```bash
cd /home/dbehnke/urf259
IMAGE_VERSION=latest docker compose -p urf259 up -d
```

Verify new containers are healthy, then stop old zombie project:

```bash
cd /home/dbehnke/urfd-docker/zombie
docker compose -p zombie down
```

### Rollback

If the new deployment fails:

```bash
cd /home/dbehnke/urf259
docker compose -p urf259 down
cd /home/dbehnke/urfd-docker/zombie
docker compose -p zombie up -d
```

## Container Labels

All containers are labeled for filtering:

```bash
docker ps --filter 'label=com.dbehnke.urfd.instance=URF259'
```

## Verification

```bash
# Check containers
docker compose -p urf259 ps

# Check listening ports
ss -H -ltnup | grep -E ':(6544|55552|10102)\b'
ss -H -lunp | grep -E ':(20002|30002|30052|8882|17002|62032|41402|41002|10012|42002)\b'

# Check logs
docker logs --tail 100 urf259-urfd
docker logs --tail 100 urf259-tcd
docker logs --tail 100 urf259-dashboard
```

## Updating Configs

1. Edit the relevant file in `config/`
2. Restart the affected service:
   ```bash
   docker compose -p urf259 restart urfd
   ```

## Differences from URF239

| Feature | URF239 | URF259 |
|---------|--------|--------|
| Modules | ADMSZ | A only |
| Port offset | +1 | +2 |
| Dashboard port | 8080 | 6544 |
| NNG port | 5555 | 55552 |
| Transcoder | 10101 | 10102 |
| DMR maps | None | MapA=7001, MapB=7002, MapC=7003 |
| Callbook | None | QRZ configured (secrets local-only) |
| IPv4External | Not set | 67.220.71.98 |
| Image | Separate urfd/tcd/dashboard | urfd-combined (legacy) → separate |

## Relationship to Templates

This URF259 deployment is a **concrete instance** derived from the generic templates in `deployment/templates/`. Unlike the template system (which uses `envsubst` and `calculate-ports.sh` for arbitrary instances), this directory is pre-configured for URF259's specific requirements:

- +2 port offset
- Host networking for URFD/TCD
- Single module (A) with DMR mapping
- Dashboard on non-standard port 6544
- QRZ callbook support (credentials excluded from repo)
