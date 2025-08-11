#!/bin/bash
set -e

echo "==============================================="
echo "Installing Dokploy on Railway"
echo "==============================================="

# Check if Docker is available
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running. Cannot install Dokploy."
    exit 1
fi

# Railway-specific environment setup
echo "Setting up Dokploy for Railway environment..."

# Determine advertise address for Docker Swarm
echo "Determining advertise address for Docker Swarm..."

# Use helper script if available
if [ -f /app/scripts/get-container-ip.sh ]; then
    ADVERTISE_ADDR=$(/app/scripts/get-container-ip.sh | tail -n1)
else
    # Fallback to simple detection
    ADVERTISE_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ADVERTISE_ADDR" ]; then
        ADVERTISE_ADDR="127.0.0.1"
    fi
fi

# Validate the IP address
if [ "$ADVERTISE_ADDR" = "127.0.0.1" ]; then
    echo "WARNING: Using localhost as advertise address. Swarm may have limited functionality."
elif echo "$ADVERTISE_ADDR" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    echo "Using IPv4 address: $ADVERTISE_ADDR"
else
    echo "WARNING: Invalid IP address detected: $ADVERTISE_ADDR"
    ADVERTISE_ADDR="127.0.0.1"
fi

echo "Advertise address: $ADVERTISE_ADDR"

# Initialize Docker Swarm if not already initialized
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "Initializing Docker Swarm..."
    docker swarm init --advertise-addr "$ADVERTISE_ADDR" || {
        echo "WARNING: Swarm init failed, may already be initialized"
        # Try to leave and reinitialize if needed
        docker swarm leave --force 2>/dev/null || true
        docker swarm init --advertise-addr "$ADVERTISE_ADDR"
    }
else
    echo "Docker Swarm already active"
fi

# Create Dokploy network using host network driver for Railway
echo "Creating Dokploy network..."
# In Railway, we use host networking since bridge is disabled
docker network create --driver host dokploy-network 2>/dev/null || {
    # If host network fails, try overlay (for Swarm mode)
    docker network create --driver overlay --attachable dokploy-network 2>/dev/null || {
        echo "Network dokploy-network already exists or using default"
    }
}

# Ensure required directories exist with proper permissions
mkdir -p /etc/dokploy
mkdir -p /etc/dokploy/traefik
mkdir -p /etc/dokploy/traefik/dynamic

# Deploy Dokploy services
echo "==============================================="
echo "Deploying Dokploy services..."
echo "==============================================="

# Deploy PostgreSQL for Dokploy
echo "Deploying PostgreSQL..."
docker service create \
    --name dokploy-postgres \
    --replicas 1 \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --env POSTGRES_USER=dokploy \
    --env POSTGRES_DB=dokploy \
    --env POSTGRES_PASSWORD=dokploy2024 \
    --mount type=volume,source=dokploy-postgres-database,target=/var/lib/postgresql/data \
    --restart-condition any \
    --restart-delay 5s \
    postgres:16 2>/dev/null || {
    echo "Postgres service already exists, updating..."
    docker service update dokploy-postgres --force 2>/dev/null || true
}

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 10

# Deploy Redis for Dokploy
echo "Deploying Redis..."
docker service create \
    --name dokploy-redis \
    --replicas 1 \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --mount type=volume,source=redis-data-volume,target=/data \
    --restart-condition any \
    --restart-delay 5s \
    redis:7 2>/dev/null || {
    echo "Redis service already exists, updating..."
    docker service update dokploy-redis --force 2>/dev/null || true
}

# Wait for Redis to be ready
echo "Waiting for Redis to be ready..."
sleep 5

# Deploy Dokploy main application
echo "Deploying Dokploy application..."
docker service create \
    --name dokploy \
    --replicas 1 \
    --network dokploy-network \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
    --mount type=volume,source=dokploy-docker-config,target=/root/.docker \
    --publish published=${PORT:-3000},target=3000,mode=host \
    --env DATABASE_URL="postgresql://dokploy:dokploy2024@dokploy-postgres:5432/dokploy" \
    --env REDIS_URL="redis://dokploy-redis:6379" \
    --env SERVER_IP="${ADVERTISE_ADDR}" \
    --env DOCKER_HOST="unix:///var/run/docker.sock" \
    --update-parallelism 1 \
    --update-order stop-first \
    --constraint 'node.role == manager' \
    --restart-condition any \
    --restart-delay 5s \
    dokploy/dokploy:latest 2>/dev/null || {
    echo "Dokploy service already exists, updating..."
    docker service update dokploy --force 2>/dev/null || true
}

# Create Traefik configuration
echo "Configuring Traefik..."
cat > /etc/dokploy/traefik/traefik.yml <<EOF
api:
  dashboard: false

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    swarmMode: true
    exposedByDefault: false
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true

log:
  level: INFO

accessLog: {}
EOF

# Deploy Traefik as a service (not container) for better Railway integration
echo "Deploying Traefik..."
docker service create \
    --name dokploy-traefik \
    --replicas 1 \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --mount type=bind,source=/etc/dokploy/traefik/traefik.yml,target=/etc/traefik/traefik.yml,readonly \
    --mount type=bind,source=/etc/dokploy/traefik/dynamic,target=/etc/dokploy/traefik/dynamic,readonly \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly \
    --publish published=80,target=80,mode=host \
    --publish published=443,target=443,mode=host \
    --restart-condition any \
    --restart-delay 5s \
    traefik:v3.1.2 2>/dev/null || {
    echo "Traefik service already exists, updating..."
    docker service update dokploy-traefik --force 2>/dev/null || true
}

echo "==============================================="
echo "Dokploy installation completed!"
echo "==============================================="
echo ""
echo "Services deployed:"
docker service ls | grep dokploy
echo ""
echo "Access Dokploy at: http://localhost:${PORT:-3000}"
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    echo "Railway URL: https://$RAILWAY_PUBLIC_DOMAIN"
fi