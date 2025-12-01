# Script de déploiement Kubernetes complet
# Usage: .\scripts\deploy-k8s.ps1 [-Namespace devsecops] [-ImageName kubernetes-webapp:latest] [-WaitForRollout]

param(
    [string]$Namespace = "devsecops",
    [string]$ImageName = "kubernetes-webapp:latest",
    [switch]$WaitForRollout,
    [string]$Context = ""
)

$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Check-Prerequisites {
    Write-Header "Vérification des prérequis"
    
    # Check kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Host "❌ kubectl n'est pas installé ou non accessible" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ kubectl trouvé" -ForegroundColor Green
    
    # Check current context
    $CurrentContext = kubectl config current-context 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Aucun contexte kubectl configuré" -ForegroundColor Red
        Write-Host "Veuillez configurer kubectl avec: kubectl config use-context <context-name>" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✅ Contexte actuel: $CurrentContext" -ForegroundColor Green
    
    # Check if namespace exists
    $NSExists = kubectl get namespace $Namespace 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Namespace '$Namespace' n'existe pas, création..." -ForegroundColor Yellow
        kubectl create namespace $Namespace
        Write-Host "✅ Namespace créé" -ForegroundColor Green
    } else {
        Write-Host "✅ Namespace '$Namespace' existe" -ForegroundColor Green
    }
}

function Deploy-StorageClass {
    Write-Header "Déploiement de la classe de stockage"
    kubectl apply -f k8s/postgres-storageclass.yaml
    Write-Host "✅ StorageClass déployée" -ForegroundColor Green
}

function Deploy-Postgres {
    Write-Header "Déploiement de PostgreSQL"
    
    # Deploy secret
    kubectl apply -f k8s/postgres-secret.yaml
    Write-Host "✅ Secret PostgreSQL appliqué" -ForegroundColor Green
    
    # Deploy configmap
    kubectl apply -f k8s/postgres-configmap.yaml
    Write-Host "✅ ConfigMap PostgreSQL appliquée" -ForegroundColor Green
    
    # Deploy init script configmap
    kubectl apply -f k8s/postgres-init-configmap.yaml
    Write-Host "✅ ConfigMap init script PostgreSQL appliquée" -ForegroundColor Green
    
    # Deploy PVC
    kubectl apply -f k8s/postgres-pvc.yaml
    Write-Host "✅ PersistentVolumeClaim déployée" -ForegroundColor Green
    
    # Deploy service
    kubectl apply -f k8s/service-db.yaml
    Write-Host "✅ Service PostgreSQL déployé" -ForegroundColor Green
    
    # Deploy deployment
    kubectl apply -f k8s/postgres-deployment.yaml
    Write-Host "✅ Deployment PostgreSQL déployé" -ForegroundColor Green
    
    Write-Host "`n⏳ Attente du démarrage de PostgreSQL..." -ForegroundColor Yellow
    kubectl rollout status deployment/postgres-deployment -n $Namespace --timeout=5m
    Write-Host "✅ PostgreSQL est prêt" -ForegroundColor Green
    
    # Show postgres pod status
    Write-Host "`nPod PostgreSQL:" -ForegroundColor Cyan
    kubectl get pods -n $Namespace -l app=postgres
}

function Deploy-WebApp {
    Write-Header "Déploiement de l'application web"
    
    # Deploy secret
    kubectl apply -f k8s/webapp-secret.yaml
    Write-Host "✅ Secret application déployé" -ForegroundColor Green
    
    # Deploy configmap
    kubectl apply -f k8s/webapp-configmap.yaml
    Write-Host "✅ ConfigMap application déployée" -ForegroundColor Green
    
    # Deploy service NodePort
    kubectl apply -f k8s/service-web.yaml
    Write-Host "✅ Services application déployés" -ForegroundColor Green
    
    # Deploy deployment
    kubectl apply -f k8s/webapp-deployment.yaml
    Write-Host "✅ Deployment application déployé" -ForegroundColor Green
    
    if ($WaitForRollout) {
        Write-Host "`n⏳ Attente du déploiement de l'application..." -ForegroundColor Yellow
        kubectl rollout status deployment/webapp-deployment -n $Namespace --timeout=5m
        Write-Host "✅ Application est prête" -ForegroundColor Green
    }
    
    # Show webapp pod status
    Write-Host "`nPods application:" -ForegroundColor Cyan
    kubectl get pods -n $Namespace -l app=webapp
}

function Show-DeploymentInfo {
    Write-Header "Informations de déploiement"
    
    # Show all resources
    Write-Host "`n📦 Déploiements:" -ForegroundColor Cyan
    kubectl get deployments -n $Namespace
    
    Write-Host "`n📦 Services:" -ForegroundColor Cyan
    kubectl get services -n $Namespace
    
    Write-Host "`n📦 PVCs:" -ForegroundColor Cyan
    kubectl get pvc -n $Namespace
    
    Write-Host "`n📦 Secrets:" -ForegroundColor Cyan
    kubectl get secrets -n $Namespace
    
    Write-Host "`n📦 ConfigMaps:" -ForegroundColor Cyan
    kubectl get configmaps -n $Namespace
    
    # Show NodePort information
    Write-Host "`n🔗 Accès à l'application:" -ForegroundColor Cyan
    $NodePort = kubectl get service webapp-service -n $Namespace -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null
    if ($NodePort) {
        $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null
        if (-not $Node) {
            $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
        }
        Write-Host "  Application accessible sur: http://$($Node):$NodePort" -ForegroundColor Green
    }
}

# Main execution
try {
    Write-Host "`n🚀 Déploiement Kubernetes du projet DevSecOps" -ForegroundColor Yellow
    Write-Host "   Namespace: $Namespace" -ForegroundColor Yellow
    Write-Host "   Image: $ImageName" -ForegroundColor Yellow
    
    Check-Prerequisites
    Deploy-StorageClass
    Deploy-Postgres
    Start-Sleep -Seconds 5
    Deploy-WebApp
    Show-DeploymentInfo
    
    Write-Header "✅ Déploiement complété avec succès!"
    Write-Host "Commandes utiles:" -ForegroundColor Yellow
    Write-Host "  kubectl get pods -n $Namespace                          # Lister les pods"
    Write-Host "  kubectl logs -n $Namespace -l app=postgres -f           # Logs PostgreSQL"
    Write-Host "  kubectl logs -n $Namespace -l app=webapp -f             # Logs application"
    Write-Host "  kubectl port-forward -n $Namespace svc/postgres-service 5432:5432  # Port forwarding DB"
    Write-Host "  kubectl port-forward -n $Namespace svc/webapp-service 3000:80     # Port forwarding app"
    Write-Host "`n"
    
} catch {
    Write-Host "`n❌ Erreur lors du déploiement:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
