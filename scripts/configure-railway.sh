#!/bin/bash
set -e

echo "Configuring Dokploy for Railway environment..."

# Check if running on Railway
if [ -n "$RAILWAY_ENVIRONMENT" ]; then
    echo "Railway environment detected: $RAILWAY_ENVIRONMENT"
    
    # Docker configuration is now handled in entrypoint.sh
    echo "Docker will be configured for Railway environment"
    
    # Configure Traefik for dual-stack
    mkdir -p /etc/dokploy/traefik/dynamic
    cat > /etc/dokploy/traefik/traefik.yml <<EOF
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  debug: false

entryPoints:
  web:
    address: "[::]:80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: "[::]:443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@dokploy.local
      storage: /etc/dokploy/traefik/acme.json
      httpChallenge:
        entryPoint: web
EOF
    echo "Traefik configured for Railway"
    
    # Set proper permissions
    chmod 600 /etc/dokploy/traefik/acme.json 2>/dev/null || touch /etc/dokploy/traefik/acme.json && chmod 600 /etc/dokploy/traefik/acme.json
    
    # Configure network settings for IPv6 (if we have permission)
    if [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
        sysctl -w net.ipv6.conf.default.disable_ipv6=0
        sysctl -w net.ipv6.conf.all.forwarding=1
    else
        echo "Cannot modify sysctl settings (read-only filesystem) - skipping"
    fi
    
    echo "Railway configuration completed"
else
    echo "Not running on Railway, using default configuration"
fi