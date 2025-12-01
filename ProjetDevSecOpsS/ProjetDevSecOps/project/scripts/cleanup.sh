#!/bin/bash

echo "=========================================="
echo "Cleaning up Kubernetes resources"
echo "=========================================="

echo ""
echo "Removing all resources..."
kubectl delete -f k8s/

echo ""
echo "Verifying deletion..."
kubectl get all

echo ""
echo "=========================================="
echo "Cleanup completed!"
echo "=========================================="
