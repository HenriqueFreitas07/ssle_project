#!/bin/bash
#
# Quick Attack Testing Script for Wazuh
# Usage: ./run-attack-tests.sh <apache_ip> <test_type>
#
# Test types: shellshock, dos, apt-recon, apt-exploit, apt-persist, all
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <apache_ip> <test_type>${NC}"
    echo ""
    echo "Test types:"
    echo "  shellshock    - Shellshock vulnerability tests"
    echo "  dos-light     - Light DoS tests (50-100 req)"
    echo "  dos-heavy     - Heavy DoS tests (200+ req)"
    echo "  apt-recon     - APT reconnaissance tests"
    echo "  apt-exploit   - APT exploitation tests (SQLi, XSS, CMDi)"
    echo "  apt-persist   - APT persistence tests (web shells)"
    echo "  all           - Run all tests (WARNING: may block your IP)"
    echo ""
    echo "Example: $0 10.244.0.10 shellshock"
    exit 1
fi

TARGET_IP="$1"
TEST_TYPE="$2"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Wazuh Attack Testing Script${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Target: ${YELLOW}$TARGET_IP${NC}"
echo -e "Test Type: ${YELLOW}$TEST_TYPE${NC}"
echo ""

# Test connectivity
echo -e "${BLUE}[*] Testing connectivity to target...${NC}"
if ! curl -s --connect-timeout 5 "http://$TARGET_IP/" > /dev/null 2>&1; then
    echo -e "${RED}[!] Cannot reach target at http://$TARGET_IP/${NC}"
    echo -e "${RED}[!] Please verify the IP address and network connectivity${NC}"
    exit 1
fi
echo -e "${GREEN}[+] Target is reachable${NC}"
echo ""

# Function to run Shellshock tests
run_shellshock_tests() {
    echo -e "${BLUE}=== SHELLSHOCK TESTS ===${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/3] Basic Shellshock pattern - Rule 100100${NC}"
    curl -s -H "User-Agent: () { :; }; echo vulnerable" "http://$TARGET_IP/" -o /dev/null
    echo -e "${GREEN}[+] Sent basic Shellshock pattern${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 2/3] Shellshock with command execution - Rule 100101${NC}"
    curl -s -H "User-Agent: () { :; }; /bin/bash -c 'whoami'" "http://$TARGET_IP/" -o /dev/null
    echo -e "${GREEN}[+] Sent Shellshock with bash command${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 3/3] Shellshock in multiple headers - Rule 100102${NC}"
    curl -s -H "Referer: () { :; }; echo test" "http://$TARGET_IP/" -o /dev/null
    curl -s -H "Cookie: session=() { :; }; /bin/sh" "http://$TARGET_IP/" -o /dev/null
    echo -e "${GREEN}[+] Sent Shellshock in various headers${NC}"

    echo ""
    echo -e "${GREEN}[+] Shellshock tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100100-100102 alerts (Level 15)${NC}"
    echo -e "${YELLOW}[!] Expected: IP blocked for 30 minutes${NC}"
    echo ""
}

# Function to run Light DoS tests
run_dos_light_tests() {
    echo -e "${BLUE}=== LIGHT DOS TESTS ===${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/2] Moderate HTTP flood - 60 requests in 10s - Rule 100200${NC}"
    echo -e "${BLUE}[*] Sending 60 requests...${NC}"
    for i in {1..60}; do
        curl -s "http://$TARGET_IP/" -o /dev/null &
    done
    wait
    echo -e "${GREEN}[+] Sent 60 requests${NC}"
    sleep 3

    echo -e "${YELLOW}[Test 2/2] Endpoint-specific flood - 35 requests to same URL - Rule 100203${NC}"
    for i in {1..35}; do
        curl -s "http://$TARGET_IP/index.html" -o /dev/null &
    done
    wait
    echo -e "${GREEN}[+] Sent 35 requests to same endpoint${NC}"

    echo ""
    echo -e "${GREEN}[+] Light DoS tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100200, 100203 alerts (Level 10-12)${NC}"
    echo -e "${YELLOW}[!] Expected: IP blocked for 5-10 minutes${NC}"
    echo ""
}

# Function to run Heavy DoS tests
run_dos_heavy_tests() {
    echo -e "${BLUE}=== HEAVY DOS TESTS ===${NC}"
    echo -e "${RED}[!] WARNING: This may impact service availability!${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/2] Heavy HTTP flood - 120 requests - Rule 100201${NC}"
    for i in {1..120}; do
        curl -s "http://$TARGET_IP/" -o /dev/null &
    done
    wait
    echo -e "${GREEN}[+] Sent 120 requests${NC}"
    sleep 3

    echo -e "${YELLOW}[Test 2/2] Aggressive flood - 250 requests - Rule 100202${NC}"
    for i in {1..250}; do
        curl -s "http://$TARGET_IP/" -o /dev/null &
    done
    wait
    echo -e "${GREEN}[+] Sent 250 requests${NC}"

    echo ""
    echo -e "${GREEN}[+] Heavy DoS tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100201-100202 alerts (Level 12-15)${NC}"
    echo -e "${YELLOW}[!] Expected: IP blocked for 10 minutes${NC}"
    echo ""
}

# Function to run APT Reconnaissance tests
run_apt_recon_tests() {
    echo -e "${BLUE}=== APT RECONNAISSANCE TESTS ===${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/3] Directory scanning - Rule 100300${NC}"
    for page in admin wp-admin phpMyAdmin administrator login panel dashboard backup config setup install database; do
        curl -s "http://$TARGET_IP/$page" -o /dev/null
        sleep 1
    done
    echo -e "${GREEN}[+] Scanned 11 directories${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 2/3] Vulnerable app scanning - Rule 100301${NC}"
    curl -s "http://$TARGET_IP/phpMyAdmin/" -o /dev/null
    curl -s "http://$TARGET_IP/wp-admin/" -o /dev/null
    curl -s "http://$TARGET_IP/cgi-bin/test.cgi" -o /dev/null
    curl -s "http://$TARGET_IP/shell.php" -o /dev/null
    curl -s "http://$TARGET_IP/webshell.php" -o /dev/null
    echo -e "${GREEN}[+] Scanned for vulnerable applications${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 3/3] Security scanner detection - Rule 100310${NC}"
    curl -s -A "Nikto/2.1.6" "http://$TARGET_IP/" -o /dev/null
    curl -s -A "sqlmap/1.0" "http://$TARGET_IP/" -o /dev/null
    curl -s -A "Metasploit/5.0" "http://$TARGET_IP/" -o /dev/null
    curl -s -A "Nmap Scripting Engine" "http://$TARGET_IP/" -o /dev/null
    echo -e "${GREEN}[+] Simulated security scanners${NC}"

    echo ""
    echo -e "${GREEN}[+] APT reconnaissance tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100300, 100301, 100310 alerts (Level 8-10)${NC}"
    echo ""
}

# Function to run APT Exploitation tests
run_apt_exploit_tests() {
    echo -e "${BLUE}=== APT EXPLOITATION TESTS ===${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/4] SQL Injection - Rule 100302${NC}"
    curl -s "http://$TARGET_IP/index.php?id=1' OR '1'='1" -o /dev/null
    curl -s "http://$TARGET_IP/search?q=admin'--" -o /dev/null
    curl -s "http://$TARGET_IP/user?id=1 UNION SELECT * FROM users" -o /dev/null
    echo -e "${GREEN}[+] Sent SQL injection payloads${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 2/4] Cross-Site Scripting - Rule 100303${NC}"
    curl -s "http://$TARGET_IP/search?q=<script>alert('XSS')</script>" -o /dev/null
    curl -s "http://$TARGET_IP/comment?text=<img src=x onerror=alert(1)>" -o /dev/null
    echo -e "${GREEN}[+] Sent XSS payloads${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 3/4] Command Injection - Rule 100304${NC}"
    curl -s "http://$TARGET_IP/ping.php?host=localhost;id" -o /dev/null
    curl -s "http://$TARGET_IP/exec?cmd=cat /etc/passwd" -o /dev/null
    curl -s "http://$TARGET_IP/run?command=ls|whoami" -o /dev/null
    echo -e "${GREEN}[+] Sent command injection payloads${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 4/4] Path Traversal - Rule 100305${NC}"
    curl -s "http://$TARGET_IP/file?name=../../../../etc/passwd" -o /dev/null
    curl -s "http://$TARGET_IP/download?file=../../etc/shadow" -o /dev/null
    echo -e "${GREEN}[+] Sent path traversal payloads${NC}"

    echo ""
    echo -e "${GREEN}[+] APT exploitation tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100302-100305 alerts (Level 10-12)${NC}"
    echo -e "${YELLOW}[!] Expected: IP blocked for 30 minutes (SQLi, CMDi)${NC}"
    echo ""
}

# Function to run APT Persistence tests
run_apt_persist_tests() {
    echo -e "${BLUE}=== APT PERSISTENCE TESTS ===${NC}"
    echo ""

    echo -e "${YELLOW}[Test 1/3] Web shell upload attempt - Rule 100306${NC}"
    curl -s -X POST -d "file=c99.php" "http://$TARGET_IP/upload" -o /dev/null
    curl -s -X POST -d "backdoor=r57shell" "http://$TARGET_IP/filemanager" -o /dev/null
    curl -s -X POST -d "webshell=b374k" "http://$TARGET_IP/admin/upload" -o /dev/null
    echo -e "${GREEN}[+] Simulated web shell uploads${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 2/3] Obfuscated payload - Rule 100307${NC}"
    curl -s -X POST -d "data=base64_decode('cm0gLXJmIC8=')" "http://$TARGET_IP/" -o /dev/null
    curl -s -X POST -d "payload=eval(atob('YWxlcnQoMSk='))" "http://$TARGET_IP/" -o /dev/null
    echo -e "${GREEN}[+] Sent obfuscated payloads${NC}"
    sleep 2

    echo -e "${YELLOW}[Test 3/3] Sensitive file access - Rule 100312${NC}"
    curl -s "http://$TARGET_IP/config.php.bak" -o /dev/null
    curl -s "http://$TARGET_IP/database.sql" -o /dev/null
    curl -s "http://$TARGET_IP/.env" -o /dev/null
    curl -s "http://$TARGET_IP/.git/config" -o /dev/null
    echo -e "${GREEN}[+] Attempted access to sensitive files${NC}"

    echo ""
    echo -e "${GREEN}[+] APT persistence tests completed${NC}"
    echo -e "${YELLOW}[!] Expected: Rule 100306, 100307, 100312 alerts (Level 10-14)${NC}"
    echo -e "${YELLOW}[!] Expected: IP blocked for 60 minutes (web shells)${NC}"
    echo ""
}

# Main test execution
case "$TEST_TYPE" in
    shellshock)
        run_shellshock_tests
        ;;
    dos-light)
        run_dos_light_tests
        ;;
    dos-heavy)
        run_dos_heavy_tests
        ;;
    apt-recon)
        run_apt_recon_tests
        ;;
    apt-exploit)
        run_apt_exploit_tests
        ;;
    apt-persist)
        run_apt_persist_tests
        ;;
    all)
        echo -e "${RED}[!] WARNING: Running ALL tests may block your IP for extended periods!${NC}"
        echo -e "${YELLOW}[?] Continue? (yes/no)${NC}"
        read -r response
        if [[ "$response" != "yes" ]]; then
            echo -e "${BLUE}[*] Tests cancelled${NC}"
            exit 0
        fi

        run_shellshock_tests
        sleep 5
        run_apt_recon_tests
        sleep 5
        run_apt_exploit_tests
        sleep 5
        run_apt_persist_tests
        sleep 5
        run_dos_light_tests
        ;;
    *)
        echo -e "${RED}[!] Invalid test type: $TEST_TYPE${NC}"
        echo -e "${YELLOW}Valid options: shellshock, dos-light, dos-heavy, apt-recon, apt-exploit, apt-persist, all${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}[+] Testing completed!${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Check Wazuh alerts: ${BLUE}tail -f /var/ossec/logs/alerts/alerts.log${NC}"
echo -e "2. Check blocked IPs: ${BLUE}iptables -L INPUT -n | grep <your_ip>${NC}"
echo -e "3. View active responses: ${BLUE}tail -f /var/ossec/logs/active-responses.log${NC}"
echo -e "4. Check Wazuh dashboard: ${BLUE}Security Events${NC}"
echo ""
echo -e "${YELLOW}[!] If your IP was blocked, wait for the timeout or manually remove:${NC}"
echo -e "    ${BLUE}iptables -D INPUT -s <your_ip> -j DROP${NC}"
echo ""
