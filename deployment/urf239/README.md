# URF239 Deployment Guide

This directory contains the complete, self-contained configuration for deploying **URF239** on the `whocares` host.

## Goal

Deploy URF239 from a fresh repo clone **without local modifications** — only secrets and host-specific values need to be provided at deploy time.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Compose stack: `urf239-urfd`, `urf239-tcd`, `urf239-dashboard` |
| `config/production/urfd.ini` | URFD reflector config (+1 port offset, USRP enabled) |
| `config/production/tcd.ini` | Transcoder config (connects to URFD on 127.0.0.1:10101) |
| `config/dashboard/config.yaml` | Dashboard config (NNG via `host.docker.internal`) |

## Prerequisites

- Docker and Docker Compose installed on `whocares`
- Images `urfd`, `tcd`, `dashboard` built or pulled (tagged `latest` or explicit version)
- Host networking available (urfd and tcd use `network_mode: host`)

## Quick Deploy

```bash
# 1. Clone or pull the repo
git clone <repo-url> /tmp/urfd-tilt
cd /tmp/urfd-tilt

# 2. Copy URF239 deployment to target directory
mkdir -p /home/dbehnke/urf239
cp -r deployment/urf239/* /home/dbehnke/urf239/

# 3. Create required data directories
mkdir -p /home/dbehnke/urf239/data/logs
mkdir -p /home/dbehnke/urf239/data/audio
mkdir -p /home/dbehnke/urf239/data/dashboard

# 4. Set secrets (DO NOT commit these)
# Edit config/production/urfd.ini:
#   - SysopEmail
#   - Sponsor
#   - DashboardUrl
# Edit config/dashboard/config.yaml:
#   - transmit_password

# 5. Start the stack
cd /home/dbehnke/urf239
IMAGE_VERSION=latest docker compose -p urf239 up -d
```

## Networking Model

| Service | Network Mode | Notes |
|---------|-------------|-------|
| `urfd` | `host` | Binds all protocol ports directly on host |
| `tcd` | `host` | Connects to URFD transcoder on `127.0.0.1:10101` |
| `dashboard` | bridge | Publishes `8080:8080`, reaches URFD via `host.docker.internal` |

## Port Reference

See `deployment/URF239-PORTS.md` for the complete port listing.

Key ports:
- Dashboard HTTP: `8080/tcp`
- URFD NNG Dashboard: `5555/tcp`
- URFD NNG Voice audio: `5556/tcp`
- URFD NNG Voice control: `6556/tcp`
- URFD Dashboard control: `6001/tcp` (AllStar-Nexus registration)
- Transcoder: `10101/tcp`
- Protocol UDP ports: `30052`, `30002`, `20002`, `8881`, `17001`, `62031`, `41401`, `41001`, `10018`, `42001`
- USRP: `34001/udp` (RX), `32001/udp` (TX)

## Container Labels

All containers are labeled for filtering:

```bash
docker ps --filter 'label=com.dbehnke.urfd.instance=URF239'
```

## Verification

```bash
# Check containers
docker compose -p urf239 ps

# Check listening ports
ss -H -ltnup | grep -E ':(8080|5555|5556|6001|6556|10101)\b'
ss -H -lunp | grep -E ':(20002|30002|30052|8881|17001|62031|41401|41001|10018|34001|32001|42001)\b'

# Check logs
docker logs --tail 100 urf239-urfd
docker logs --tail 100 urf239-tcd
docker logs --tail 100 urf239-dashboard
```

## Rollback

```bash
cd /home/dbehnke/urf239
docker compose -p urf239 down
# Restore previous docker-compose.yml and configs if needed
docker compose -p urf239 up -d
```

## Updating Configs

1. Edit the relevant file in `config/`
2. Restart the affected service:
   ```bash
   docker compose -p urf239 restart urfd
   ```

## Relationship to Templates

This URF239 deployment is a **concrete instance** derived from the generic templates in `deployment/templates/`. Unlike the template system (which uses `envsubst` and `calculate-ports.sh` for arbitrary instances), this directory is pre-configured for URF239's specific requirements:

- +1 port offset (not `instance_num * 100`)
- Host networking for URFD/TCD
- USRP enabled with custom ports
- `host.docker.internal` for dashboard NNG

If you need to deploy a **different** URF instance, use the template system:

```bash
deployment/scripts/deploy-instance.sh URF042 v1.0.0
```
