#!/bin/bash

# Initialize Docker for Railway environment
echo "Initializing Docker for Railway container environment..."

# Check if we have CAP_NET_ADMIN capability
if capsh --print 2>/dev/null | grep -q cap_net_admin; then
    echo "Network admin capability detected"
    USE_IPTABLES="true"
else
    echo "No network admin capability - disabling iptables"
    USE_IPTABLES="false"
fi

# Try to load necessary kernel modules (may fail in container, that's ok)
for module in overlay br_netfilter; do
    modprobe $module 2>/dev/null || echo "Note: Could not load module $module (expected in container)"
done

# Set up sysctl parameters if possible
if [ -w /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || true
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 2>/dev/null || true
fi

# Configure Docker daemon based on environment
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"

if [ "$USE_IPTABLES" = "false" ]; then
    # Railway environment without iptables
    cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "vfs",
  "data-root": "$DOCKER_DATA_ROOT",
  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["8.8.8.8", "8.8.4.4"],
  "insecure-registries": ["127.0.0.0/8"],
  "live-restore": false,
  "iptables": false,
  "bridge": "none",
  "ip-forward": false,
  "ip-masq": false,
  "userland-proxy": true,
  "experimental": true,
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5,
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  }
}
EOF
else
    # Environment with iptables support
    cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "vfs",
  "data-root": "$DOCKER_DATA_ROOT",
  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["8.8.8.8", "8.8.4.4"],
  "insecure-registries": ["127.0.0.0/8"],
  "live-restore": false,
  "userland-proxy": false,
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5
}
EOF
fi

echo "Docker configuration complete"
cat /etc/docker/daemon.json