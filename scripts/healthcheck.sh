#!/bin/bash

# Use PORT environment variable with fallback to 3000
PORT=${PORT:-3000}

# Function to check if Dokploy service is healthy
check_dokploy_health() {
    local endpoint=$1
    local description=$2
    
    # Check if we get a valid HTTP response
    if curl -f -m 5 -s -o /dev/null -w "%{http_code}" "$endpoint" | grep -q "^[23]"; then
        echo "Dokploy is healthy ($description)"
        return 0
    fi
    return 1
}

# During initial setup, Dokploy might take time to install
# Check if installation is in progress
if [ -f /tmp/dokploy-installing ]; then
    echo "Dokploy is being installed..."
    exit 0
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running yet"
    
    # Check if we're within the first 5 minutes of startup (extended for Railway)
    UPTIME=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "300")
    if [ "$UPTIME" -lt 300 ]; then
        echo "Container is still starting up (${UPTIME}s elapsed)..."
        exit 0
    fi
    
    echo "ERROR: Docker daemon failed to start after 5 minutes"
    exit 1
fi

# Check if Dokploy services are running in Docker Swarm
if docker service ls 2>/dev/null | grep -q dokploy; then
    # Check if the main Dokploy service is running
    DOKPLOY_STATUS=$(docker service ps dokploy --format "{{.CurrentState}}" 2>/dev/null | head -n1)
    if [[ "$DOKPLOY_STATUS" == *"Running"* ]]; then
        echo "Dokploy service is running in Swarm"
    else
        echo "Dokploy service status: $DOKPLOY_STATUS"
        # Give it time during startup
        UPTIME=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "300")
        if [ "$UPTIME" -lt 300 ]; then
            exit 0
        fi
    fi
fi

# Try multiple endpoints for health check
# First try IPv6 localhost
if check_dokploy_health "http://[::1]:${PORT}/" "IPv6 localhost"; then
    exit 0
fi

# Then try IPv4 localhost
if check_dokploy_health "http://localhost:${PORT}/" "IPv4 localhost"; then
    exit 0
fi

# Try 127.0.0.1 explicitly
if check_dokploy_health "http://127.0.0.1:${PORT}/" "127.0.0.1"; then
    exit 0
fi

# Try 0.0.0.0 binding
if check_dokploy_health "http://0.0.0.0:${PORT}/" "0.0.0.0"; then
    exit 0
fi

# Check if installation has completed
if [ ! -f /data/dokploy/.installed ] && [ ! -f /etc/dokploy/.installed ]; then
    # Check uptime to determine if we should still wait
    UPTIME=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "300")
    if [ "$UPTIME" -lt 300 ]; then
        echo "Dokploy installation in progress (${UPTIME}s elapsed)..."
        exit 0
    else
        echo "WARNING: Dokploy installation incomplete after 5 minutes"
    fi
fi

# Final check - see if Dokploy container is at least running
if docker ps 2>/dev/null | grep -q dokploy; then
    echo "Dokploy container is running but not yet responding on port ${PORT}"
    # During startup phase, this is acceptable
    UPTIME=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "300")
    if [ "$UPTIME" -lt 300 ]; then
        exit 0
    fi
fi

echo "ERROR: Dokploy is not responding on port ${PORT}"
exit 1