#!/bin/bash
set -e

echo "Installing Dokploy..."

# Check if Docker is available
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running. Cannot install Dokploy."
    exit 1
fi

# For Railway, we need to modify the installation approach
# since we can't use the standard install script directly
echo "Setting up Dokploy for Railway environment..."

# Initialize Docker Swarm if not already initialized
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "Initializing Docker Swarm..."
    # Use the container's IP address for swarm init
    SWARM_IP=$(hostname -I | awk '{print $1}')
    docker swarm init --advertise-addr "$SWARM_IP" || {
        echo "WARNING: Swarm init failed, may already be initialized"
    }
fi

# Create Dokploy network
docker network create --driver overlay --attachable dokploy-network 2>/dev/null || {
    echo "Network dokploy-network already exists"
}

# Deploy Dokploy services
echo "Deploying Dokploy services..."

# Deploy PostgreSQL for Dokploy
docker service create \
    --name dokploy-postgres \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --env POSTGRES_USER=dokploy \
    --env POSTGRES_DB=dokploy \
    --env POSTGRES_PASSWORD=dokploy2024 \
    --mount type=volume,source=dokploy-postgres-database,target=/var/lib/postgresql/data \
    postgres:16 2>/dev/null || echo "Postgres service already exists"

# Deploy Redis for Dokploy
docker service create \
    --name dokploy-redis \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --mount type=volume,source=redis-data-volume,target=/data \
    redis:7 2>/dev/null || echo "Redis service already exists"

# Deploy Dokploy itself
docker service create \
    --name dokploy \
    --replicas 1 \
    --network dokploy-network \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
    --mount type=volume,source=dokploy-docker-config,target=/root/.docker \
    --publish published=${PORT:-3000},target=3000,mode=host \
    --update-parallelism 1 \
    --update-order stop-first \
    --constraint 'node.role == manager' \
    dokploy/dokploy:latest 2>/dev/null || echo "Dokploy service already exists"

# Deploy Traefik
docker run -d \
    --name dokploy-traefik \
    --network dokploy-network \
    --restart always \
    -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
    -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -p 80:80/tcp \
    -p 443:443/tcp \
    traefik:v3.1.2 2>/dev/null || echo "Traefik container already exists"

echo "Dokploy installation completed!"