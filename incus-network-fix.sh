#!/bin/bash

# Incus Network Troubleshooting and Fix Script
# This script diagnoses and fixes networking issues with Incus when Docker is present

set -e

echo "=== Incus Network Diagnostic and Fix Script ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "1. Current Network Configuration:"
echo "=================================="
echo ""
echo "Incus bridge (incusbr0):"
ip addr show incusbr0 | grep -E "inet |state"
echo ""

echo "IP Forwarding enabled: $(cat /proc/sys/net/ipv4/ip_forward)"
echo ""

echo "2. Checking Firewall Backend:"
echo "============================="
IPTABLES_VERSION=$(iptables --version)
echo "$IPTABLES_VERSION"
echo ""

echo "3. Current FORWARD Chain Policy:"
echo "================================="
iptables -L FORWARD -n -v | head -5
echo ""

echo "4. Current NAT Rules (POSTROUTING):"
echo "===================================="
iptables -t nat -L POSTROUTING -n -v
echo ""

echo "5. Testing Container Connectivity:"
echo "==================================="
CONTAINER_NAME=$(incus list -c n --format csv | head -1)
if [ -z "$CONTAINER_NAME" ]; then
    echo "No containers found. Please start at least one container."
    exit 1
fi

echo "Using container: $CONTAINER_NAME"
echo ""

echo "Ping to gateway (10.10.10.1):"
incus exec "$CONTAINER_NAME" -- ping -c 2 10.10.10.1 2>&1 | tail -2
echo ""

echo "Ping to external IP (8.8.8.8):"
if incus exec "$CONTAINER_NAME" -- ping -c 2 8.8.8.8 2>&1 | grep -q "2 received"; then
    echo "SUCCESS: External connectivity is working!"
    exit 0
else
    echo "FAILED: No external connectivity"
fi
echo ""

echo "=== APPLYING FIX ==="
echo ""

# The issue is likely that Docker's iptables rules are blocking forwarding
# or NAT is not properly configured for incusbr0

echo "6. Ensuring proper iptables rules for Incus:"
echo "============================================="

# Ensure FORWARD chain accepts traffic for incusbr0
echo "Adding FORWARD rules for incusbr0..."
iptables -I FORWARD -i incusbr0 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD -o incusbr0 -j ACCEPT 2>/dev/null || true

# Ensure NAT is set up for incusbr0
echo "Adding POSTROUTING NAT rule for incusbr0..."
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 ! -d 10.10.10.0/24 -j MASQUERADE 2>/dev/null || true

echo ""
echo "7. Verifying fix:"
echo "================="
echo "Testing external connectivity again..."
sleep 1

if incus exec "$CONTAINER_NAME" -- ping -c 2 8.8.8.8 2>&1 | grep -q "2 received"; then
    echo ""
    echo "SUCCESS: External connectivity is now working!"
    echo ""
    echo "To make these changes persistent across reboots, consider:"
    echo "1. Using iptables-persistent package (Debian/Ubuntu)"
    echo "2. Adding rules to /etc/nftables.conf (if using nftables)"
    echo "3. Creating a systemd service to apply rules at boot"
    echo "4. Configuring Docker to use a different iptables backend"
else
    echo ""
    echo "FAILED: Issue persists. Additional debugging needed."
    echo ""
    echo "Possible causes:"
    echo "- Firewall blocking at kernel level"
    echo "- Docker daemon configuration conflict"
    echo "- Network namespace issues"
    echo "- nftables rules overriding iptables"
    echo ""
    echo "Try checking: nft list ruleset"
fi
