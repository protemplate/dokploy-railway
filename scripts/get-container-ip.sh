#!/bin/bash

# Helper script to get container IP address for Docker Swarm

echo "Detecting container IP address..."

# Method 1: hostname -I
IP1=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$IP1" ]; then
    echo "  Method 1 (hostname -I): $IP1"
fi

# Method 2: ip addr show
IP2=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
if [ -n "$IP2" ]; then
    echo "  Method 2 (ip addr): $IP2"
fi

# Method 3: ip route
IP3=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+')
if [ -n "$IP3" ]; then
    echo "  Method 3 (ip route): $IP3"
fi

# Method 4: Network interfaces
IP4=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n1)
if [ -n "$IP4" ]; then
    echo "  Method 4 (ifconfig): $IP4"
fi

# Select the first available IP
for IP in $IP1 $IP2 $IP3 $IP4; do
    if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
        echo "Selected IP: $IP"
        echo "$IP"
        exit 0
    fi
done

# Fallback to localhost
echo "No external IP found, using localhost"
echo "127.0.0.1"