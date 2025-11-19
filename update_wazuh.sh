#!/bin/bash

set -e  # Exit on error

# Function to log info messages
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

WAZUH_IP=$(incus list wazuh-container -c 4 -f csv | grep eth0 | cut -d' ' -f1)
# Validate required variables
if [ -z "$WAZUH_IP" ]; then
    log_error "WAZUH_IP environment variable is not set"
    exit 1
fi

# Validate required files exist
if [ ! -f "./wazuh-config/ossec.conf" ]; then
    log_error "Required file not found: ./wazuh-config/ossec.conf"
    exit 1
fi

if [ ! -f "./wazuh-config/local_rules.xml" ]; then
    log_error "Required file not found: ./wazuh-config/local_rules.xml"
    exit 1
fi

# Validate container exists
if ! incus list | grep -q "wazuh-container"; then
    log_error "Container 'wazuh-container' not found"
    exit 1
fi

log_info "Reading configuration files..."

# Read and substitute NODE_IP in ossec.conf
CONFIG=$(cat "./wazuh-config/ossec.conf" | sed "s/NODE_IP/$WAZUH_IP/g")

# Read custom rules
CUSTOM_RULES=$(cat "./wazuh-config/local_rules.xml")


log_info "Applying custom ossec.conf configuration..."
echo "$CONFIG" | incus exec wazuh-container -- bash -c 'cat > /var/ossec/etc/ossec.conf'

log_info "Applying custom rules to the server..." 
echo "$CUSTOM_RULES" | incus exec wazuh-container -- bash -c 'cat > /var/ossec/etc/rules/local_rules.xml'

log_info "Restarting Wazuh manager to apply changes..."
incus exec wazuh-container -- systemctl restart wazuh-manager

log_info "Waiting for Wazuh manager to start..."
sleep 5

log_info "Verifying Wazuh manager status..."
if incus exec wazuh-container -- systemctl is-active --quiet wazuh-manager; then
    log_info "✓ Wazuh manager is running"
    incus exec wazuh-container -- systemctl status wazuh-manager --no-pager | head -10
else
    log_error "✗ Wazuh manager failed to start"
    log_error "Checking logs..."
    incus exec wazuh-container -- tail -50 /var/ossec/logs/ossec.log
    exit 1
fi

log_info "Verifying active response configuration..."
incus exec wazuh-container -- bash -c '
    echo "Configured active responses:"
    grep -A 5 "<active-response>" /var/ossec/etc/ossec.conf | grep -E "(command|rules_id|timeout)"
'

log_info "Checking for active response scripts..."
incus exec wazuh-container -- bash -c '
    echo ""
    echo "Available active response scripts:"
    ls -la /var/ossec/active-response/bin/ | grep -E "(firewall-drop|host-deny|route-null)"
'

log_info "Configuration applied successfully!"
log_info ""
log_info "Next steps:"
log_info "  1. Test rules with: incus exec wazuh-container -- /var/ossec/bin/wazuh-logtest"
log_info "  2. Monitor alerts: incus exec wazuh-container -- tail -f /var/ossec/logs/alerts/alerts.log"
log_info "  3. Check active responses: incus exec wazuh-container -- tail -f /var/ossec/logs/active-responses.log"
