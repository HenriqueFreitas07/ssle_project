# SSLE Project - Microservices on K3s in Incus

A complete microservices architecture deployed on K3s running inside Incus containers, with Prometheus monitoring and Grafana dashboards.

## Architecture

```
Host Machine
    |
    └─── Incus Containers (10.10.10.0/24)
            ├─── k3s-master  (Control plane)
            ├─── k3s-node1   (Worker - services)
            └─── k3s-node2   (Worker - services)
                    |
                    └─── K3s Cluster
                            ├─── Microservices (ssle-project namespace)
                            │     ├─── registry-service
                            │     ├─── storage-service
                            │     ├─── ingestion-service
                            │     ├─── analytics-service
                            │     └─── temperature-service
                            │
                            └─── Monitoring (monitoring namespace)
                                  ├─── Prometheus
                                  ├─── Node Exporter
                                  └─── Grafana
```

## Prerequisites

- **Incus** installed and configured
- **Docker** and **docker-compose** installed
- **Sudo access** (required for kernel parameters)
- **Linux host** (tested on Manjaro, should work on any Linux)

## Quick Start

### 1. Clone the Repository

```bash
git clone <your-repo-url>
cd ssle_project
```

### 2. One-Command Setup

Run the complete setup script:

```bash
sudo ./setup-complete-cluster.sh
```

This script will:
1. Configure host kernel parameters
2. Create K3s Incus profile
3. Deploy K3s cluster (1 master + 2 workers)
4. Build Docker images for all microservices
5. Import images into K3s nodes
6. Deploy all Kubernetes resources
7. Start Prometheus and Grafana monitoring
8. Start Wazuh installation Components
9. Install Wazuh agents on worker nodes

**Setup time:** ~3-9 minutes

## Project Structure

```
.
├── setup-complete-cluster.sh    # Main setup script
├── docker-compose.yml            # Service container definitions
├── src/                          # Service source code
│   ├── registry_service/
│   ├── storage_service/
│   ├── ingestion_service/
│   ├── analytics_service/
│   └── temperature_service/
└── k8s/                          # Kubernetes manifests
    ├── namespace.yaml
    ├── configmaps.yaml
    ├── storage-pvc.yaml
    ├── registry-service.yaml
    ├── storage-service.yaml
    ├── ingestion-service.yaml
    ├── analytics-service.yaml
    ├── temperature-service.yaml
    ├── prometheus.yaml
    └── grafana.yaml
```

## Services

### Microservices

All services are Flask-based Python applications:

- **Registry Service** (Port 5050): Service discovery and registration
- **Storage Service** (Port 5002): Data persistence layer
- **Ingestion Service** (Port 5001): Data ingestion pipeline
- **Analytics Service** (Port 5003): Data analysis and processing
- **Temperature Service**: Temperature data monitoring

### Monitoring Stack

- **Prometheus**: Metrics collection and storage
- **Node Exporter**: Host-level metrics (CPU, memory, disk, network)
- **Grafana**: Visualization with pre-configured dashboard

## Useful Commands

### Cluster Management

```bash
# Check cluster nodes
incus exec k3s-master -- k3s kubectl get nodes

# Check all pods
incus exec k3s-master -- k3s kubectl get pods -A

# Check services
incus exec k3s-master -- k3s kubectl get svc -n ssle-project
```

### Service Health

```bash
# Test service health (replace <node-ip> with actual IP, it can be any of the nodes of the cluster since it is running with k8s)
curl http://<node-ip>:30050/health  # Registry
curl http://<node-ip>:30002/health  # Storage
curl http://<node-ip>:30001/health  # Ingestion
curl http://<node-ip>:30003/health  # Analytics
```

### Logs

```bash
# View service logs
incus exec k3s-master -- k3s kubectl logs -n ssle-project -l app=registry-service
incus exec k3s-master -- k3s kubectl logs -n ssle-project -l app=storage-service

# View Prometheus logs
incus exec k3s-master -- k3s kubectl logs -n monitoring -l app=prometheus

# View Grafana logs
incus exec k3s-master -- k3s kubectl logs -n monitoring -l app=grafana
```

### Rebuild and Redeploy

If you make changes to services:

```bash
# Rebuild images
docker-compose build

# Save and import to K3s nodes
docker save ssle_project-registry_service:latest -o /tmp/registry.tar
incus exec k3s-master -- ctr --namespace k8s.io images import - < /tmp/registry.tar
incus exec k3s-node1 -- ctr --namespace k8s.io images import - < /tmp/registry.tar
incus exec k3s-node2 -- ctr --namespace k8s.io images import - < /tmp/registry.tar

# Restart pods
incus exec k3s-master -- k3s kubectl rollout restart deployment/registry-service -n ssle-project
```

## Grafana Dashboard

The setup automatically provisions a dashboard for monitoring the service nodes:

**Dashboard: "SSLE Service Nodes Monitoring"**
- CPU usage per node
- Memory usage per node
- Network traffic (RX/TX)
- Disk usage
- Load averages

Access at: `http://<node-ip>:30300/

## Cleanup

To completely remove the cluster:

```bash
# Delete all containers
incus delete -f k3s-master k3s-node1 k3s-node2

# Delete the profile
incus profile delete k3s

# Remove Docker images (optional)
docker-compose down --rmi all
```

### Service not accessible from host

Check NodePort services:
```bash
incus exec k3s-master -- k3s kubectl get svc -n ssle-project
```

Verify node IPs:
```bash
incus list -c n,4
```

## Network Details

- **Incus Bridge**: 10.10.10.0/24
- **K3s Pod Network**: 10.42.0.0/16 (Flannel)
- **K3s Service Network**: 10.43.0.0/16 (ClusterIP)
- **NodePort Range**: 30000-32767

## IP Table Update

Since this is suppose to build docker images, incus and docker are expected to be installed. But since docker overwrites some nat iptable rules that block incus bridge network interface traffic, a script was built to give priority to traffic coming from and into incus. Since docker was only used to build these images, and no container was running during the development of this project, there is no way to describe the behaviour of docker networking capabilities during and after the script has been executed. 

```bash
sudo ./incus-network-fix.sh
```
