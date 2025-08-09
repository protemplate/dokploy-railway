#!/bin/bash
set -e

echo "Starting Dokploy deployment..."

# Start Docker daemon in the background
dockerd &

# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 2
done

echo "Docker is ready!"

# Start Dokploy
echo "Starting Dokploy on port ${DOKPLOY_PORT:-3000}..."
exec dokploy start --port=${DOKPLOY_PORT:-3000}