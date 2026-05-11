# URF239 Docker Compose Strategy for `whocares`

**Goal:** Replace the current non-prefixed URF239 containers (`urfd`, `tcd`, `dashboard`) with an explicitly named and labeled production Compose deployment for URF239 on `whocares`.

**Production host:** `whocares`

**Current runtime path:** `/home/dbehnke/urf239`

**Current Compose project:** `urf239`

## Current state

The current containers are already Compose-managed under project `urf239`, but their container names are generic:

- `urfd`
- `tcd`
- `dashboard`

They have Docker Compose labels such as `com.docker.compose.project=urf239`, but they do not have explicit URF239/operator labels, and the names are not self-identifying.

Current networking:

- `urfd`: `network_mode: host`
- `tcd`: `network_mode: host`
- `dashboard`: bridge network, publishes `8080:8080/tcp`, uses `host.docker.internal:host-gateway`

Keep this networking model for URF239 because the checked production configs already bind instance-specific ports directly on the host.

## Recommended target state

Use a dedicated production Compose file in `/home/dbehnke/urf239/docker-compose.yml` with:

- top-level Compose project name: `urf239`
- prefixed container names:
  - `urf239-urfd`
  - `urf239-tcd`
  - `urf239-dashboard`
- explicit labels on every service:
  - `com.dbehnke.urfd.instance=URF239`
  - `com.dbehnke.urfd.environment=production`
  - `com.dbehnke.urfd.host=whocares`
  - `com.dbehnke.urfd.managed-by=docker-compose`
  - `com.dbehnke.urfd.role=<urfd|tcd|dashboard>`
- image tags controlled by `IMAGE_VERSION`, defaulting to `latest` only if no explicit tag is provided.

## Target Compose shape

```yaml
name: urf239

x-urf239-labels: &urf239-labels
  com.dbehnke.urfd.instance: "URF239"
  com.dbehnke.urfd.environment: "production"
  com.dbehnke.urfd.host: "whocares"
  com.dbehnke.urfd.managed-by: "docker-compose"
  com.dbehnke.urfd.compose-project: "urf239"

services:
  urfd:
    image: urfd:${IMAGE_VERSION:-latest}
    container_name: urf239-urfd
    command: urfd /usr/local/etc/urfd/urfd.ini
    network_mode: host
    labels:
      <<: *urf239-labels
      com.dbehnke.urfd.role: "urfd"
    volumes:
      - ./config/production:/usr/local/etc/urfd:ro
      - ./data/logs:/var/log/urfd
      - ./data/audio:/usr/local/bin/audio
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  tcd:
    image: tcd:${IMAGE_VERSION:-latest}
    container_name: urf239-tcd
    command: tcd /usr/local/etc/tcd/tcd.ini
    network_mode: host
    depends_on:
      - urfd
    labels:
      <<: *urf239-labels
      com.dbehnke.urfd.role: "tcd"
    volumes:
      - ./config/production:/usr/local/etc/tcd:ro
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  dashboard:
    image: dashboard:${IMAGE_VERSION:-latest}
    container_name: urf239-dashboard
    command: dashboard -config /etc/dashboard/config.yaml
    ports:
      - "8080:8080/tcp"
    environment:
      - URFD_HOST=urfd
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      - urfd
    labels:
      <<: *urf239-labels
      com.dbehnke.urfd.role: "dashboard"
    volumes:
      - ./config/dashboard:/etc/dashboard:ro
      - ./data/audio:/usr/local/bin/audio:ro
      - ./data/dashboard:/data
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Image tagging strategy

For production, avoid depending on mutable `latest` once the rebuild is ready.

Recommended tag pattern:

```bash
VERSION=v1.0.3-urf239
bash deployment/build/build-images.sh "$VERSION" --also-tag-latest
```

Then start URF239 with:

```bash
IMAGE_VERSION=v1.0.3-urf239 docker compose -p urf239 up -d
```

The build script tags both short and production names for core images, including:

- `urfd:${VERSION}` and `urfd-urfd:${VERSION}`
- `tcd:${VERSION}` and `urfd-tcd:${VERSION}`
- `dashboard:${VERSION}` and `urfd-dashboard:${VERSION}`

For this specific Compose file, use the short names: `urfd`, `tcd`, `dashboard`, because that matches the current deployment and existing local images on `whocares`.

## Cutover procedure

Run this only during an approved production maintenance window.

### 1. Snapshot current state

```bash
ssh whocares
cd /home/dbehnke/urf239
mkdir -p backups/$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backups/$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml.before-prefixed-containers"
docker compose -p urf239 ps > "$BACKUP_DIR/compose-ps.txt"
docker inspect urfd tcd dashboard > "$BACKUP_DIR/docker-inspect.json"
```

### 2. Build or verify images

If rebuilding on `whocares` from the repo checkout:

```bash
cd /home/dbehnke/urf239
VERSION=v1.0.3-urf239
bash deployment/build/build-images.sh "$VERSION" --also-tag-latest
```

Verify:

```bash
docker images | grep -E '^(urfd|tcd|dashboard)'
```

### 3. Replace `docker-compose.yml`

Write the target Compose file above to `/home/dbehnke/urf239/docker-compose.yml`.

Validate before stopping production:

```bash
cd /home/dbehnke/urf239
IMAGE_VERSION=v1.0.3-urf239 docker compose -p urf239 config >/tmp/urf239-compose.rendered.yml
```

### 4. Stop old generic containers

Because the existing generic containers are still Compose-managed under `com.docker.compose.project=urf239`, stop them through Compose rather than manually deleting by name:

```bash
cd /home/dbehnke/urf239
docker compose -p urf239 down --remove-orphans
```

Expected result: `urfd`, `tcd`, and `dashboard` are stopped and removed. Do not touch the separate `zombie` Compose project.

### 5. Start prefixed URF239 containers

```bash
cd /home/dbehnke/urf239
IMAGE_VERSION=v1.0.3-urf239 docker compose -p urf239 up -d --remove-orphans
```

### 6. Verify identity and labels

```bash
docker ps --filter 'label=com.dbehnke.urfd.instance=URF239' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

docker inspect urf239-urfd urf239-tcd urf239-dashboard \
  --format '{{.Name}} {{index .Config.Labels "com.dbehnke.urfd.instance"}} {{index .Config.Labels "com.dbehnke.urfd.role"}}'
```

Expected containers:

- `/urf239-urfd URF239 urfd`
- `/urf239-tcd URF239 tcd`
- `/urf239-dashboard URF239 dashboard`

### 7. Verify ports and service health

```bash
docker compose -p urf239 ps
ss -H -ltnup | grep -E ':(8080|5555|5556|6001|6556|10101)\b'
ss -H -lunp | grep -E ':(20002|30002|30052|8881|17001|62031|41401|41001|10018|34001|32001|42001)\b'
docker logs --tail 100 urf239-urfd
docker logs --tail 100 urf239-tcd
docker logs --tail 100 urf239-dashboard
```

Dashboard should still be available at:

```text
http://whocares:8080
```

## Rollback

If the prefixed deployment fails:

```bash
cd /home/dbehnke/urf239
docker compose -p urf239 down --remove-orphans
cp backups/<timestamp>/docker-compose.yml.before-prefixed-containers docker-compose.yml
docker compose -p urf239 up -d
```

This restores the previous generic container names and Compose shape.

## Follow-up repo work

After validating the URF239 strategy on `whocares`, consider updating the production template in the repo:

- `deployment/templates/docker-compose.prod.yml`

Recommended improvements:

1. Add explicit service labels using environment variables:
   - `${INSTANCE_NAME}`
   - `${DEPLOYMENT_ENVIRONMENT:-production}`
   - `${DEPLOYMENT_HOST}`
2. Decide whether production should standardize on:
   - host networking for URFD/TCD, matching the current URF239 deployment, or
   - bridge networking with explicit port mappings, matching the current production template.
3. Avoid mixing the two strategies without documenting why. URF239 currently relies on host networking and instance-specific config ports.
