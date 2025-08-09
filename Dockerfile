FROM ubuntu:24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=3000
ENV DOKPLOY_PORT=3000
ENV ADVERTISE_ADDR=[::]
ENV DOCKER_HOST=unix:///var/run/docker.sock

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    supervisor \
    iproute2 \
    net-tools \
    iputils-ping \
    dnsutils \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Docker
RUN curl -fsSL https://get.docker.com -o get-docker.sh && \
    sh get-docker.sh && \
    rm get-docker.sh

# Create app directory
WORKDIR /app

# Copy scripts
COPY scripts/ /app/scripts/
COPY .railway/ /app/.railway/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh /app/.railway/*.sh

# Expose ports
EXPOSE 3000 80 443

# Create volume for persistent data
VOLUME ["/etc/dokploy", "/var/lib/docker"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /app/scripts/healthcheck.sh

# Use entrypoint script
ENTRYPOINT ["/app/scripts/entrypoint.sh"]