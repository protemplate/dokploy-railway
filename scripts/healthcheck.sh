#!/bin/bash

# Check if Dokploy is responding
if curl -f http://localhost:3000/health >/dev/null 2>&1; then
    echo "Dokploy is healthy"
    exit 0
else
    echo "Dokploy is not responding"
    exit 1
fi