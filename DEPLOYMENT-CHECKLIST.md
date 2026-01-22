# URF239 Production Deployment Checklist

## Pre-Deployment Preparation

### System Requirements
- [ ] VM or dedicated server running Linux (Ubuntu 22.04+ recommended)
- [ ] Docker installed (version 20.10+)
- [ ] Docker Compose installed (version 2.0+)
- [ ] Git installed
- [ ] Tailscale installed and configured (if using Tailscale tunnel)
- [ ] Minimum 2 CPU cores, 4GB RAM, 20GB disk space
- [ ] Root or sudo access

### Network Requirements
- [ ] Static IP or Tailscale IP configured
- [ ] Firewall rules configured (see Port Configuration below)
- [ ] Domain/subdomain pointing to server (for dashboard)
- [ ] Port forwarding configured if behind NAT

## Port Configuration

### Firewall Rules to Allow

```bash
# URF239 Reflector Ports (all standard + 1)
sudo ufw allow 42001/udp    # YSF
sudo ufw allow 17001/udp    # M17
sudo ufw allow 41001/udp    # P25
sudo ufw allow 41401/udp    # NXDN
sudo ufw allow 30052/tcp    # DCS
sudo ufw allow 30002/tcp    # DExtra
sudo ufw allow 20002/tcp    # DPlus
sudo ufw allow 10018/tcp    # URF
sudo ufw allow 62031/tcp    # MMDVM
sudo ufw allow 8881/tcp     # DMRPlus

# Dashboard
sudo ufw allow 8081/tcp     # Dashboard HTTP

# AllStar USRP (if enabled)
sudo ufw allow 32000:34000/udp

# AllStar-Nexus Web UI (optional)
sudo ufw allow 8090/tcp

# Enable firewall
sudo ufw enable
sudo ufw status
```

### Port Conflicts Check
- [ ] Verify no conflicts: `sudo netstat -tulpn | grep -E '17001|42001|8081|5555|5556|6556'`
- [ ] Stop any conflicting services

## Initial Deployment

### 1. Clone Repository
- [ ] SSH into production VM
- [ ] Clone repository: `git clone https://github.com/YOUR_USERNAME/urfd-tilt.git`
- [ ] Change to directory: `cd urfd-tilt`
- [ ] Create production branch: `git checkout -b production/urf239`

### 2. Customize Configuration

#### urfd.ini
- [ ] Edit: `nano config/production/urfd.ini`
- [ ] Update email (line 6)
- [ ] Update sponsor (line 9)
- [ ] Update dashboard URL (line 10)
- [ ] Customize module descriptions (lines 19-23)
- [ ] Verify USRP settings if using AllStar:
  - [ ] `Enable = true`
  - [ ] `IPAddress = 172.17.0.1` (or AllStar-Nexus IP)
- [ ] Verify ControlNNGAddr is set: `tcp://0.0.0.0:6556`

#### dashboard/config.yaml
- [ ] Edit: `nano config/production/dashboard/config.yaml`
- [ ] Update reflector name if desired
- [ ] Set transmit_password for security
- [ ] Verify NNG URLs point to `host.docker.internal`

### 3. Create Data Directories
```bash
mkdir -p data/production/{logs,audio,dashboard}
```
- [ ] Verify directories created: `ls -la data/production/`

### 4. Build Docker Images
```bash
./docker/build-all.sh
```
- [ ] Verify all images built successfully:
  - [ ] `urfd-common`
  - [ ] `imbe-lib`
  - [ ] `md380-lib`
  - [ ] `urfd`
  - [ ] `tcd`
  - [ ] `dashboard`
- [ ] Check images: `docker images | grep -E 'urfd|tcd|dashboard'`

### 5. Start Services
```bash
# Create alias for convenience
alias dc-prod="docker-compose -f docker-compose.yml -f docker-compose.prod.yml"

# Start production
dc-prod up -d
```
- [ ] Verify containers started: `dc-prod ps`
- [ ] Check container status: all should be "Up"

### 6. Verify Services

#### URFD
```bash
docker logs urfd239 --tail 50
```
- [ ] URFD started successfully
- [ ] All protocols initialized (YSF, M17, P25, NXDN, etc.)
- [ ] NNG Dashboard socket listening at tcp://0.0.0.0:5555
- [ ] NNG Voice socket listening at tcp://0.0.0.0:5556
- [ ] NNG Control socket listening at tcp://0.0.0.0:6556 (if AllStar enabled)
- [ ] USRP protocol enabled (if AllStar configured)
- [ ] No error messages

#### TCD
```bash
docker logs tcd239 --tail 50
```
- [ ] TCD started successfully
- [ ] Listening on port 10101
- [ ] Connected to URFD
- [ ] No codec initialization errors

#### Dashboard
```bash
docker logs dashboard239 --tail 50
```
- [ ] Dashboard started successfully
- [ ] Connected to URFD NNG at host.docker.internal:5555
- [ ] Voice stream connected at host.docker.internal:5556
- [ ] HTTP server listening on :8080 (internal)
- [ ] No connection errors

### 7. Network Verification
```bash
# Verify host networking
docker inspect urfd239 | grep NetworkMode
# Should show: "NetworkMode": "host"

docker inspect tcd239 | grep NetworkMode
# Should show: "NetworkMode": "container:urfd239"

# Check listening ports on host
sudo netstat -tulpn | grep -E '17001|42001|5555|5556|6556|10101'
```
- [ ] URFD ports bound directly to host
- [ ] NNG sockets listening
- [ ] TCD listening on 10101

### 8. Dashboard Access
- [ ] Open browser to `http://YOUR_SERVER_IP:8081`
- [ ] Dashboard loads successfully
- [ ] Reflector name shows "URF239"
- [ ] Modules listed: A, D, M, S, Z
- [ ] Connected users visible (if any)
- [ ] No JavaScript console errors

## AllStar-Nexus Integration (Optional)

### 1. Install AllStar-Nexus on Host
```bash
cd /opt
sudo git clone https://github.com/dbehnke/allstar-nexus.git
cd allstar-nexus
sudo go build -o allstar-nexus .
```
- [ ] AllStar-Nexus built successfully

### 2. Configure AllStar-Nexus
```bash
sudo nano config.yaml
```
- [ ] Set Asterisk AMI host, username, password
- [ ] Set `urfd.nng_control_addr: "tcp://127.0.0.1:6556"`
- [ ] Set `urfd.usrp_callsign: "ALLSTAR"`

### 3. Start AllStar-Nexus
```bash
sudo ./allstar-nexus
```
- [ ] AllStar-Nexus starts without errors
- [ ] Connected to Asterisk AMI
- [ ] Connected to URFD NNG Control at 127.0.0.1:6556

### 4. Test AllStar Integration
- [ ] Key up on AllStar node
- [ ] Check URFD logs: `docker logs -f urfd239 | grep -E "NNG Control|USRP"`
- [ ] Should see: `NNG Control: Registered CALLSIGN at IP`
- [ ] Audio appears on dashboard
- [ ] Callsign displays correctly

## Post-Deployment Testing

### Protocol Testing

#### YSF (port 42001)
- [ ] Connect YSF client to `YOUR_SERVER_IP:42001`
- [ ] Verify connection in URFD logs
- [ ] Transmit and verify audio on dashboard
- [ ] Verify callsign displays correctly

#### M17 (port 17001)
- [ ] Connect M17 client to `YOUR_SERVER_IP:17001`
- [ ] Verify connection in URFD logs
- [ ] Transmit and verify audio on dashboard
- [ ] Check live audio playback works (not just recordings)

#### P25 (port 41001)
- [ ] Connect P25 client to `YOUR_SERVER_IP:41001`
- [ ] Verify connection and transmission

#### NXDN (port 41401)
- [ ] Connect NXDN client to `YOUR_SERVER_IP:41401`
- [ ] Verify connection and transmission

### Audio Testing
- [ ] Live audio plays on dashboard during transmission
- [ ] Audio recordings saved in `data/production/audio/`
- [ ] Audio files playable after transmission ends
- [ ] Callsign appears in audio player

### Transcoding Testing
- [ ] Transmit from M17 module, verify audio on YSF module
- [ ] Transmit from YSF module, verify audio on M17 module
- [ ] Verify TCD transcodes without errors
- [ ] Check TCD logs for any codec warnings

## Monitoring & Maintenance

### Setup Monitoring
- [ ] Configure log rotation (already enabled in docker-compose.prod.yml)
- [ ] Setup monitoring/alerting (optional)
- [ ] Create backup script (see below)

### Backup Script
```bash
#!/bin/bash
# Save as ~/backup-urfd.sh
BACKUP_DIR=~/urfd-backups
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p $BACKUP_DIR
cd ~/urfd-tilt
tar czf $BACKUP_DIR/urfd239-$DATE.tar.gz \
  config/production \
  data/production/dashboard/*.db \
  docker-compose.prod.yml \
  PRODUCTION.md
echo "Backup created: $BACKUP_DIR/urfd239-$DATE.tar.gz"
# Keep only last 7 backups
ls -t $BACKUP_DIR/*.tar.gz | tail -n +8 | xargs rm -f
```
- [ ] Create backup script: `nano ~/backup-urfd.sh`
- [ ] Make executable: `chmod +x ~/backup-urfd.sh`
- [ ] Test backup: `~/backup-urfd.sh`
- [ ] Schedule daily backups: `crontab -e`
  ```
  0 3 * * * /home/YOUR_USER/backup-urfd.sh
  ```

### Log Monitoring
```bash
# View all logs
dc-prod logs -f

# View specific service
docker logs -f urfd239
docker logs -f tcd239
docker logs -f dashboard239

# Search for errors
docker logs urfd239 | grep -i error
```
- [ ] Setup log monitoring routine

### Health Checks
- [ ] Dashboard accessible: `curl http://localhost:8081`
- [ ] URFD running: `docker ps | grep urfd239`
- [ ] TCD running: `docker ps | grep tcd239`
- [ ] Dashboard running: `docker ps | grep dashboard239`
- [ ] No errors in logs

## Commit Configuration

```bash
cd ~/urfd-tilt
git add config/production/
git add docker-compose.prod.yml
git add PRODUCTION.md
git add DEPLOYMENT-CHECKLIST.md
git commit -m "chore: URF239 production deployment configuration"
git push -u origin production/urf239
```
- [ ] Configuration committed to git
- [ ] Pushed to remote repository (for backup)

## Documentation

- [ ] Update wiki/documentation with server IP and ports
- [ ] Document any custom module configurations
- [ ] Share dashboard URL with users
- [ ] Update whitelist/blacklist if needed

## Troubleshooting Reference

### Services Won't Start
```bash
# Check Docker service
sudo systemctl status docker

# Check logs for errors
dc-prod logs

# Verify config syntax
grep -E "^[A-Z]" config/production/urfd.ini

# Check port conflicts
sudo netstat -tulpn | grep -E '17001|42001|8081'
```

### Dashboard Not Accessible
```bash
# Check dashboard container
docker logs dashboard239

# Verify port binding
docker ps | grep dashboard239

# Test from server
curl http://localhost:8081
```

### Audio Issues
```bash
# Check voice stream
docker logs urfd239 | grep "Voice"

# Verify audio directory
ls -la data/production/audio/

# Check TCD connection
docker logs tcd239 | grep -i connect
```

### AllStar Not Registering
```bash
# Check Control socket
docker logs urfd239 | grep "NNG Control"

# Verify AllStar-Nexus
sudo systemctl status allstar-nexus

# Test NNG connection
telnet localhost 6556
```

## Final Checklist

- [ ] All services running: `dc-prod ps`
- [ ] No errors in logs: `dc-prod logs | grep -i error`
- [ ] Dashboard accessible via browser
- [ ] At least one protocol tested and working
- [ ] Audio playback working (live and recordings)
- [ ] Configuration backed up and committed to git
- [ ] Firewall rules configured
- [ ] Monitoring/backup scheduled
- [ ] Documentation updated
- [ ] Users notified of new reflector

## Deployment Complete!

**Congratulations!** Your URF239 reflector is now live.

### Quick Reference Commands
```bash
# View status
dc-prod ps

# View logs
dc-prod logs -f

# Restart services
dc-prod restart

# Stop services
dc-prod down

# Start services
dc-prod up -d

# Backup configuration
~/backup-urfd.sh
```

### Support
- Review logs: `dc-prod logs`
- Check GitHub issues: https://github.com/YOUR_USERNAME/urfd-tilt/issues
- See PRODUCTION.md for upgrade procedures
- See TROUBLESHOOTING.md for common issues (if available)

---

**Deployment Date**: _______________  
**Deployed By**: _______________  
**Server IP**: _______________  
**Dashboard URL**: _______________
