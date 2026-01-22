# URF239 Production Branch & Upgrade Guide

## Branch Strategy Overview

This repository uses a **Git branch strategy** for managing URF239 production deployments:

- **`main`** branch: Development (URF000) with standard ports
- **`production/urf239`** branch: Production (URF239) with offset ports (+1)

This allows you to:
- ✅ Pull updates from `main` when new features are released
- ✅ Keep your URF239 production configs separate  
- ✅ Merge updates on your schedule
- ✅ Track all changes in Git

## Repository Structure

```
urfd-tilt/
├── docker-compose.yml              # Base configuration (URF000/dev)
├── docker-compose.prod.yml         # Production override (URF239)
├── config/
│   ├── local/                      # Dev configs (URF000) - gitignored
│   ├── production/                 # Production configs (URF239) - tracked
│   │   ├── urfd.ini               # URF239 main config
│   │   ├── tcd.ini                # URF239 transcoder config
│   │   ├── urfd.whitelist
│   │   ├── urfd.blacklist
│   │   └── ...
│   └── dashboard/
│       └── config.yaml             # Shared dashboard config
├── data/
│   ├── logs/                       # Dev runtime data - gitignored
│   ├── audio/
│   ├── dashboard/
│   └── production/                 # Production runtime data - gitignored
│       ├── logs/
│       ├── audio/
│       └── dashboard/
└── src/                            # Source code (shared)
```

## Initial Setup on Production VM

### 1. Clone and Setup

```bash
# Clone the repository
cd ~
git clone https://github.com/YOUR_USERNAME/urfd-tilt.git
cd urfd-tilt

# Create and switch to production branch
git checkout -b production/urf239

# Create production data directories (if they don't exist)
mkdir -p data/production/{logs,audio,dashboard}
mkdir -p config/production
```

### 2. Customize Production Config

```bash
# Edit URF239 configuration
nano config/production/urfd.ini
```

**Required changes:**
- Line 6: Your email
- Line 9: Your sponsor/organization
- Line 10: Your dashboard URL
- Lines 19-23: Module descriptions (optional)

```bash
# Verify TCD config
cat config/production/tcd.ini
```

Should show `Port=10101` (already correct)

### 3. Commit Production Config

```bash
# Add production configs to git
git add config/production/
git add docker-compose.prod.yml
git add data/production/.gitkeep

# Commit your production settings
git commit -m "chore: add URF239 production configuration"

# Push to your fork/remote (optional but recommended)
git push -u origin production/urf239
```

### 4. Build Docker Images

```bash
# Build all images
./docker/build-all.sh

# Or build individually
docker build -t urfd-common -f docker/urfd-common.Dockerfile .
docker build -t imbe-lib -f docker/imbe-lib.Dockerfile .
docker build -t md380-lib -f docker/md380-lib.Dockerfile .
docker build -t urfd -f docker/urfd.Dockerfile .
docker build -t tcd -f docker/tcd.Dockerfile .
docker build -t dashboard -f docker/dashboard.Dockerfile .
```

### 5. Start Production URF239

```bash
# Start with production override
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Check status
docker-compose -f docker-compose.yml -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
```

### 6. Create Convenience Alias (Optional)

```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'alias dc-prod="docker-compose -f docker-compose.yml -f docker-compose.prod.yml"' >> ~/.bashrc
source ~/.bashrc

# Now you can use:
dc-prod up -d
dc-prod logs -f
dc-prod restart
dc-prod down
```

## Upgrading URF239 from Main

When a new version of urfd-tilt is released on `main`, follow these steps to upgrade:

### Option A: Merge Updates (Recommended)

```bash
cd ~/urfd-tilt

# Make sure production is clean
git status
# If there are uncommitted changes, commit or stash them

# Fetch latest updates from main
git fetch origin main

# Review what's changed
git log --oneline production/urf239..origin/main

# Merge updates from main into production
git merge origin/main

# If there are conflicts (usually in config files):
# 1. Resolve them manually
# 2. Keep your production settings
# 3. Mark as resolved: git add <file>
# 4. Complete merge: git commit
```

### Option B: Rebase Updates (Alternative)

```bash
cd ~/urfd-tilt

# Fetch latest
git fetch origin main

# Rebase production on top of main
git rebase origin/main

# If conflicts, resolve and continue
git rebase --continue
```

### After Merging/Rebasing

```bash
# Review changes
git diff HEAD~1

# Rebuild Docker images (if source code changed)
./docker/build-all.sh

# Or rebuild specific images
docker build -t urfd -f docker/urfd.Dockerfile .
docker build -t tcd -f docker/tcd.Dockerfile .

# Restart with new images
dc-prod down
dc-prod up -d

# Monitor logs
dc-prod logs -f urfd239 tcd239

# Check health
dc-prod ps
docker logs urfd239 --tail 50
docker logs tcd239 --tail 50
```

### Handling Config Conflicts

If `config/production/urfd.ini` conflicts during merge:

```bash
# Keep your production version
git checkout --ours config/production/urfd.ini
git add config/production/urfd.ini

# Or manually edit to merge changes
nano config/production/urfd.ini
git add config/production/urfd.ini

# Complete merge
git commit
```

## Upgrade Checklist

- [ ] Check GitHub for new releases/tags
- [ ] Review changelog/commit messages
- [ ] Backup current configuration
  ```bash
  tar czf ~/urfd-backup-$(date +%Y%m%d).tar.gz ~/urfd-tilt/config/production ~/urfd-tilt/data/production
  ```
- [ ] Fetch latest from main: `git fetch origin main`
- [ ] Review changes: `git log production/urf239..origin/main`
- [ ] Merge updates: `git merge origin/main`
- [ ] Resolve any conflicts (keep production configs)
- [ ] Rebuild Docker images: `./docker/build-all.sh`
- [ ] Stop services: `dc-prod down`
- [ ] Start services: `dc-prod up -d`
- [ ] Verify logs: `dc-prod logs -f`
- [ ] Test connectivity (YSF, M17, P25, Dashboard)
- [ ] Monitor for 30 minutes
- [ ] Mark upgrade complete

## Rollback if Needed

If something goes wrong:

```bash
# Stop services
dc-prod down

# Go back to previous commit
git log --oneline  # Find previous commit hash
git reset --hard <previous-commit-hash>

# Or go back one commit
git reset --hard HEAD~1

# Rebuild with old version
./docker/build-all.sh

# Restart
dc-prod up -d
```

## Keeping in Sync

### Pull from Upstream (Original Repo)

If you forked urfd-tilt:

```bash
# Add upstream remote (one time)
git remote add upstream https://github.com/ORIGINAL_AUTHOR/urfd-tilt.git

# Fetch from upstream
git fetch upstream main

# Merge upstream changes
git checkout production/urf239
git merge upstream/main
```

### Push Production Branch (Backup)

```bash
# Push your production branch to your fork
git push origin production/urf239

# Now it's backed up on GitHub!
```

## Development vs Production

**Run Development (URF000):**
```bash
# Uses config/local/ and standard ports
docker-compose up -d
```

**Run Production (URF239):**
```bash
# Uses config/production/ and offset ports
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

**Can't run both simultaneously on same machine** (port conflicts)

## Common Commands

```bash
# Start production
dc-prod up -d

# Stop production
dc-prod down

# Restart production
dc-prod restart

# View logs (all services)
dc-prod logs -f

# View specific service logs
docker logs -f urfd239
docker logs -f tcd239
docker logs -f dashboard239

# Check status
dc-prod ps

# Pull latest main
git fetch origin main

# Merge updates
git merge origin/main

# Rebuild images
./docker/build-all.sh

# Backup
tar czf ~/backup-$(date +%Y%m%d).tar.gz config/production data/production
```

## Troubleshooting Upgrades

**Merge conflicts:**
```bash
# See conflicted files
git status

# Resolve conflicts
nano config/production/urfd.ini

# Mark resolved
git add config/production/urfd.ini

# Complete merge
git commit
```

**Build failures:**
```bash
# Clean Docker cache
docker system prune -a

# Rebuild without cache
docker build --no-cache -t urfd -f docker/urfd.Dockerfile .
```

**Services won't start:**
```bash
# Check logs
dc-prod logs

# Verify config syntax
grep -E "^[A-Z]" config/production/urfd.ini

# Test port availability
sudo netstat -tulpn | grep -E '17001|42001|8081'
```

## AllStar-Nexus Integration (USRP)

URF239 production deployment includes **AllStar-Nexus** integration for connecting AllStarLink nodes via USRP protocol.

### Architecture Overview

```
┌─────────────────┐       ┌──────────────────┐       ┌─────────────────┐
│ AllStar Node    │       │  AllStar-Nexus   │       │  URF239 (URFD)  │
│ (Asterisk)      │◄─────►│  (Host Network)  │◄─────►│  (Host Network) │
│                 │  AMI  │                  │  NNG  │                 │
│ 127.0.0.1:XXXX  │       │  Port 8090       │ 6001  │  USRP Enabled   │
└─────────────────┘       └──────────────────┘       └─────────────────┘
```

### Key Features

- **USRP Protocol**: Enabled in URF239 for AllStarLink communication
- **Dynamic Registration**: AllStar-Nexus registers nodes via NNG Control Channel
- **Host Networking**: URFD runs with `network_mode: host` for direct NNG access
- **IP-to-Callsign Mapping**: AllStar-Nexus sends callsign registration before transmission

### NNG Port Configuration

URF239 uses three NNG sockets for different purposes:

| Socket Type | Port | Purpose | Protocol |
|-------------|------|---------|----------|
| **Dashboard PUB** | 5555 | Publish reflector events to dashboard | PUB/SUB |
| **Voice PAIR** | 5556 | Bidirectional voice streaming | PAIR |
| **Control REP** | 6001 | AllStar-Nexus registration commands | REQ/REP |

### URFD Configuration

The production `config/production/urfd.ini` includes:

```ini
[USRP]
Enable = true
Callsign = ALLSTAR
IPAddress = 172.17.0.1  # Docker host gateway (or AllStar-Nexus IP)

[Dashboard]
ControlNNGEnable = true
ControlNNGAddr = tcp://0.0.0.0:6001  # Control socket for USRP registration
```

### Host Networking Mode

URF239 containers use **host networking** to access AllStar-Nexus on the host:

```yaml
# docker-compose.prod.yml
services:
  urfd:
    network_mode: host  # Direct access to host network for NNG/USRP
  
  tcd:
    network_mode: service:urfd  # Shares URFD's host network
  
  dashboard:
    extra_hosts:
      - "host.docker.internal:host-gateway"  # Connects to URFD via host
```

### AllStar-Nexus Registration Flow

When an AllStar node transmits:

1. **Node Keys Up** → AllStar sends AMI event to AllStar-Nexus
2. **Extract Info** → AllStar-Nexus extracts IP address and callsign
3. **NNG Registration** → AllStar-Nexus sends to URFD:
   ```json
   {
     "cmd": "usrp_register",
     "ip": "127.0.0.1",
     "callsign": "W1AW"
   }
   ```
4. **Force Reset** → URFD closes existing stream from that IP
5. **Reconnect** → AllStar node automatically reconnects
6. **Mapped** → URFD associates IP with callsign, audio flows correctly

### AllStar-Nexus Setup

AllStar-Nexus runs **directly on the host** (NOT in Docker):

```bash
# Install AllStar-Nexus on host
cd /opt
git clone https://github.com/dbehnke/allstar-nexus.git
cd allstar-nexus
go build -o allstar-nexus .

# Configure AllStar-Nexus
nano config.yaml
```

**Required config.yaml settings:**

```yaml
server:
  addr: ":8090"
  
asterisk:
  host: "127.0.0.1:5038"  # AllStar AMI
  username: "admin"
  password: "YOUR_AMI_PASSWORD"
  
urfd:
  nng_control_addr: "tcp://127.0.0.1:6001"  # URF239 Control socket
  usrp_callsign: "ALLSTAR"
```

### Firewall Configuration

Ensure these ports are accessible:

```bash
# AllStar USRP (if external nodes connect)
sudo ufw allow 32000:34000/udp

# URF239 Dashboard
sudo ufw allow 8081/tcp

# AllStar-Nexus Web UI (optional)
sudo ufw allow 8090/tcp

# YSF, M17, P25, NXDN (if used)
sudo ufw allow 42001/udp
sudo ufw allow 17001/udp
sudo ufw allow 41001/udp
sudo ufw allow 41401/udp
```

### Testing AllStar Integration

```bash
# 1. Start URF239
dc-prod up -d

# 2. Verify NNG Control socket is listening
sudo netstat -tulpn | grep 6001
# Should show: tcp  0  0  0.0.0.0:6001  0.0.0.0:*  LISTEN

# 3. Start AllStar-Nexus (on host)
cd /opt/allstar-nexus
./allstar-nexus

# 4. Monitor URFD logs for registration
docker logs -f urfd239 | grep -E "NNG Control|USRP|registered"

# Expected output when node keys up:
# NNG Control: Registered W1AW at 127.0.0.1
# USRP: Force closing stream for 127.0.0.1 to update callsign to W1AW
```

### Troubleshooting AllStar Integration

**Problem: AllStar-Nexus can't connect to URFD**

```bash
# Check if URFD Control socket is listening
docker logs urfd239 | grep "NNG Control"
# Should show: NNG Control: Listening at tcp://0.0.0.0:6001

# Test connection from host
telnet localhost 6001
```

**Problem: USRP audio not reaching reflector**

```bash
# Verify USRP is enabled
docker exec urfd239 grep -A 3 "^\[USRP\]" /usr/local/etc/urfd/urfd.ini

# Check USRP client connections
docker logs urfd239 | grep USRP

# Verify IPAddress matches AllStar-Nexus or node IP
```

**Problem: Host networking conflicts**

```bash
# Check port conflicts
sudo netstat -tulpn | grep -E '5555|5556|6001|17001|42001'

# If ports are in use, stop conflicting services
sudo systemctl stop <conflicting-service>

# Restart URF239
dc-prod restart
```

### AllStar-Nexus Documentation

For complete AllStar-Nexus setup, see:
- `src/allstar-nexus/README.md` - Full setup guide
- `src/urfd/docs/nng_control.md` - NNG Control protocol details
- `src/urfd/docs/architecture.md` - URFD architecture overview

## Questions?

- Review logs: `dc-prod logs`
- Check GitHub issues
- Verify config files are correct
- Test network connectivity

---

**You're all set for easy upgrades!** 🚀

Just remember:
1. `git fetch origin main` - Get updates
2. `git merge origin/main` - Merge them
3. `./docker/build-all.sh` - Rebuild images
4. `dc-prod restart` - Apply changes
