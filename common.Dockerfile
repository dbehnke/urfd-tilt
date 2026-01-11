# Base image
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libnng-dev \
    libcurl4-gnutls-dev \
    libboost-all-dev \
    nlohmann-json3-dev \
    libfmt-dev \
    libopus-dev \
    libogg-dev \
    unzip \
    python3 \
    golang-go \
    wget \
    curl \
    xxd \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /build
