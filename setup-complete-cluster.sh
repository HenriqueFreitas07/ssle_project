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

log_info "[11/12] Installing Wazuh in separate container..."

# Delete if exists
incus delete -f wazuh-container 2>/dev/null || true

log_info "Creating Wazuh container..."
incus launch images:ubuntu/22.04 wazuh-container
sleep 10

log_info "Installing Wazuh using automated installer..."
incus exec wazuh-container -- bash -c '
# Update and install curl
apt update
apt install -y curl

# Download Wazuh installation script
curl -sO https://packages.wazuh.com/4.13/wazuh-install.sh
chmod +x wazuh-install.sh

# Run all-in-one installation
./wazuh-install.sh -a -i
'

log_info "Wazuh installation complete!"
log_info "Extracting admin credentials..."

# Get the admin password - it's displayed during installation
# Extract it from the wazuh-install-files.tar
WAZUH_PASSWORD=$(incus exec wazuh-container -- bash -c '
if [ -f wazuh-install-files.tar ]; then
    tar -xf wazuh-install-files.tar 2>/dev/null
fi
if [ -f wazuh-install-files/wazuh-passwords.txt ]; then
    grep -A 1 "indexer_username: '\''admin'\''" wazuh-install-files/wazuh-passwords.txt | grep "indexer_password:" | head -1 | sed "s/.*indexer_password: '\''\(.*\)'\''/\1/"
fi
' || echo "CHECK_CONTAINER")

echo "✓ Wazuh Manager, Indexer, and Dashboard installed in wazuh-container"
echo ""

# Get wazuh-container IP
WAZUH_IP=$(incus list wazuh-container -c 4 -f csv | grep eth0 | cut -d' ' -f1)
log_info "Wazuh Manager IP: $WAZUH_IP"

# Verify password was extracted
if [ -z "$WAZUH_PASSWORD" ] || [ "$WAZUH_PASSWORD" == "CHECK_CONTAINER" ]; then
    log_warn "Could not automatically extract password. You can find it by running:"
    log_warn "  incus exec wazuh-container -- cat wazuh-install-files/wazuh-passwords.txt"
    WAZUH_PASSWORD="<see instructions above>"
else
    log_info "Admin password successfully extracted!"
fi

# ==============================================
# STEP 12: Install Wazuh Agents on Worker Nodes
# ==============================================
log_info "[12/12] Installing Wazuh Agents on worker nodes..."

# Get manager version to ensure agent compatibility
log_info "Getting Wazuh manager version..."
WAZUH_VERSION=$(incus exec wazuh-container -- /var/ossec/bin/wazuh-control info | grep WAZUH_VERSION | cut -d'"' -f2 | sed 's/^v//')
log_info "Manager version: $WAZUH_VERSION"

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

    # Install Wazuh agent with specific version matching manager, pointing to wazuh-container
    WAZUH_MANAGER='$WAZUH_IP' apt install -y --allow-downgrades wazuh-agent=$WAZUH_VERSION-1

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
    incus exec wazuh-container -- bash -c "/var/ossec/bin/manage_agents -a -n $node -i any || true"
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
echo "  - Host: wazuh-container ($WAZUH_IP)"
echo "  - API Port: 55000"
echo "  - Agent Port: 1514"
echo ""
echo "Wazuh Dashboard:"
echo "  - URL: https://$WAZUH_IP"
echo "  - Username: admin"
echo "  - Password: $WAZUH_PASSWORD"
echo ""
echo "Wazuh Agents:"
echo "  - k3s-node1: Installed and connected"
echo "  - k3s-node2: Installed and connected"
echo ""
echo "Check agent status:"
echo "  incus exec wazuh-container -- /var/ossec/bin/agent_control -l"
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
echo "   https://$WAZUH_IP"
echo "   Username: admin"
echo "   Password: $WAZUH_PASSWORD"
echo ""
echo "4. View Wazuh manager logs:"
echo "   incus exec wazuh-container -- tail -f /var/ossec/logs/ossec.log"
echo ""
echo "5. View agent logs on nodes:"
echo "   incus exec k3s-node1 -- tail -f /var/ossec/logs/ossec.log"
echo ""

log_info "Setup completed successfully! 🎉"
