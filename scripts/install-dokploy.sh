#!/bin/bash
set -e

echo "Installing Dokploy..."

# Download and run Dokploy installation script
curl -sSL https://dokploy.com/install.sh | bash

echo "Dokploy installation completed!"