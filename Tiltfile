# Tiltfile

# Helper script to ensure repositories exist
local_resource(
    'ensure-repos',
    cmd='./scripts/ensure-repos.sh',
    deps=['./scripts/ensure-repos.sh']
)

# Common Build Image
docker_build(
    'urfd-common',
    context='.',
    dockerfile='common.Dockerfile'
)

# library: imbe_vocoder
docker_build(
    'imbe-lib',
    context='src/imbe_vocoder',
    dockerfile='docker/imbe.Dockerfile',
    build_args={},
    only=['.'], # optimize context if needed, but for now full context
)

# library: md380_vocoder
docker_build(
    'md380-lib',
    context='src/md380_vocoder_dynarmic',
    dockerfile='docker/md380.Dockerfile',
)

# Service: urfd
docker_build(
    'urfd',
    context='src/urfd',
    dockerfile='docker/urfd.Dockerfile',
    # live_update could be added here for incremental C++ builds if configured
)

# Service: tcd
docker_build(
    'tcd',
    context='.',
    dockerfile='docker/tcd.Dockerfile',
    only=['tcd', 'urfd'], # Explicitly whitelist source folders
)

# Service: dashboard
docker_build(
    'dashboard',
    context='src/urfd-nng-dashboard',
    dockerfile='docker/dashboard.Dockerfile',
)

# Check for --usrp flag
args = config.parse()
enable_usrp = 'usrp' in args

if enable_usrp:
    docker_build(
        'allstar-nexus',
        context='src/allstar-nexus',
        dockerfile='docker/allstar-nexus.Dockerfile'
    )

# Main Docker Compose
compose_files = ['docker-compose.yml']
if enable_usrp:
    compose_files.append('docker-compose.usrp.yml')

docker_compose(compose_files)
