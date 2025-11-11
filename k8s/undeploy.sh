#!/bin/bash

# SSLE Project Kubernetes Cleanup Script

echo "========================================="
echo "SSLE Project - Kubernetes Cleanup"
echo "========================================="

echo ""
echo "This will delete all resources in the ssle-project namespace."
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Deleting all deployments and services..."
kubectl delete -f temperature-service.yaml
kubectl delete -f analytics-service.yaml
kubectl delete -f ingestion-service.yaml
kubectl delete -f storage-service.yaml
kubectl delete -f registry-service.yaml

echo ""
echo "Deleting PersistentVolumeClaim (this will delete the database)..."
kubectl delete -f storage-pvc.yaml

echo ""
echo "Deleting ConfigMaps..."
kubectl delete -f configmaps.yaml

echo ""
echo "Deleting namespace..."
kubectl delete -f namespace.yaml

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
