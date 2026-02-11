FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# Provide a minimal systemd-enabled Debian image with kmod so /sbin/rmmod exists
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    dbus \
    kmod \
    ca-certificates \
    libnng1 \
    libopus0 \
    libogg0 \
    libfmt10 \
    libcurl3t64-gnutls \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Allow systemd to mount cgroups from the host
VOLUME ["/sys/fs/cgroup"]

CMD ["/sbin/init"]
