# URFD Development Environment

This directory contains the modernized development workflow for URFD, using [Tilt](https://tilt.dev/), [Docker Compose](https://docs.docker.com/compose/), and [Taskfile](https://taskfile.dev/).

## Architecture

The environment orchestrates multiple services and builds them from local source repositories.

```mermaid
graph TD
    subgraph Host
        Tilt[Tilt]
        Task[Taskfile]
        Repos[Source Repositories]
    end

    subgraph Docker
        Common[urfd-common (Base Image)]
        
        subgraph Vocoders
            Imbe[IMBE Lib]
            MD380[MD380 Lib]
        end

        subgraph Sevices
            URFD[URFD Reflector]
            TCD[TCD Transcoder]
            Dash[Dashboard]
            Nexus[AllStar Nexus (Optional)]
        end
    end

    Tilt -->|Orchestrates| Docker
    Task -->|Initializes| Repos
    Repos -->|Build Context| Common
    Common --> Imbe & MD380 & URFD & TCD & Dash
    Imbe & MD380 -->|Linked into| TCD
    URFD -->|NNG| Dash
    URFD -->|TCP| TCD
    Nexus -.->|USRP| URFD
```

## Prerequisites

### Option 1: Nix (Recommended)

If you have [Nix](https://nixos.org/download.html) installed, you can enter a reproducible shell with all dependencies:

```bash
nix-shell
# or
nix-shell shell.nix
```

### Option 2: macOS (Homebrew)

```bash
brew install tilt go-task docker git
```

### Manual

Ensure you have the following installed:

- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Tilt](https://docs.tilt.dev/install.html)
- [Task](https://taskfile.dev/installation/)
- Git

## Quick Start

1. **Initialize the Environment**:
    Clones missing repositories and sets up local configuration.

    ```bash
    task init
    ```

2. **Start Tilt**:
    Builds containers and streams logs.

    ```bash
    tilt up
    ```

    Press `Space` to open the Tilt UI in your browser.

3. **Access Services**:
    - **Tilt UI**: `http://localhost:10350`
    - **Dashboard**: `http://localhost:8080` (or as configured)
    - **URFD**: Ports defined in `docker-compose.yml` (host mode).

## Workflow

### Configuration

- Default configurations are in `config/defaults/`.
- **Do not edit files in `defaults/` directly.**
- Run `task init` to copy them to `config/local/`.
- Edit `config/local/urfd.ini` to change settings. This directory is git-ignored.

### Enabling Optional Components

 To enable **AllStar Nexus** for USRP testing:

 ```bash
 tilt up -- --usrp
 ```

### Rebuilding

- Tilt automatically watches the `Tiltfile` and `config/local` changes.
- Source code changes in `../urfd` etc. will trigger image rebuilds (standard Tilt behavior).
- To force a full rebuild, use the Tilt UI or restart `tilt up`.

## Repository Layout

The setup assumes the following directory structure:

```
../
├── urfd/
├── tcd/
├── urfd-nng-dashboard/
├── imbe_vocoder/
├── md380_vocoder_dynarmic/
├── allstar-nexus/ (Optional)
└── urfd-tilt/  <-- You are here
    ├── Tiltfile
    ├── Taskfile.yml
    ├── docker-compose.yml
    └── ...
```
