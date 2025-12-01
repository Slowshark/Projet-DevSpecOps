# Quick Start - Déploiement Kubernetes

## ⚡ Démarrage rapide (5 minutes)

### 1️⃣ Vérifier les prérequis

```powershell
# Vérifier Docker
docker --version
docker run hello-world

# Vérifier kubectl
kubectl version --client
kubectl cluster-info
```

### 2️⃣ Construire l'image Docker

```powershell
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project

# Build
docker build -t kubernetes-webapp:latest .

# Vérifier
docker images | grep kubernetes-webapp
```

### 3️⃣ Déployer sur Kubernetes (Automatique)

```powershell
# Déploiement complet en une commande
.\scripts\deploy-k8s.ps1 -Namespace devsecops -WaitForRollout

# Le script va:
# ✅ Créer le namespace
# ✅ Déployer PostgreSQL
# ✅ Déployer l'application web
# ✅ Configurer les services
# ✅ Afficher les informations d'accès
```

### 4️⃣ Vérifier le déploiement

```powershell
# Vérification complète
.\scripts\verify-k8s-deployment.ps1 -Namespace devsecops -WaitForReady

# Ou vérification rapide
kubectl get pods -n devsecops
kubectl get services -n devsecops
```

### 5️⃣ Accéder à l'application

```powershell
# Récupérer l'URL
$NodePort = kubectl get service webapp-service -n devsecops -o jsonpath='{.spec.ports[0].nodePort}'
$Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
if (-not $Node) {
  $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}
Write-Host "👉 Ouvrir: http://$($Node):$NodePort"
```

Ouvrir dans le navigateur et tester les fonctionnalités (ajouter/modifier/supprimer des tâches).

## 🧪 Tests API rapides

```powershell
$NodePort = kubectl get service webapp-service -n devsecops -o jsonpath='{.spec.ports[0].nodePort}'
$Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
if (-not $Node) { $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' }
$Url = "http://$($Node):$NodePort"

# Test 1: Health
Invoke-RestMethod -Uri "$Url/api/health" -UseBasicParsing | ConvertTo-Json

# Test 2: Récupérer tâches
Invoke-RestMethod -Uri "$Url/api/tasks" -UseBasicParsing | ConvertTo-Json

# Test 3: Créer tâche
Invoke-RestMethod -Uri "$Url/api/tasks" -Method POST `
  -ContentType "application/json" `
  -Body '{"title":"Test","description":"De déploiement K8s"}' `
  -UseBasicParsing | ConvertTo-Json
```

## 🔍 Debugging

```powershell
# Logs PostgreSQL
kubectl logs -n devsecops -l app=postgres -f

# Logs Application
kubectl logs -n devsecops -l app=webapp -f

# Accéder au pod PostgreSQL
$PgPod = kubectl get pods -n devsecops -l app=postgres -o jsonpath='{.items[0].metadata.name}'
kubectl exec -it -n devsecops $PgPod -- psql -U admin -d tasksdb

# Port forwarding
kubectl port-forward -n devsecops svc/postgres-service 5432:5432 &
kubectl port-forward -n devsecops svc/webapp-service 3000:80
```

## 🧹 Nettoyage

```powershell
# Supprimer le namespace (tout)
kubectl delete namespace devsecops

# Supprimer l'image Docker
docker rmi kubernetes-webapp:latest
```

## 📖 Documentation complète

Voir: `DEPLOYMENT_GUIDE_KUBERNETES.md`

---

**Temps estimé de déploiement**: 5-10 minutes  
**Ressources requises**: 2GB RAM, 2 CPUs minimum
