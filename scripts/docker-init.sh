#!/bin/bash

# Initialize Docker for Railway environment
echo "Initializing Docker environment checks..."

# Check if we have CAP_NET_ADMIN capability
# In Railway, we typically don't have this capability
if capsh --print 2>/dev/null | grep -q cap_net_admin; then
    echo "✓ Network admin capability detected (unexpected in Railway)"
    export USE_IPTABLES="true"
else
    echo "✓ Running without network admin capability (expected in Railway)"
    export USE_IPTABLES="false"
fi

# Try to load necessary kernel modules (may fail in container, that's ok)
for module in overlay br_netfilter; do
    if modprobe $module 2>/dev/null; then
        echo "✓ Loaded kernel module: $module"
    else
        echo "✗ Could not load module $module (expected in container)"
    fi
done

# Set up sysctl parameters if possible
if [ -w /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || true
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 2>/dev/null || true
    echo "✓ Configured bridge netfilter"
else
    echo "✗ Cannot configure bridge netfilter (expected in container)"
fi

# Remove any existing daemon.json to avoid conflicts with command-line flags
if [ -f /etc/docker/daemon.json ]; then
    echo "Removing existing daemon.json to use command-line flags instead"
    rm -f /etc/docker/daemon.json
fi

echo "Docker environment check complete"
echo "USE_IPTABLES=$USE_IPTABLES"