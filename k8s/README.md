# SSLE Project - Kubernetes Deployment

Complete Kubernetes deployment for the SSLE (Sensor Storage Logic and Analytics) microservices project with integrated security monitoring (Wazuh) and observability (Prometheus).

## Architecture Overview

### 3-Node Incus Cluster Layout

```
Node 1 (Services)          Node 2 (Services)          Node 3 (Monitoring)
├─ Registry Service        ├─ Storage Service         ├─ Wazuh Manager
├─ Ingestion Service       ├─ Analytics Service       ├─ Wazuh Dashboard
├─ Temperature Service     ├─ Load Distribution       ├─ Prometheus
├─ Wazuh Agent            ├─ Wazuh Agent             ├─ Grafana
└─ Node Exporter          └─ Node Exporter           └─ Persistent Storage
```

### Microservices Architecture

```
┌─────────────────────┐
│ Temperature Service │  Generates simulated sensor data
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Ingestion Service   │  Receives and validates data
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐     ┌──────────────────┐
│ Storage Service     │────▶│  SQLite Database │
└──────────┬──────────┘     └──────────────────┘
           │
           ▼
┌─────────────────────┐
│ Analytics Service   │  Provides queries and statistics
└─────────────────────┘

┌─────────────────────┐
│ Registry Service    │  Service discovery
└─────────────────────┘
```

## Quick Start

### Prerequisites

- Incus cluster with 3 nodes
- kubectl configured
- Docker images built

### 1. Label Kubernetes Nodes

```bash
kubectl label node <node1-name> node-role=services
kubectl label node <node2-name> node-role=services
kubectl label node <node3-name> node-role=monitoring
```

### 2. Deploy Everything

```bash
cd k8s
./deploy.sh
```

## Detailed Setup

See [INCUS_SETUP.md](./INCUS_SETUP.md) for complete step-by-step Incus cluster setup.

## Deployed Components

### SSLE Services (Namespace: `ssle-project`)

| Service | Port | Purpose | Node Affinity |
|---------|------|---------|---------------|
| Registry | 5050 | Service registry | services |
| Storage | 5002 | Data persistence | services |
| Ingestion | 5001 | Data intake | services |
| Analytics | 5003 | Query & analytics | services |
| Temperature | N/A | Sensor simulator | services |

### Monitoring Stack (Namespace: `monitoring`)

| Component | Port | Purpose | Node Affinity |
|-----------|------|---------|---------------|
| Prometheus | 9090 | Metrics collection | monitoring |
| Node Exporter | 9100 | Node metrics | services (DaemonSet) |

### Security Stack (Namespace: `ssle-project`)

| Component | Purpose | Node Affinity |
|-----------|---------|---------------|
| Wazuh Agent | Security monitoring | services (DaemonSet) |

## Configuration Files

```
k8s/
├── namespace.yaml              # Namespace definition
├── configmaps.yaml             # Environment configurations
├── storage-pvc.yaml            # Persistent volume for database
├── registry-service.yaml       # Registry deployment + service
├── storage-service.yaml        # Storage deployment + service
├── ingestion-service.yaml      # Ingestion deployment + service
├── analytics-service.yaml      # Analytics deployment + service
├── temperature-service.yaml    # Temperature simulator
├── wazuh-agent.yaml            # Wazuh agent DaemonSet
├── prometheus.yaml             # Prometheus + Node Exporter
├── deploy.sh                   # Automated deployment script
├── undeploy.sh                 # Cleanup script
├── INCUS_SETUP.md              # Detailed Incus setup guide
└── README.md                   # This file
```

## Access Services

### Port Forwarding

```bash
# SSLE Services
kubectl port-forward svc/storage-service 5002:5002 -n ssle-project
kubectl port-forward svc/ingestion-service 5001:5001 -n ssle-project
kubectl port-forward svc/analytics-service 5003:5003 -n ssle-project

# Monitoring
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
```

### API Endpoints

Once port-forwarding is active:

**Analytics Queries:**
```bash
# Get all statistics
curl http://localhost:5003/stats

# Get average temperature
curl http://localhost:5003/average

# Get min/max temperatures
curl http://localhost:5003/min
curl http://localhost:5003/max

# Get per-device statistics
curl http://localhost:5003/by_device

# Get recent readings (last 10)
curl "http://localhost:5003/recent?limit=10"
```

**Storage Queries:**
```bash
# Get total count
curl http://localhost:5002/count

# Query all data
curl http://localhost:5002/query
```

**Manual Data Ingestion:**
```bash
curl -X POST http://localhost:5001/ingest \
  -H "Content-Type: application/json" \
  -d '{"device_id":"manual-sensor","temperature":25.5}'
```

## Monitoring & Observability

### Prometheus Targets

Access Prometheus UI: `http://localhost:9090`

Configured scrape targets:
- Kubernetes API Server
- Kubernetes Nodes
- Node Exporter (service nodes)
- SSLE Services (registry, storage, ingestion, analytics)

### Grafana Dashboards

After deploying Grafana:
1. Access: `http://localhost:3000`
2. Login: admin/admin
3. Add Prometheus data source: `http://prometheus.monitoring.svc.cluster.local:9090`
4. Import dashboards for:
   - Node Exporter metrics
   - Kubernetes cluster overview
   - SSLE service metrics

### Wazuh Security Monitoring

Configure Wazuh agents to connect to Wazuh manager:

```bash
# Edit Wazuh agent configuration
kubectl edit configmap wazuh-agent-config -n ssle-project

# Update WAZUH_MANAGER to your Wazuh manager address
# Example: wazuh-manager.wazuh.svc.cluster.local

# Restart agents
kubectl rollout restart daemonset/wazuh-agent -n ssle-project
```

View Wazuh Dashboard (after deploying Wazuh central components):
```bash
kubectl port-forward svc/wazuh-dashboard 443:5601 -n wazuh
# Access: https://localhost:443
```

## Operations

### Scaling Services

```bash
# Scale ingestion service for higher load
kubectl scale deployment ingestion-service --replicas=3 -n ssle-project

# Scale analytics service
kubectl scale deployment analytics-service --replicas=2 -n ssle-project
```

**Note:** Storage service should remain at 1 replica due to SQLite limitations.

### View Logs

```bash
# Service logs
kubectl logs -f deployment/storage-service -n ssle-project
kubectl logs -f deployment/ingestion-service -n ssle-project
kubectl logs -f deployment/analytics-service -n ssle-project

# Monitoring logs
kubectl logs -f deployment/prometheus -n monitoring
kubectl logs -f daemonset/node-exporter -n monitoring

# Security logs
kubectl logs -f daemonset/wazuh-agent -n ssle-project
```

### Update Configuration

```bash
# Edit ConfigMaps
kubectl edit configmap registry-service-config -n ssle-project

# Apply changes by restarting deployment
kubectl rollout restart deployment/registry-service -n ssle-project
```

### Backup Database

```bash
# Find storage pod
STORAGE_POD=$(kubectl get pod -n ssle-project -l app=storage-service -o jsonpath='{.items[0].metadata.name}')

# Copy database to local machine
kubectl cp ssle-project/$STORAGE_POD:/app/data/temp_data.db ./backup-$(date +%Y%m%d).db
```

## Troubleshooting

### Pods Not Scheduling

Check node labels:
```bash
kubectl get nodes --show-labels
```

Verify pods are bound to correct nodes:
```bash
kubectl get pods -n ssle-project -o wide
kubectl get pods -n monitoring -o wide
```

### Service Connection Issues

Test DNS resolution:
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# nslookup storage-service.ssle-project.svc.cluster.local
```

Test service connectivity:
```bash
kubectl exec -it deployment/ingestion-service -n ssle-project -- \
  wget -O- http://storage-service:5002/health
```

### Image Pull Errors

Verify images are available:
```bash
# On each node
incus exec <node-name> -- ctr -n k8s.io images ls | grep ssle
```

### Database Issues

Check PVC status:
```bash
kubectl get pvc -n ssle-project
kubectl describe pvc storage-data-pvc -n ssle-project
```

Inspect database:
```bash
kubectl exec -it deployment/storage-service -n ssle-project -- sh
# ls -la /app/data/
# sqlite3 /app/data/temp_data.db "SELECT COUNT(*) FROM temperatures;"
```

### Wazuh Agent Connection

Check agent logs:
```bash
kubectl logs daemonset/wazuh-agent -n ssle-project
```

Verify Wazuh manager connectivity:
```bash
kubectl exec -it daemonset/wazuh-agent -n ssle-project -- \
  telnet wazuh-manager.wazuh.svc.cluster.local 1514
```

### Prometheus Scraping Issues

Check Prometheus targets:
```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090/targets
```

View Prometheus logs:
```bash
kubectl logs -f deployment/prometheus -n monitoring
```

## Cleanup

### Remove All Resources

```bash
./undeploy.sh
```

Or manually:
```bash
kubectl delete namespace ssle-project
kubectl delete namespace monitoring
```

### Destroy Incus Cluster

```bash
incus stop k8s-node1 k8s-node2 k8s-node3
incus delete k8s-node1 k8s-node2 k8s-node3
```

## Security Considerations

1. **Wazuh Agent Configuration**
   - Change default `WAZUH_REGISTRATION_PASSWORD` in production
   - Use Kubernetes secrets instead of ConfigMap for sensitive data

2. **Network Policies**
   - Consider adding NetworkPolicies to restrict pod-to-pod communication
   - Limit ingress/egress to necessary services only

3. **RBAC**
   - Prometheus ServiceAccount has cluster-wide read permissions
   - Review and adjust RBAC as needed for your environment

4. **Image Security**
   - Use specific image tags instead of `latest`
   - Scan images for vulnerabilities
   - Push images to private registry for production

5. **Secrets Management**
   - Store sensitive configuration in Kubernetes Secrets
   - Consider using external secret management (Vault, etc.)

## Performance Tuning

### Resource Limits

All deployments have resource requests and limits defined. Adjust based on workload:

```bash
kubectl edit deployment <service-name> -n ssle-project
# Modify resources.requests and resources.limits
```

### Storage Performance

For production:
- Use ReadWriteMany storage class with better performance
- Consider using external database instead of SQLite
- Enable database connection pooling

### Prometheus Retention

Adjust retention period in `prometheus.yaml`:
```yaml
args:
- '--storage.tsdb.retention.time=30d'  # Adjust as needed
```

## Additional Resources

- [Incus Documentation](https://linuxcontainers.org/incus/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## Support

For issues or questions:
1. Check logs: `kubectl logs -f <pod-name> -n <namespace>`
2. Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
3. Describe resources: `kubectl describe <resource> <name> -n <namespace>`
