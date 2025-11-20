#!/bin/bash
#
# Setup Incus Attacker Container for Wazuh Testing
# This script creates an Incus container with attack tools installed
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Incus Attacker Container Setup${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if incus is installed
if ! command -v incus &> /dev/null; then
    echo -e "${RED}[!] Incus is not installed or not in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Incus detected${NC}"
echo ""

# Check if container already exists
if incus list | grep -q "attacker"; then
    echo -e "${YELLOW}[!] Container 'attacker' already exists${NC}"
    echo -e "${YELLOW}[?] Do you want to delete it and create a new one? (yes/no)${NC}"
    read -r response
    if [[ "$response" == "yes" ]]; then
        echo -e "${BLUE}[*] Stopping and deleting existing container...${NC}"
        incus stop attacker 2>/dev/null || true
        incus delete attacker
        echo -e "${GREEN}[+] Old container removed${NC}"
    else
        echo -e "${BLUE}[*] Using existing container${NC}"
        exit 0
    fi
fi

echo -e "${BLUE}[*] Creating Incus container 'attacker'...${NC}"

# Launch Ubuntu container (Alpine can also be used)
incus launch images:ubuntu/22.04 attacker

echo -e "${YELLOW}[*] Waiting for container to start...${NC}"
sleep 5

# Wait for network to be ready
echo -e "${YELLOW}[*] Waiting for network connectivity...${NC}"
for i in {1..30}; do
    if incus exec attacker -- ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "${GREEN}[+] Network is ready${NC}"
        break
    fi
    sleep 2
done

echo -e "${BLUE}[*] Installing attack tools...${NC}"

# Install required packages
incus exec attacker -- bash -c "
    apt-get update -qq
    apt-get install -y curl wget apache2-utils netcat nmap dnsutils hping3 \
        build-essential python3 python3-pip git net-tools iproute2 \
        iptables traceroute telnet tcpdump nikto sqlmap
"

echo -e "${GREEN}[+] Basic tools installed${NC}"

# Install additional Python tools
echo -e "${BLUE}[*] Installing Python attack tools...${NC}"
incus exec attacker -- bash -c "
    pip3 install --quiet slowloris requests
" 2>/dev/null || echo -e "${YELLOW}[!] Some Python tools may have failed (non-critical)${NC}"

echo ""
echo -e "${GREEN}[+] Attacker container created successfully!${NC}"
echo ""

# Get container IP
ATTACKER_IP=$(incus list attacker -c 4 | grep eth0 | awk '{print $1}')
echo -e "${YELLOW}Attacker Container IP:${NC} ${BLUE}$ATTACKER_IP${NC}"
echo ""

# Show Apache container info if it exists
echo -e "${BLUE}[*] Looking for Apache container...${NC}"
if incus list | grep -i apache &>/dev/null; then
    APACHE_NAME=$(incus list | grep -i apache | awk '{print $2}' | head -1)
    APACHE_IP=$(incus list $APACHE_NAME -c 4 | grep eth0 | awk '{print $1}')
    echo -e "${GREEN}[+] Found Apache container: ${BLUE}$APACHE_NAME${NC}"
    echo -e "${YELLOW}Apache IP:${NC} ${BLUE}$APACHE_IP${NC}"
    echo ""
else
    echo -e "${YELLOW}[!] No Apache container found. You'll need to find the IP manually.${NC}"
    echo ""
fi

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

echo -e "${YELLOW}Quick Start Commands:${NC}"
echo ""
echo -e "1. ${BLUE}Access the attacker container:${NC}"
echo -e "   incus exec attacker -- bash"
echo ""

echo -e "2. ${BLUE}Copy test script to container:${NC}"
echo -e "   incus file push run-attack-tests.sh attacker/root/"
echo ""

echo -e "3. ${BLUE}Run tests from inside container:${NC}"
echo -e "   incus exec attacker -- bash /root/run-attack-tests.sh <apache-ip> shellshock"
echo ""

if [ -n "$APACHE_IP" ]; then
    echo -e "4. ${BLUE}Quick Shellshock test (using detected Apache IP):${NC}"
    echo -e "   incus exec attacker -- curl -H \"User-Agent: () { :; }; echo test\" http://$APACHE_IP/"
    echo ""
fi

echo -e "${YELLOW}List all containers:${NC}"
echo -e "   incus list"
echo ""

echo -e "${YELLOW}Stop and delete attacker when done:${NC}"
echo -e "   incus stop attacker && incus delete attacker"
echo ""

echo -e "${RED}[!] Remember: Only test systems you own or have permission to test!${NC}"
echo ""
