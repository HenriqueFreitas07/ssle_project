# SSLE Project - Incus Kubernetes Cluster Setup

This guide covers deploying the SSLE project on a 3-node Kubernetes cluster using Incus containers.

## Cluster Architecture

### Node Layout

```
┌─────────────────────────────────────────────────────────────┐
│                    Incus K8s Cluster                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │   Node 1 (Worker)  │  │   Node 2 (Worker)  │            │
│  │  node-role=services│  │  node-role=services│            │
│  ├────────────────────┤  ├────────────────────┤            │
│  │ - Registry Service │  │ - Storage Service  │            │
│  │ - Ingestion Svc    │  │ - Analytics Svc    │            │
│  │ - Temperature Svc  │  │ - (Load balanced)  │            │
│  │                    │  │                    │            │
│  │ - Wazuh Agent      │  │ - Wazuh Agent      │            │
│  │ - Node Exporter    │  │ - Node Exporter    │            │
│  └────────────────────┘  └────────────────────┘            │
│                                                               │
│  ┌──────────────────────────────────────────┐               │
│  │        Node 3 (Monitoring)               │               │
│  │       node-role=monitoring               │               │
│  ├──────────────────────────────────────────┤               │
│  │ - Wazuh Manager                          │               │
│  │ - Wazuh Indexer                          │               │
│  │ - Wazuh Dashboard                        │               │
│  │ - Prometheus                             │               │
│  │ - Grafana                                │               │
│  └──────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Incus installed and configured
- kubectl installed
- Minimum resources:
  - Node 1: 2 vCPUs, 4GB RAM
  - Node 2: 2 vCPUs, 4GB RAM
  - Node 3: 4 vCPUs, 8GB RAM

## Step 1: Create Incus Containers

Create 3 Incus containers for the Kubernetes nodes:

```bash
# Create Node 1 (Service Node)
incus launch images:ubuntu/22.04 k8s-node1 \
  --config limits.cpu=2 \
  --config limits.memory=4GB \
  --device eth0,nictype=bridged,parent=incusbr0

# Create Node 2 (Service Node)
incus launch images:ubuntu/22.04 k8s-node2 \
  --config limits.cpu=2 \
  --config limits.memory=4GB \
  --device eth0,nictype=bridged,parent=incusbr0

# Create Node 3 (Monitoring Node)
incus launch images:ubuntu/22.04 k8s-node3 \
  --config limits.cpu=4 \
  --config limits.memory=8GB \
  --device eth0,nictype=bridged,parent=incusbr0
```

Enable nested virtualization for Kubernetes:

```bash
incus config set k8s-node1 security.nesting=true security.privileged=true
incus config set k8s-node2 security.nesting=true security.privileged=true
incus config set k8s-node3 security.nesting=true security.privileged=true
```

## Step 2: Install Kubernetes on All Nodes

For each node, run the following commands:

```bash
# SSH into each node
incus exec k8s-node1 -- bash
# Or: incus exec k8s-node2 -- bash
# Or: incus exec k8s-node3 -- bash

# Update system
apt-get update && apt-get upgrade -y

# Install required packages
apt-get install -y apt-transport-https ca-certificates curl

# Add Kubernetes repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Install container runtime (containerd)
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load required kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

## Step 3: Initialize Kubernetes Cluster (Node 1)

On `k8s-node1` (control plane):

```bash
incus exec k8s-node1 -- bash

# Initialize cluster
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl for root
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Save join command (you'll need this for other nodes)
kubeadm token create --print-join-command > /root/join-command.txt
```

## Step 4: Join Worker Nodes

On `k8s-node2` and `k8s-node3`:

```bash
# Get join command from node1
incus exec k8s-node1 -- cat /root/join-command.txt

# Execute join command on node2 and node3
incus exec k8s-node2 -- bash
# Paste the join command here

incus exec k8s-node3 -- bash
# Paste the join command here
```

## Step 5: Label Nodes

Back on `k8s-node1` (control plane):

```bash
# Label service nodes
kubectl label node k8s-node1 node-role=services
kubectl label node k8s-node2 node-role=services

# Label monitoring node
kubectl label node k8s-node3 node-role=monitoring

# Verify labels
kubectl get nodes --show-labels
```

Expected output:
```
NAME         STATUS   ROLES           AGE   VERSION   LABELS
k8s-node1    Ready    control-plane   10m   v1.28.x   node-role=services,...
k8s-node2    Ready    <none>          5m    v1.28.x   node-role=services,...
k8s-node3    Ready    <none>          5m    v1.28.x   node-role=monitoring,...
```

## Step 6: Copy Docker Images to Cluster

From your host machine, export and load Docker images:

```bash
# Export images
docker save ssle_project-registry_service:latest | gzip > registry-service.tar.gz
docker save ssle_project-storage_service:latest | gzip > storage-service.tar.gz
docker save ssle_project-ingestion_service:latest | gzip > ingestion-service.tar.gz
docker save ssle_project-analytics_service:latest | gzip > analytics-service.tar.gz
docker save ssle_project-temperature_service:latest | gzip > temperature-service.tar.gz

# Copy to nodes and import
for node in k8s-node1 k8s-node2; do
  incus file push registry-service.tar.gz $node/root/
  incus file push storage-service.tar.gz $node/root/
  incus file push ingestion-service.tar.gz $node/root/
  incus file push analytics-service.tar.gz $node/root/
  incus file push temperature-service.tar.gz $node/root/

  incus exec $node -- ctr -n k8s.io images import /root/registry-service.tar.gz
  incus exec $node -- ctr -n k8s.io images import /root/storage-service.tar.gz
  incus exec $node -- ctr -n k8s.io images import /root/ingestion-service.tar.gz
  incus exec $node -- ctr -n k8s.io images import /root/analytics-service.tar.gz
  incus exec $node -- ctr -n k8s.io images import /root/temperature-service.tar.gz
done

# Cleanup
rm *.tar.gz
```

## Step 7: Deploy Wazuh Central Components (Node 3)

Deploy Wazuh on the monitoring node:

```bash
# Create wazuh namespace
kubectl create namespace wazuh

# Deploy Wazuh using official manifests
kubectl apply -f https://raw.githubusercontent.com/wazuh/wazuh-kubernetes/master/wazuh/wazuh-cluster-v4.7.0.yaml
kubectl apply -f https://raw.githubusercontent.com/wazuh/wazuh-kubernetes/master/wazuh/wazuh-cluster-service.yaml

# Add node selector to ensure it runs on monitoring node
kubectl patch deployment wazuh-manager -n wazuh -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role":"monitoring"}}}}}'
kubectl patch deployment wazuh-indexer -n wazuh -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role":"monitoring"}}}}}'
kubectl patch deployment wazuh-dashboard -n wazuh -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role":"monitoring"}}}}}'

# Wait for Wazuh to be ready
kubectl wait --for=condition=ready pod -l app=wazuh-manager -n wazuh --timeout=300s
```

## Step 8: Deploy SSLE Services

From your host machine with kubectl configured:

```bash
# Copy kubeconfig from node1 to your local machine
incus file pull k8s-node1/root/.kube/config ~/.kube/incus-config
export KUBECONFIG=~/.kube/incus-config

# Navigate to k8s directory
cd /home/hfreitas07/Desktop/ssle_project/k8s

# Deploy SSLE services
kubectl apply -f namespace.yaml
kubectl apply -f configmaps.yaml
kubectl apply -f storage-pvc.yaml
kubectl apply -f registry-service.yaml
kubectl apply -f storage-service.yaml
kubectl apply -f ingestion-service.yaml
kubectl apply -f analytics-service.yaml
kubectl apply -f temperature-service.yaml

# Deploy Wazuh agents on service nodes
kubectl apply -f wazuh-agent.yaml

# Deploy Prometheus and Node Exporter
kubectl apply -f prometheus.yaml

# Verify deployments
kubectl get pods -n ssle-project
kubectl get pods -n monitoring
```

## Step 9: Deploy Grafana (Node 3)

Create Grafana deployment:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: grafana
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      nodeSelector:
        node-role: monitoring
      containers:
      - name: grafana
        image: grafana/grafana:10.2.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        - name: GF_SERVER_ROOT_URL
          value: "http://localhost:3000"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
      volumes:
      - name: grafana-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: grafana
spec:
  selector:
    app: grafana
  ports:
  - protocol: TCP
    port: 3000
    targetPort: 3000
  type: NodePort
EOF
```

## Step 10: Access Services

### Port Forwarding from Control Plane

```bash
# SSLE Services
kubectl port-forward svc/registry-service 5050:5050 -n ssle-project
kubectl port-forward svc/storage-service 5002:5002 -n ssle-project
kubectl port-forward svc/ingestion-service 5001:5001 -n ssle-project
kubectl port-forward svc/analytics-service 5003:5003 -n ssle-project

# Monitoring Stack
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n grafana

# Wazuh Dashboard
kubectl port-forward svc/wazuh-dashboard 443:5601 -n wazuh
```

### Access URLs

- **Analytics API**: http://localhost:5003/stats
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)
- **Wazuh Dashboard**: https://localhost:443

## Step 11: Configure Grafana

Add Prometheus data source to Grafana:

1. Login to Grafana (http://localhost:3000)
2. Go to Configuration → Data Sources
3. Add Prometheus:
   - URL: `http://prometheus.monitoring.svc.cluster.local:9090`
   - Access: Server (default)
   - Click "Save & Test"

## Verification

### Check Node Distribution

```bash
# See which pods are on which nodes
kubectl get pods -n ssle-project -o wide
kubectl get pods -n monitoring -o wide
kubectl get pods -n wazuh -o wide
```

### Check Wazuh Agents

```bash
# View Wazuh agent logs
kubectl logs -f daemonset/wazuh-agent -n ssle-project

# Check agent registration
kubectl exec -it deployment/wazuh-manager -n wazuh -- /var/ossec/bin/agent_control -l
```

### Check Prometheus Targets

```bash
# Port forward Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Open browser to http://localhost:9090/targets
# Verify all scrape targets are UP
```

## Cleanup

To remove everything:

```bash
# Delete namespaces (this removes all resources)
kubectl delete namespace ssle-project
kubectl delete namespace monitoring
kubectl delete namespace grafana
kubectl delete namespace wazuh

# Or use the undeploy script
./undeploy.sh

# Destroy Incus containers
incus stop k8s-node1 k8s-node2 k8s-node3
incus delete k8s-node1 k8s-node2 k8s-node3
```

## Troubleshooting

### Pods Stuck in Pending

Check if nodes have the correct labels:
```bash
kubectl get nodes --show-labels
```

### Wazuh Agents Not Connecting

Check agent configuration:
```bash
kubectl describe configmap wazuh-agent-config -n ssle-project
# Update WAZUH_MANAGER to point to your Wazuh manager service
kubectl edit configmap wazuh-agent-config -n ssle-project
# Restart agent pods
kubectl rollout restart daemonset/wazuh-agent -n ssle-project
```

### Image Pull Errors

Verify images are loaded in containerd:
```bash
incus exec k8s-node1 -- ctr -n k8s.io images ls | grep ssle
```

### Storage Issues

Check PVC status:
```bash
kubectl get pvc -n ssle-project
kubectl describe pvc storage-data-pvc -n ssle-project
```

## Next Steps

1. Configure Grafana dashboards for SSLE metrics
2. Set up Wazuh rules for security monitoring
3. Configure alerting in Prometheus
4. Set up log aggregation (optional: EFK stack)
