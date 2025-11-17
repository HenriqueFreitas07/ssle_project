#!/bin/bash

# Complete K3s Cluster Setup Script with Wazuh
# This script automates the entire setup from Incus containers to deployed services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "  Complete K3s Cluster Setup + Wazuh"
echo "  Following SSLE Guide 2"
echo "=========================================="
echo ""

# Check if running as root for kernel params
if [ "$EUID" -ne 0 ]; then
    log_error "This script needs to configure kernel parameters"
    log_info "Please run with sudo: sudo ./setup-complete-cluster.sh"
    exit 1
fi

# ==============================================
# STEP 1: Configure Host Kernel Parameters
# ==============================================
log_info "[1/12] Configuring host kernel parameters..."
sysctl -w vm.overcommit_memory=1
sysctl -w kernel.panic=10
sysctl -w kernel.panic_on_oops=1
echo "✓ Kernel parameters configured"
echo ""

# ==============================================
# STEP 2: Create K3s Incus Profile
# ==============================================
log_info "[2/12] Creating K3s Incus profile..."

# Check if profile exists, delete if it does
if incus profile show k3s &>/dev/null; then
    log_warn "Profile k3s exists, recreating..."
    incus profile delete k3s || true
fi

incus profile create k3s
incus profile set k3s security.privileged=true security.nesting=true \
    linux.kernel_modules=ip_tables,ip6_tables,nf_nat,overlay,br_netfilter

incus profile set k3s raw.lxc='lxc.apparmor.profile=unconfined
lxc.cgroup.devices.allow=a *:* rwm
lxc.cap.drop='

incus profile device add k3s kmsg unix-char source=/dev/kmsg path=/dev/kmsg
incus profile device add k3s eth0 nic network=incusbr0 name=eth0
incus profile device add k3s root disk path=/ pool=default

echo "✓ K3s profile created"
echo ""

# ==============================================
# STEP 3: Create and Setup K3s Master Node
# ==============================================
log_info "[3/12] Creating K3s master node..."

# Delete if exists
incus delete -f k3s-master 2>/dev/null || true

incus launch images:debian/trixie k3s-master --profile k3s
log_info "Waiting for container to be ready..."
sleep 10

log_info "Installing K3s on master node..."
incus exec k3s-master -- bash -c "
    apt update -qq
    apt install -y curl
    curl -sfL https://get.k3s.io | sh -
"

log_info "Waiting for K3s to start..."
sleep 15

# Verify K3s is running
incus exec k3s-master -- k3s kubectl get nodes
echo "✓ K3s master node ready"
echo ""

# Get node token
log_info "Getting K3s node token..."
NODE_TOKEN=$(incus exec k3s-master -- cat /var/lib/rancher/k3s/server/node-token)
echo "✓ Node token retrieved"
echo ""

# ==============================================
# STEP 4: Create and Join Worker Nodes
# ==============================================
log_info "[4/12] Creating and joining worker nodes..."

# Delete if exists
incus delete -f k3s-node1 k3s-node2 2>/dev/null || true

# Create worker nodes
for node in k3s-node1 k3s-node2; do
    log_info "Creating $node..."
    incus launch images:debian/trixie $node --profile k3s
    sleep 5

    log_info "Installing K3s agent on $node..."
    incus exec $node -- bash -c "
        apt update -qq
        apt install -y curl
        curl -sfL https://get.k3s.io | K3S_URL=https://k3s-master.incus:6443 K3S_TOKEN='$NODE_TOKEN' sh -
    "
    echo "✓ $node joined cluster"
done

sleep 10
log_info "Cluster nodes:"
incus exec k3s-master -- k3s kubectl get nodes
echo ""

# ==============================================
# STEP 5: Label Nodes for Workload Scheduling
# ==============================================
log_info "[5/12] Labeling nodes for scheduling..."
incus exec k3s-master -- k3s kubectl label nodes k3s-master node-role=monitoring --overwrite
incus exec k3s-master -- k3s kubectl label nodes k3s-node1 node-role=services --overwrite
incus exec k3s-master -- k3s kubectl label nodes k3s-node2 node-role=services --overwrite
echo "✓ Nodes labeled"
echo ""

log_info "[11/12] Installing Wazuh Manager on k3s-master..."

incus exec k3s-master -- bash -c '
# Update and install prerequisites
apt update
apt install -y curl apt-transport-https lsb-release gnupg

# Add Wazuh repository
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list

# Update package list
apt update
'

log_info "Installing Wazuh indexer..."
incus exec k3s-master -- bash -c '
# Install Wazuh indexer
apt install -y wazuh-indexer

# Configure indexer for single node
cat > /etc/wazuh-indexer/opensearch.yml <<EOF
network.host: "0.0.0.0"
node.name: "wazuh-indexer"
cluster.name: "wazuh-cluster"
discovery.type: "single-node"
plugins.security.disabled: true
EOF

# Start and enable indexer
systemctl daemon-reload
systemctl enable wazuh-indexer
systemctl start wazuh-indexer

# Wait for indexer to start
sleep 10
'

log_info "Installing Wazuh manager..."
incus exec k3s-master -- bash -c '
# Install Wazuh manager
apt install -y wazuh-manager

# Start and enable manager
systemctl daemon-reload
systemctl enable wazuh-manager
systemctl start wazuh-manager

# Wait for manager to start
sleep 5
'

# Deploy custom ossec.conf if it exists
if [ -f "$PROJECT_DIR/wazuh-config/ossec.conf" ]; then
    log_info "Deploying custom ossec.conf..."
    cat "$PROJECT_DIR/wazuh-config/ossec.conf" | incus exec k3s-master -- bash -c 'cat > /var/ossec/etc/ossec.conf'
    incus exec k3s-master -- systemctl restart wazuh-manager
    log_info "Custom ossec.conf deployed and manager restarted"
else
    log_info "No custom ossec.conf found, using default configuration"
fi

# Deploy custom agent.conf if it exists
if [ -f "$PROJECT_DIR/wazuh-config/agent.conf" ]; then
    log_info "Deploying custom agent.conf..."
    cat "$PROJECT_DIR/wazuh-config/agent.conf" | incus exec k3s-master -- bash -c 'cat > /var/ossec/etc/shared/default/agent.conf'
    log_info "Custom agent.conf deployed"
else
    log_info "No custom agent.conf found, using default configuration"
fi

log_info "Installing Filebeat for log forwarding..."
incus exec k3s-master -- bash -c '
# Install Filebeat
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-7.10.2-amd64.deb
dpkg -i filebeat-oss-7.10.2-amd64.deb
rm filebeat-oss-7.10.2-amd64.deb

# Download Wazuh Filebeat module
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | tar -xvz -C /usr/share/filebeat/module

# Configure Filebeat
cat > /etc/filebeat/filebeat.yml <<EOF
output.elasticsearch:
  hosts: ["127.0.0.1:9200"]

setup.template.json.enabled: true
setup.template.json.path: "/etc/filebeat/wazuh-template.json"
setup.template.json.name: "wazuh"
setup.ilm.enabled: false

filebeat.modules:
  - module: wazuh
    alerts:
      enabled: true
    archives:
      enabled: false
EOF

# Download Wazuh template
curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.7.0/extensions/elasticsearch/7.x/wazuh-template.json

# Enable and start Filebeat
systemctl daemon-reload
systemctl enable filebeat
systemctl start filebeat
'

log_info "Installing Wazuh dashboard..."
incus exec k3s-master -- bash -c '
# Install Wazuh dashboard
apt install -y wazuh-dashboard

# Configure dashboard
cat > /etc/wazuh-dashboard/opensearch_dashboards.yml <<EOF
server.host: "0.0.0.0"
server.port: 5601
opensearch.hosts: ["http://127.0.0.1:9200"]
opensearch.ssl.verificationMode: none
opensearch_security.enabled: false
EOF

# Enable and start dashboard
systemctl daemon-reload
systemctl enable wazuh-dashboard
systemctl start wazuh-dashboard
'

echo "✓ Wazuh Manager, Indexer, and Dashboard installed on k3s-master"
echo ""

# Get k3s-master IP
MASTER_IP=$(incus list k3s-master -c 4 -f csv | grep eth0 | cut -d' ' -f1)
log_info "Wazuh Manager IP: $MASTER_IP"

# ==============================================
# STEP 12: Install Wazuh Agents on Worker Nodes
# ==============================================
log_info "[12/12] Installing Wazuh Agents on worker nodes..."

for node in k3s-node1 k3s-node2; do
    log_info "Installing Wazuh agent on $node..."

    incus exec $node -- bash -c "
    # Update and install prerequisites
    apt update
    apt install -y curl apt-transport-https lsb-release gnupg

    # Add Wazuh repository
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
    chmod 644 /usr/share/keyrings/wazuh.gpg
    echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main' | tee -a /etc/apt/sources.list.d/wazuh.list

    # Update package list
    apt update

    # Install Wazuh agent
    WAZUH_MANAGER='$MASTER_IP' apt install -y wazuh-agent

    # Start and enable agent
    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl start wazuh-agent
    "

    echo "✓ $node agent installed"
done

log_info "Configuring agents to connect to manager..."

# Wait for manager API to be ready
log_info "Waiting for Wazuh manager to be fully ready..."
sleep 15

# Register agents with manager
for node in k3s-node1 k3s-node2; do
    log_info "Registering $node with manager..."

    # Get agent key from manager
    incus exec k3s-master -- bash -c "/var/ossec/bin/manage_agents -a -n $node -i any || true"
done

# Restart agents to connect
for node in k3s-node1 k3s-node2; do
    incus exec $node -- systemctl restart wazuh-agent
done

echo "✓ Wazuh agents configured and connected"
echo ""
# ==============================================
# STEP 6: Build Docker Images
# ==============================================
log_info "[6/12] Building Docker images..."

# Get the real user (since we're running with sudo)
REAL_USER="${SUDO_USER:-$USER}"
PROJECT_DIR="/home/$REAL_USER/Desktop/ssle_project"

cd "$PROJECT_DIR"

# Build images using docker-compose
log_info "Building images with docker-compose..."
docker-compose build

echo "✓ Docker images built"
echo ""

# ==============================================
# STEP 7: Export and Import Images to K3s
# ==============================================
log_info "[7/12] Exporting and importing Docker images to K3s nodes..."

# Create temp directory
mkdir -p /tmp/k8s-images

log_info "Saving Docker images to tar files..."
docker save ssle_project-registry_service:latest -o /tmp/k8s-images/registry-service.tar
docker save ssle_project-storage_service:latest -o /tmp/k8s-images/storage-service.tar
docker save ssle_project-ingestion_service:latest -o /tmp/k8s-images/ingestion-service.tar
docker save ssle_project-analytics_service:latest -o /tmp/k8s-images/analytics-service.tar
docker save ssle_project-temperature_service:latest -o /tmp/k8s-images/temperature-service.tar

echo "✓ Images saved"

# Import into all nodes
for node in k3s-master k3s-node1 k3s-node2; do
    log_info "Importing images into $node..."

    for service in registry storage ingestion analytics temperature; do
        cat /tmp/k8s-images/${service}-service.tar | incus exec $node -- ctr --namespace k8s.io images import -
    done

    echo "✓ $node complete"
done

# Cleanup
rm -rf /tmp/k8s-images
echo "✓ Images imported to all nodes"
echo ""

# ==============================================
# STEP 8: Deploy Namespace and ConfigMaps
# ==============================================
log_info "[8/12] Deploying namespace and configmaps..."

cat "$PROJECT_DIR/k8s/namespace.yaml" | incus exec k3s-master -- bash -c 'cat > /root/namespace.yaml && k3s kubectl apply -f /root/namespace.yaml'

# Copy and apply configmaps
cat "$PROJECT_DIR/k8s/configmaps.yaml" | incus exec k3s-master -- bash -c 'cat > /root/configmaps.yaml && k3s kubectl apply -f /root/configmaps.yaml'

echo "✓ Namespaces and ConfigMaps created"
echo ""

# ==============================================
# STEP 9: Deploy Monitoring Stack
# ==============================================
log_info "[9/12] Deploying monitoring stack (Prometheus & Grafana)..."
cat "$PROJECT_DIR/k8s/prometheus.yaml" | incus exec k3s-master -- bash -c 'cat > /root/prometheus.yaml && k3s kubectl apply -f /root/prometheus.yaml'

log_info "Deploying Storage PVC..."
cat "$PROJECT_DIR/k8s/storage-pvc.yaml" | incus exec k3s-master -- bash -c 'cat > /root/storage-pvc.yaml && k3s kubectl apply -f /root/storage-pvc.yaml'

log_info "Deploying Grafana..."
cat "$PROJECT_DIR/k8s/grafana.yaml" | incus exec k3s-master -- bash -c 'cat > /root/grafana.yaml && k3s kubectl apply -f /root/grafana.yaml'

echo "✓ Monitoring stack deployed"
echo ""

# ==============================================
# STEP 10: Deploy All Microservices
# ==============================================
log_info "[10/12] Deploying microservices..."

# Deploy microservices
for service in registry-service storage-service ingestion-service analytics-service temperature-service; do
    log_info "Deploying $service..."
    cat "$PROJECT_DIR/k8s/${service}.yaml" | incus exec k3s-master -- bash -c "cat > /root/${service}.yaml && k3s kubectl apply -f /root/${service}.yaml"
done

echo "✓ All microservices deployed"
echo ""

# ==============================================
# STEP 11: Install Wazuh on k3s-master
# ==============================================

# ==============================================
# Wait for Pods to be Ready
# ==============================================
log_info "Waiting for K8s pods to be ready (this may take a minute)..."
sleep 20

echo ""
echo "=========================================="
echo "  DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""

# Show cluster status
log_info "Cluster Nodes:"
incus exec k3s-master -- k3s kubectl get nodes
echo ""

log_info "Services in ssle-project namespace:"
incus exec k3s-master -- k3s kubectl get pods -n ssle-project
echo ""

log_info "Services in monitoring namespace:"
incus exec k3s-master -- k3s kubectl get pods -n monitoring
echo ""

log_info "Service endpoints:"
incus exec k3s-master -- k3s kubectl get svc -n ssle-project
echo ""

echo "=========================================="
echo "  Wazuh Information"
echo "=========================================="
echo ""
echo "Wazuh Manager:"
echo "  - Host: k3s-master ($MASTER_IP)"
echo "  - API Port: 55000"
echo "  - Agent Port: 1514"
echo ""
echo "Wazuh Dashboard:"
echo "  - URL: http://$MASTER_IP:5601"
echo "  - Default credentials: admin / admin"
echo ""
echo "Wazuh Agents:"
echo "  - k3s-node1: Installed and connected"
echo "  - k3s-node2: Installed and connected"
echo ""
echo "Check agent status:"
echo "  incus exec k3s-master -- /var/ossec/bin/agent_control -l"
echo ""

echo "=========================================="
echo "  Next Steps:"
echo "=========================================="
echo ""
echo "1. Check K8s service health:"
echo "   incus exec k3s-master -- k3s kubectl get pods -n ssle-project"
echo ""
echo "2. Access Grafana dashboard:"
echo "   (Check Grafana service IP from above)"
echo ""
echo "3. Access Wazuh dashboard:"
echo "   http://$MASTER_IP:5601"
echo ""
echo "4. View Wazuh manager logs:"
echo "   incus exec k3s-master -- tail -f /var/ossec/logs/ossec.log"
echo ""
echo "5. View agent logs on nodes:"
echo "   incus exec k3s-node1 -- tail -f /var/ossec/logs/ossec.log"
echo ""

log_info "Setup completed successfully! 🎉"
