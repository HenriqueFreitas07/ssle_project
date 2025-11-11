#!/bin/bash

# SSLE Project Kubernetes Deployment Script

echo "========================================="
echo "SSLE Project - Kubernetes Deployment"
echo "========================================="

# Verify node labels
echo ""
echo "[0/11] Verifying node labels..."
SERVICE_NODES=$(kubectl get nodes -l node-role=services --no-headers | wc -l)
MONITORING_NODES=$(kubectl get nodes -l node-role=monitoring --no-headers | wc -l)

echo "Found $SERVICE_NODES service nodes and $MONITORING_NODES monitoring nodes"

if [ "$SERVICE_NODES" -lt 2 ]; then
    echo "WARNING: Expected at least 2 nodes with label 'node-role=services'"
    echo "Run: kubectl label node <node-name> node-role=services"
fi

if [ "$MONITORING_NODES" -lt 1 ]; then
    echo "WARNING: Expected at least 1 node with label 'node-role=monitoring'"
    echo "Run: kubectl label node <node-name> node-role=monitoring"
fi

read -p "Continue with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

# Step 1: Create namespace
echo ""
echo "[1/11] Creating namespace..."
kubectl apply -f namespace.yaml

# Step 2: Create ConfigMaps
echo ""
echo "[2/11] Creating ConfigMaps..."
kubectl apply -f configmaps.yaml

# Step 3: Create PersistentVolumeClaim
echo ""
echo "[3/11] Creating PersistentVolumeClaim..."
kubectl apply -f storage-pvc.yaml

# Step 4: Deploy Registry Service
echo ""
echo "[4/11] Deploying Registry Service..."
kubectl apply -f registry-service.yaml

# Step 5: Deploy Storage Service
echo ""
echo "[5/11] Deploying Storage Service..."
kubectl apply -f storage-service.yaml

# Wait for storage service to be ready
echo "Waiting for storage service to be ready..."
kubectl wait --for=condition=ready pod -l app=storage-service -n ssle-project --timeout=120s

# Step 6: Deploy Ingestion Service
echo ""
echo "[6/11] Deploying Ingestion Service..."
kubectl apply -f ingestion-service.yaml

# Step 7: Deploy Analytics Service
echo ""
echo "[7/11] Deploying Analytics Service..."
kubectl apply -f analytics-service.yaml

# Step 8: Deploy Temperature Service
echo ""
echo "[8/11] Deploying Temperature Service..."
kubectl apply -f temperature-service.yaml

# Step 9: Deploy Wazuh Agents
echo ""
echo "[9/11] Deploying Wazuh Agents..."
kubectl apply -f wazuh-agent.yaml
echo "NOTE: Update WAZUH_MANAGER in wazuh-agent.yaml to point to your Wazuh manager"

# Step 10: Deploy Prometheus and Node Exporter
echo ""
echo "[10/11] Deploying Prometheus and Node Exporter..."
kubectl apply -f prometheus.yaml

# Wait for Prometheus to be ready
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s

# Step 11: Verify Deployment
echo ""
echo "[11/11] Verifying deployment..."
sleep 5

echo ""
echo "========================================="
echo "Deployment Status"
echo "========================================="
echo ""
echo "SSLE Services:"
kubectl get pods -n ssle-project -o wide
echo ""
echo "Monitoring Stack:"
kubectl get pods -n monitoring -o wide
echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Check status:"
echo "  kubectl get pods -n ssle-project"
echo "  kubectl get pods -n monitoring"
echo ""
echo "View logs:"
echo "  kubectl logs -f deployment/storage-service -n ssle-project"
echo "  kubectl logs -f deployment/ingestion-service -n ssle-project"
echo "  kubectl logs -f deployment/analytics-service -n ssle-project"
echo "  kubectl logs -f deployment/prometheus -n monitoring"
echo "  kubectl logs -f daemonset/wazuh-agent -n ssle-project"
echo "  kubectl logs -f daemonset/node-exporter -n monitoring"
echo ""
echo "Access services via port-forward:"
echo "  # SSLE Services"
echo "  kubectl port-forward svc/registry-service 5050:5050 -n ssle-project"
echo "  kubectl port-forward svc/storage-service 5002:5002 -n ssle-project"
echo "  kubectl port-forward svc/ingestion-service 5001:5001 -n ssle-project"
echo "  kubectl port-forward svc/analytics-service 5003:5003 -n ssle-project"
echo ""
echo "  # Monitoring"
echo "  kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
echo ""
echo "Test endpoints:"
echo "  curl http://localhost:5003/stats"
echo "  curl http://localhost:5002/count"
echo "  curl http://localhost:9090/api/v1/targets"
echo ""
echo "IMPORTANT: Configure Wazuh manager address in wazuh-agent ConfigMap"
echo "  kubectl edit configmap wazuh-agent-config -n ssle-project"
echo ""
