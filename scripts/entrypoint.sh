#!/bin/bash
set -e

# Setup logging
LOG_FILE="/tmp/dokploy-startup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "==============================================="
echo "Dokploy Railway Container Starting"
echo "Date: $(date)"
echo "==============================================="

# Configure Railway-specific settings if needed
if [ -f /app/scripts/configure-railway.sh ]; then
    echo "Configuring Railway-specific settings..."
    /app/scripts/configure-railway.sh
fi

echo "Starting Docker daemon with IPv6 support..."

# Ensure docker data directory exists
if [ -d "/data" ]; then
    echo "Persistent volume detected at /data"
    mkdir -p /data/docker
else
    echo "WARNING: No persistent volume at /data - data will not persist!"
    mkdir -p /var/lib/docker
fi

# Configure Docker daemon for Railway's container environment
mkdir -p /etc/docker

# Set Docker data root based on volume availability
if [ -d "/data" ]; then
    export DOCKER_DATA_ROOT="/data/docker"
else
    export DOCKER_DATA_ROOT="/var/lib/docker"
fi

# Initialize Docker with appropriate configuration
if [ -f /app/scripts/docker-init.sh ]; then
    /app/scripts/docker-init.sh
else
    # Fallback configuration
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
  "userland-proxy": true,
  "iptables": false,
  "bridge": "none",
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5,
  "registry-mirrors": [],
  "debug": false
}
EOF
fi

# Start Docker daemon in the background
echo "Starting Docker daemon..."
echo "Note: Some warnings about plugins and propagation are expected in container environment"
dockerd 2>&1 | tee /tmp/docker.log &
DOCKER_PID=$!

# Wait for Docker to be ready
echo "Waiting for Docker daemon to be ready..."
MAX_DOCKER_WAIT=60
DOCKER_WAITED=0
while [ $DOCKER_WAITED -lt $MAX_DOCKER_WAIT ]; do
    if docker info >/dev/null 2>&1; then
        echo "✓ Docker daemon is ready!"
        docker version
        break
    fi
    sleep 2
    DOCKER_WAITED=$((DOCKER_WAITED + 2))
    echo "  Waiting for Docker... ($DOCKER_WAITED/$MAX_DOCKER_WAIT seconds)"
done

if [ $DOCKER_WAITED -ge $MAX_DOCKER_WAIT ]; then
    echo "==============================================="
    echo "ERROR: Docker daemon failed to start"
    echo "==============================================="
    echo "Docker logs (last 50 lines):"
    tail -n 50 /tmp/docker.log
    echo "==============================================="
    echo "System information:"
    uname -a
    echo "Memory:"
    free -h
    echo "Disk:"
    df -h
    exit 1
fi

# Setup persistent storage (Railway mounts volume at /data)
if [ -d "/data" ]; then
    echo "Setting up persistent storage..."
    
    # Create necessary directories in the volume
    mkdir -p /data/dokploy
    mkdir -p /data/docker
    mkdir -p /data/traefik
    
    # Create symlinks for persistent data
    if [ ! -L /etc/dokploy ]; then
        rm -rf /etc/dokploy
        ln -sf /data/dokploy /etc/dokploy
    fi
    
    # Note: Docker data-root is set via daemon.json instead of symlink
    # to avoid mount propagation issues
    
    echo "Persistent storage configured"
else
    echo "No /data volume detected, using local storage (data will not persist)"
    mkdir -p /etc/dokploy
    mkdir -p /var/lib/docker
fi

# Check if Dokploy is already installed
if [ ! -f /data/dokploy/.installed ]; then
    echo "First time setup - Installing Dokploy..."
    touch /tmp/dokploy-installing
    
    # Set advertise address for Railway
    if [ -n "$RAILWAY_PRIVATE_DOMAIN" ]; then
        # Running on Railway - use the private domain
        export ADVERTISE_ADDR="[::]"
        echo "Running on Railway with private domain: $RAILWAY_PRIVATE_DOMAIN"
    elif [ -n "$ADVERTISE_ADDR" ]; then
        export ADVERTISE_ADDR=$ADVERTISE_ADDR
    else
        # Try to get the container's IP (prefer IPv6)
        IPV6_ADDR=$(ip -6 addr show | grep 'inet6' | grep -v 'fe80' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
        if [ -n "$IPV6_ADDR" ]; then
            export ADVERTISE_ADDR="[$IPV6_ADDR]"
        else
            export ADVERTISE_ADDR=$(hostname -I | awk '{print $1}')
        fi
    fi
    
    echo "Using advertise address: $ADVERTISE_ADDR"
    
    # Install Dokploy with error handling
    echo "Running Dokploy installation script..."
    if /app/scripts/install-dokploy.sh; then
        echo "✓ Dokploy installation script completed successfully"
        
        # Mark as installed
        mkdir -p /data/dokploy
        touch /data/dokploy/.installed
        rm -f /tmp/dokploy-installing
        
        echo "==============================================="
        echo "✓ Dokploy installation completed!"
        echo "==============================================="
    else
        echo "==============================================="
        echo "ERROR: Dokploy installation failed!"
        echo "==============================================="
        echo "Check logs above for details"
        rm -f /tmp/dokploy-installing
        exit 1
    fi
else
    echo "Dokploy already installed, starting services..."
    
    # Start existing Dokploy services
    docker swarm init --advertise-addr ${ADVERTISE_ADDR:-$(hostname -I | awk '{print $1}')} 2>/dev/null || true
    docker service ls | grep dokploy | awk '{print $2}' | xargs -I {} docker service start {} 2>/dev/null || true
fi

# Configure Traefik for Railway if needed
if [ -n "$RAILWAY_PRIVATE_DOMAIN" ]; then
    echo "Configuring Traefik for Railway..."
    mkdir -p /etc/dokploy/traefik
    cat > /etc/dokploy/traefik/railway.yml <<EOF
http:
  serversTransports:
    default:
      forwardingTimeouts:
        dialTimeout: 30s
        responseHeaderTimeout: 30s
EOF
fi

# Wait for Dokploy to be ready
echo "Waiting for Dokploy to be ready on port ${PORT:-3000}..."
MAX_WAIT=300  # 5 minutes
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s http://[::1]:${PORT:-3000} >/dev/null 2>&1 || curl -s http://localhost:${PORT:-3000} >/dev/null 2>&1 || curl -s http://127.0.0.1:${PORT:-3000} >/dev/null 2>&1; then
        echo "Dokploy is ready!"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo "Still waiting for Dokploy... ($WAITED seconds)"
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "Warning: Dokploy did not become ready within $MAX_WAIT seconds"
    echo "Container will continue running, Dokploy may still be initializing..."
fi

# Display access information
echo "==============================================="
echo "Dokploy Setup Complete!"
echo "==============================================="
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    echo "✓ Public URL: https://$RAILWAY_PUBLIC_DOMAIN"
fi
if [ -n "$RAILWAY_PRIVATE_DOMAIN" ]; then
    echo "✓ Private URL: http://$RAILWAY_PRIVATE_DOMAIN:${PORT:-3000}"
fi
echo "✓ Local access: http://localhost:${PORT:-3000}"
echo "==============================================="

# Monitor Docker daemon
echo "Container is now running. Monitoring Docker daemon..."
trap "echo 'Shutting down...'; docker swarm leave --force 2>/dev/null; kill $DOCKER_PID 2>/dev/null" EXIT

# Keep the container running and monitor Docker
while true; do
    if ! kill -0 $DOCKER_PID 2>/dev/null; then
        echo "ERROR: Docker daemon has stopped unexpectedly!"
        echo "Docker logs (last 50 lines):"
        tail -n 50 /tmp/docker.log
        exit 1
    fi
    sleep 30
done