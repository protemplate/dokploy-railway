FROM ubuntu:24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV DOKPLOY_PORT=3000

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    supervisor \
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

# Install Dokploy
RUN /app/scripts/install-dokploy.sh

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /app/scripts/healthcheck.sh

# Start command
CMD ["/app/.railway/deploy.sh"]