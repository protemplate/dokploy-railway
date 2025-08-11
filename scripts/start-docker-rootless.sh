#!/bin/bash

# Alternative: Start Docker in rootless mode for Railway
echo "==============================================="
echo "Starting Docker in rootless mode (Railway)"
echo "==============================================="

# Set up rootless Docker environment
export DOCKER_HOST=unix:///var/run/user/$(id -u)/docker.sock
export DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/data/docker}"
export XDG_RUNTIME_DIR=/tmp/docker-runtime
mkdir -p $XDG_RUNTIME_DIR

# Install rootless extras if needed
if ! command -v dockerd-rootless.sh &> /dev/null; then
    echo "Installing rootless Docker components..."
    curl -fsSL https://get.docker.com/rootless | sh || {
        echo "Failed to install rootless components, falling back to regular Docker"
        exit 1
    }
fi

# Start rootless Docker daemon
echo "Starting rootless Docker daemon..."
PATH=$HOME/bin:$PATH dockerd-rootless.sh \
    --storage-driver=vfs \
    --data-root="${DOCKER_DATA_ROOT}" \
    2>&1 | tee /tmp/docker-rootless.log &

DOCKER_PID=$!

# Wait for Docker to be ready
echo "Waiting for rootless Docker to be ready..."
MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if docker version >/dev/null 2>&1; then
        echo "✓ Rootless Docker is ready!"
        docker info
        exit 0
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    echo "  Waiting... ($WAITED/$MAX_WAIT seconds)"
done

echo "ERROR: Rootless Docker failed to start"
cat /tmp/docker-rootless.log
exit 1