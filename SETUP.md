# URFD Setup Guide

This guide is for someone setting up this repository for the first time. It covers two common paths:

- **Development**: run URFD locally with Docker Compose and Task while editing code.
- **Production**: run one or more isolated URFD instances on a Linux server.

The recommended command interface is `task`. Task commands wrap the lower-level Docker Compose and deployment scripts so you do not need to remember every flag.

## Pick Your Setup

Use **development setup** when:

- You are changing source code.
- You want a local dashboard and reflector for testing.
- You are on macOS, Linux, or a workstation VM.

Use **production setup** when:

- You are deploying for real users.
- You want systemd startup.
- You need multiple instances on one server with different ports.
- You want versioned image builds and upgrade commands.

## Development Setup

### 1. Install Required Tools

You need:

- Git
- Docker Desktop or Colima
- Docker Compose V2
- Task

On macOS with Homebrew:

```bash
brew install git go-task docker colima
```

Start Colima with UDP-capable port forwarding:

```bash
colima start --cpu 4 --memory 8 --disk 100 --port-forwarder grpc --vz-rosetta
```

On Linux, install Docker and Task using your distribution packages or the upstream installers. Verify the tools:

```bash
git --version
docker --version
docker compose version
task --version
```

### 2. Clone And Initialize

Clone the repository:

```bash
git clone https://github.com/dbehnke/urfd-tilt.git
cd urfd-tilt
```

Initialize submodules and local config:

```bash
task init
```

This creates `config/local/` from `config/defaults/` and initializes the source repositories under `src/`.

### 3. Build Local Images

Build local Docker images tagged as `latest`:

```bash
task dev-build
```

This can take a while the first time because it builds the base image, vocoder libraries, URFD, TCD, and dashboard.

### 4. Start The Dev Stack

Start the default local instance:

```bash
task dev
```

The default instance is `URF010`. It writes `.env.dev`, creates instance-specific runtime directories under `data/dev/URF010/`, and starts Docker Compose.

Open the dashboard:

```text
http://localhost:9080
```

### 5. Check Status And Logs

Show containers:

```bash
task dev-ps
```

Follow logs:

```bash
task dev-logs
```

Run smoke checks:

```bash
task smoke
./scripts/test-udp-ports.sh
```

### 6. Stop The Dev Stack

```bash
task dev-down
```

### 7. Run A Second Local Instance

Use another instance number and a separate env file:

```bash
task dev INSTANCE=URF011 ENV_FILE=.env.URF011.dev
task dev-ps ENV_FILE=.env.URF011.dev
```

Dashboard for `URF011` is:

```text
http://localhost:9180
```

The current port-offset scheme supports `URF000` through `URF035`. Higher instance numbers can produce ports above `65535`.

## Production Setup

Production deployment is intended for a Linux server.

### 1. Install Required Tools

Install Docker, Docker Compose V2, Git, Task, `gettext-base`, and `jq`.

On Debian or Ubuntu:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
sudo apt-get update
sudo apt-get install -y git gettext-base jq
```

Install Task using the official installer or package manager for your platform, then verify:

```bash
docker --version
docker compose version
task --version
```

Log out and back in after adding your user to the Docker group, or use `sudo` for Docker commands.

### 2. Clone And Initialize

```bash
git clone https://github.com/dbehnke/urfd-tilt.git
cd urfd-tilt
task init
```

### 3. Choose The Instance Directory

By default, production instances live under:

```text
/opt/urfd-production/instances
```

Create it:

```bash
sudo mkdir -p /opt/urfd-production/instances
sudo chown "$USER:$USER" /opt/urfd-production/instances
```

If you want a different location, pass `INSTANCES_DIR` to production Task commands:

```bash
task prod-deploy INSTANCE=URF000 VERSION=v1.0.0 INSTANCES_DIR=/home/urfd/instances
```

### 4. Build Production Images

Pick a version tag:

```bash
task prod-build VERSION=v1.0.0
```

The version should look like `vMAJOR.MINOR.PATCH`, for example `v1.0.0` or `v1.1.0-rc1`.

### 5. Deploy The First Instance

```bash
task prod-deploy INSTANCE=URF000 VERSION=v1.0.0
```

This creates:

```text
/opt/urfd-production/instances/URF000/
├── .env
├── docker-compose.yml
├── config/
└── data/
```

It also installs and starts a systemd unit because `task prod-deploy` delegates to deployment with `--systemd --start`.

### 6. Customize The Instance

Edit the instance `.env` file:

```bash
sudoedit /opt/urfd-production/instances/URF000/.env
```

Use `.env` for routine settings such as callsign, dashboard name, sysop email, module descriptions, and port values.

Apply the changes:

```bash
task prod-apply INSTANCE=URF000
```

`prod-apply` re-renders generated files from `.env`, validates the instance, and runs `docker compose up -d`.

Generated files such as `docker-compose.yml`, `config/urfd.ini`, `config/tcd.ini`, and `config/dashboard/config.yaml` can be overwritten by deploy, render, and upgrade commands. Keep routine customizations in `.env`.

### 7. Manage Production

Check status:

```bash
task prod-status INSTANCE=URF000
```

Follow logs:

```bash
task prod-logs INSTANCE=URF000
```

Validate configuration:

```bash
task prod-validate INSTANCE=URF000
```

Upgrade to a new version:

```bash
task prod-build VERSION=v1.0.1
task prod-upgrade INSTANCE=URF000 VERSION=v1.0.1
```

### 8. Run Multiple Production Instances

Use a different instance name:

```bash
task prod-deploy INSTANCE=URF001 VERSION=v1.0.0
```

Ports are offset by the instance number. For example:

- `URF000` dashboard: `8080`
- `URF001` dashboard: `8180`
- `URF002` dashboard: `8280`

## Common Problems

### Docker Is Not Running

Symptoms include errors connecting to a Docker socket.

On macOS with Colima:

```bash
colima start --cpu 4 --memory 8 --disk 100 --port-forwarder grpc --vz-rosetta
```

On Linux:

```bash
sudo systemctl start docker
```

### UDP Ports Do Not Work On macOS

Colima must use the `grpc` port forwarder:

```bash
colima stop
colima start --port-forwarder grpc
```

### A Port Is Already In Use

Use another instance number:

```bash
task dev INSTANCE=URF011 ENV_FILE=.env.URF011.dev
```

For production, deploy a different instance:

```bash
task prod-deploy INSTANCE=URF001 VERSION=v1.0.0
```

### Production Validation Fails Because Images Are Missing

Build the requested version first:

```bash
task prod-build VERSION=v1.0.0
```

### Need A Dry Render Without Docker Validation

For local dry runs or documentation tests:

```bash
task prod-render INSTANCE=URF000 RENDER_FLAGS=--skip-validation
```

Use this only when you intentionally want to skip Docker image and Compose validation.
