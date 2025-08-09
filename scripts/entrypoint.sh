#!/bin/bash
set -e

# Configure Railway-specific settings if needed
if [ -f /app/scripts/configure-railway.sh ]; then
    /app/scripts/configure-railway.sh
fi

echo "Starting Docker daemon with IPv6 support..."
# Configure Docker daemon for Railway's IPv6 networking
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80",
  "experimental": true,
  "ip6tables": true
}
EOF

# Start Docker daemon in the background
dockerd &
DOCKER_PID=$!

# Wait for Docker to be ready
echo "Waiting for Docker daemon to be ready..."
while ! docker info >/dev/null 2>&1; do
    sleep 1
done
echo "Docker daemon is ready!"

# Check if Dokploy is already installed
if [ ! -f /etc/dokploy/.installed ]; then
    echo "First time setup - Installing Dokploy..."
    
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
    
    # Install Dokploy
    /app/scripts/install-dokploy.sh
    
    # Mark as installed
    mkdir -p /etc/dokploy
    touch /etc/dokploy/.installed
    
    echo "Dokploy installation completed!"
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
while ! curl -s http://[::1]:${PORT:-3000} >/dev/null 2>&1 && ! curl -s http://localhost:${PORT:-3000} >/dev/null 2>&1; do
    sleep 2
done
echo "Dokploy is ready!"

# Display access information
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    echo "Dokploy is accessible at: https://$RAILWAY_PUBLIC_DOMAIN"
else
    echo "Dokploy is running on port ${PORT:-3000}"
fi

# Keep the container running
wait $DOCKER_PID