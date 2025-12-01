#!/bin/bash

echo "=========================================="
echo "Building Kubernetes Web Application"
echo "=========================================="

echo ""
echo "Step 1: Building Docker image..."
docker build -t kubernetes-webapp:latest .

if [ $? -eq 0 ]; then
    echo "Docker image built successfully!"
else
    echo "Error building Docker image"
    exit 1
fi

echo ""
echo "Step 2: Verifying image..."
docker images | grep kubernetes-webapp

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Configure your Supabase credentials in k8s/webapp-secret.yaml"
echo "2. Deploy to Kubernetes with: ./scripts/deploy.sh"
echo "3. Or deploy manually with: kubectl apply -f k8s/"
