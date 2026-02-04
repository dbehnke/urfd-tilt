FROM debian:trixie

ENV container podman

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus dbus-user-session systemd-container \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

VOLUME ["/sys/fs/cgroup"]

STOPSIGNAL SIGRTMIN+3

# Use the systemd binary as PID 1
CMD ["/lib/systemd/systemd"]
