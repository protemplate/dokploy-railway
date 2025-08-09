#!/bin/bash

# Use PORT environment variable with fallback to 3000
PORT=${PORT:-3000}

# During initial setup, Dokploy might take time to install
# Check if installation is in progress
if [ -f /tmp/dokploy-installing ]; then
    echo "Dokploy is being installed..."
    exit 0
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running yet"
    exit 1
fi

# Try multiple endpoints for health check
# First try IPv6 localhost
if curl -f -m 5 "http://[::1]:${PORT}/" >/dev/null 2>&1; then
    echo "Dokploy is healthy (IPv6)"
    exit 0
fi

# Then try IPv4 localhost
if curl -f -m 5 "http://localhost:${PORT}/" >/dev/null 2>&1; then
    echo "Dokploy is healthy (IPv4)"
    exit 0
fi

# Try 127.0.0.1 explicitly
if curl -f -m 5 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    echo "Dokploy is healthy (127.0.0.1)"
    exit 0
fi

# If we're still installing, give it more time
if [ ! -f /data/dokploy/.installed ] && [ ! -f /etc/dokploy/.installed ]; then
    echo "Dokploy installation in progress..."
    exit 0
fi

echo "Dokploy is not responding on port ${PORT}"
exit 1