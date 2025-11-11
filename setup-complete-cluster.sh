#!/bin/bash

# Complete K3s Cluster Setup Script
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
echo "  Complete K3s Cluster Setup"
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
log_info "[1/10] Configuring host kernel parameters..."
sysctl -w vm.overcommit_memory=1
sysctl -w kernel.panic=10
sysctl -w kernel.panic_on_oops=1
echo "✓ Kernel parameters configured"
echo ""

# ==============================================
# STEP 2: Create K3s Incus Profile
# ==============================================
log_info "[2/10] Creating K3s Incus profile..."

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
log_info "[3/10] Creating K3s master node..."

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
log_info "[4/10] Creating and joining worker nodes..."

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
log_info "[5/10] Labeling nodes for scheduling..."
incus exec k3s-master -- k3s kubectl label nodes k3s-node1 k3s-node2 node-role=services node-role=monitoring --overwrite
echo "✓ Nodes labeled"
echo ""

# ==============================================
# STEP 6: Build Docker Images
# ==============================================
log_info "[6/10] Building Docker images..."

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
log_info "[7/10] Exporting and importing Docker images to K3s nodes..."

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
log_info "[8/10] Deploying namespace and configmaps..."

incus exec k3s-master -- bash << 'EOF'
cat > /root/namespace.yaml << 'EOFNS'
apiVersion: v1
kind: Namespace
metadata:
  name: ssle-project
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOFNS

k3s kubectl apply -f /root/namespace.yaml
EOF

# Copy and apply configmaps
cat "$PROJECT_DIR/k8s/configmaps.yaml" | incus exec k3s-master -- bash -c 'cat > /root/configmaps.yaml && k3s kubectl apply -f /root/configmaps.yaml'

echo "✓ Namespaces and ConfigMaps created"
echo ""

# ==============================================
# STEP 9: Deploy Storage PVCs
# ==============================================
log_info "[9/10] Deploying Persistent Volume Claims..."

incus exec k3s-master -- bash << 'EOF'
# Storage PVC for services
cat > /root/storage-pvc.yaml << 'EOFPVC'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-data-pvc
  namespace: ssle-project
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
EOFPVC

# Prometheus PVC
cat > /root/prometheus-pvc.yaml << 'EOFPVC2'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
EOFPVC2

k3s kubectl apply -f /root/storage-pvc.yaml
k3s kubectl apply -f /root/prometheus-pvc.yaml
EOF

echo "✓ PVCs created"
echo ""

# ==============================================
# STEP 10: Deploy All Services
# ==============================================
log_info "[10/10] Deploying all services..."

# Deploy microservices
for service in registry-service storage-service ingestion-service analytics-service temperature-service; do
    log_info "Deploying $service..."
    cat "$PROJECT_DIR/k8s/${service}.yaml" | incus exec k3s-master -- bash -c "cat > /root/${service}.yaml && k3s kubectl apply -f /root/${service}.yaml"
done

# Deploy monitoring
log_info "Deploying Prometheus..."
cat "$PROJECT_DIR/k8s/prometheus.yaml" | incus exec k3s-master -- bash -c 'cat > /root/prometheus.yaml && k3s kubectl apply -f /root/prometheus.yaml'

echo "✓ All services deployed"
echo ""

# ==============================================
# Wait for Pods to be Ready
# ==============================================
log_info "Waiting for pods to be ready (this may take a minute)..."
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
echo "  Next Steps:"
echo "=========================================="
echo ""
echo "1. Check service health:"
echo "   incus exec k3s-master -- k3s kubectl get pods -n ssle-project"
echo ""
echo "2. Access services from host:"
echo "   ./k8s/access-services.sh"
echo ""
echo "3. Test a service:"
echo "   incus exec k3s-master -- curl http://10.43.60.92:5050/health"
echo ""
echo "4. View logs:"
echo "   incus exec k3s-master -- k3s kubectl logs -n ssle-project -l app=registry-service"
echo ""
echo "5. Copy kubeconfig to host (optional):"
echo "   incus exec k3s-master -- cat /etc/rancher/k3s/k3s.yaml > ~/.kube/k3s-config"
echo ""

log_info "Setup completed successfully! 🎉"
