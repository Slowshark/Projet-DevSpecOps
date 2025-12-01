#!/bin/bash

echo "=========================================="
echo "Deploying to Kubernetes"
echo "=========================================="

echo ""
echo "Step 1: Creating PostgreSQL resources..."
kubectl apply -f k8s/postgres-pvc.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-configmap.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/service-db.yaml

echo ""
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres --timeout=120s

echo ""
echo "Step 2: Creating web application resources..."
kubectl apply -f k8s/webapp-secret.yaml
kubectl apply -f k8s/webapp-deployment.yaml
kubectl apply -f k8s/service-web.yaml

echo ""
echo "Waiting for webapp to be ready..."
kubectl wait --for=condition=ready pod -l app=webapp --timeout=120s

echo ""
echo "=========================================="
echo "Deployment completed!"
echo "=========================================="
echo ""
echo "Checking status..."
kubectl get all

echo ""
echo "To access the application:"
echo "  - With minikube: minikube service webapp-service"
echo "  - Or get URL: minikube service webapp-service --url"
echo "  - With K8s cluster: http://<NODE-IP>:30080"
echo ""
echo "Check health: curl http://<URL>/api/health"
