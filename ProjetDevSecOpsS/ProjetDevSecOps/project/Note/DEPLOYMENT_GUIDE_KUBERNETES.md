# Guide de Déploiement Complet - Kubernetes DevSecOps Project

## 📋 Vue d'ensemble

Ce guide décrit le déploiement complet d'une application web Node.js/React avec une base de données PostgreSQL sur Kubernetes.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Node / Worker                               │  │
│  │  ┌──────────────┐  ┌──────────────────────┐ │  │
│  │  │ PostgreSQL   │  │ WebApp Pod (x2)      │ │  │
│  │  │ Pod          │  │ - Express.js         │ │  │
│  │  │ - Port 5432  │  │ - React Frontend     │ │  │
│  │  │ - PVC: 1Gi   │  │ - Port 3000          │ │  │
│  │  └──────────────┘  └──────────────────────┘ │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
├─────────────────────────────────────────────────────┤
│  Services:                                         │
│  - postgres-service (ClusterIP:5432)               │
│  - webapp-service (NodePort:30080 -> :3000)        │
│  - webapp-service-lb (LoadBalancer, optionnel)     │
├─────────────────────────────────────────────────────┤
│  Configuration:                                    │
│  - Secrets: postgres-secret, webapp-secret         │
│  - ConfigMaps: postgres-config, postgres-init-sql, │
│                webapp-config                       │
│  - PVC: postgres-pvc (1Gi)                         │
│  - StorageClass: postgres-storage-class            │
└─────────────────────────────────────────────────────┘
```

## 🚀 Prérequis

### 1. Environnement local
- **Docker** : Pour la construction d'images
- **Docker Compose** : Pour les tests locaux
- **kubectl** : Pour gérer Kubernetes
- **PowerShell 5.1+** : Pour exécuter les scripts de déploiement

### 2. Cluster Kubernetes
- Cluster Kubernetes fonctionnel (local avec Minikube/Docker Desktop, ou cloud)
- kubectl configuré et connecté au cluster
- Stockage disponible pour les PersistentVolumeClaim

### 3. Permissions
- Droits pour créer des namespaces
- Droits pour créer des Deployments, Services, PVC, Secrets, ConfigMaps
- Droits pour gérer les StorageClass (si nécessaire)

### Vérifier les prérequis

```powershell
# Vérifier Docker
docker --version
docker-compose --version

# Vérifier kubectl
kubectl version --client
kubectl get nodes

# Vérifier la connexion à un cluster
kubectl cluster-info
```

## 📦 Étape 1: Construire l'image Docker

### 1.1 Construction locale

```powershell
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project

# Construire l'image Docker
docker build -t kubernetes-webapp:latest .

# Vérifier la construction
docker images | grep kubernetes-webapp
```

### 1.2 Vérification de l'image

```powershell
# Lancer le conteneur localement pour tester
docker run -p 3000:3000 \
  -e POSTGRES_HOST=localhost \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_DB=tasksdb \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=supersecretpassword \
  kubernetes-webapp:latest

# Tester l'endpoint
curl http://localhost:3000/api/health

# Arrêter le conteneur
docker stop <container-id>
```

## 🔧 Étape 2: Configurer Kubernetes

### 2.1 Vérifier la connexion au cluster

Pour **Docker Desktop avec Kubernetes activé** :
```powershell
kubectl config current-context
# Devrait afficher: docker-desktop
```

Pour **Minikube** :
```powershell
kubectl config current-context
# Devrait afficher: minikube
```

Pour un **cluster cloud** (AWS EKS, GCP GKE, Azure AKS) :
```powershell
# Configurer d'abord la connexion au cluster
# Exemple AWS EKS:
aws eks update-kubeconfig --name <cluster-name> --region <region>

kubectl config current-context
# Affichera votre cluster
```

### 2.2 Créer le namespace

```powershell
# Le script de déploiement crée le namespace automatiquement
# Ou créez-le manuellement:
kubectl create namespace devsecops
kubectl label namespace devsecops name=devsecops
```

## 🚀 Étape 3: Déployer sur Kubernetes

### 3.1 Déploiement automatisé (Recommandé)

```powershell
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project

# Rendre le script exécutable et le lancer
.\scripts\deploy-k8s.ps1 -Namespace devsecops -WaitForRollout

# Avec timeout personnalisé:
.\scripts\deploy-k8s.ps1 -Namespace devsecops -WaitForRollout -HealthCheckTimeout 600
```

### 3.2 Déploiement manuel (Optionnel)

Si vous préférez déployer étape par étape :

```powershell
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project

# 1. StorageClass et namespace
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-storageclass.yaml

# 2. Configuration PostgreSQL
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-configmap.yaml
kubectl apply -f k8s/postgres-init-configmap.yaml

# 3. Stockage PostgreSQL
kubectl apply -f k8s/postgres-pvc.yaml

# 4. Services
kubectl apply -f k8s/service-db.yaml

# 5. PostgreSQL Deployment
kubectl apply -f k8s/postgres-deployment.yaml

# Attendre que PostgreSQL soit prêt
kubectl rollout status deployment/postgres-deployment -n devsecops --timeout=5m

# 6. Configuration Application
kubectl apply -f k8s/webapp-secret.yaml
kubectl apply -f k8s/webapp-configmap.yaml
kubectl apply -f k8s/service-web.yaml

# 7. Application Deployment
kubectl apply -f k8s/webapp-deployment.yaml

# Attendre que l'application soit prête
kubectl rollout status deployment/webapp-deployment -n devsecops --timeout=5m
```

## ✅ Étape 4: Vérifier le déploiement

### 4.1 Vérification automatisée

```powershell
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project

# Vérification complète
.\scripts\verify-k8s-deployment.ps1 -Namespace devsecops -WaitForReady
```

### 4.2 Vérification manuelle

```powershell
# Vérifier l'état des pods
kubectl get pods -n devsecops
kubectl get pods -n devsecops -l app=postgres
kubectl get pods -n devsecops -l app=webapp

# Vérifier les services
kubectl get services -n devsecops

# Vérifier les PersistentVolumeClaim
kubectl get pvc -n devsecops

# Vérifier les Secrets et ConfigMaps
kubectl get secrets -n devsecops
kubectl get configmaps -n devsecops

# Vérifier les logs
kubectl logs -n devsecops -l app=postgres --tail=20
kubectl logs -n devsecops -l app=webapp --tail=20 -f
```

## 🌐 Étape 5: Accéder à l'application

### 5.1 Via NodePort (Local et cloud)

```powershell
# Récupérer le NodePort
$NodePort = kubectl get service webapp-service -n devsecops `
  -o jsonpath='{.spec.ports[0].nodePort}'

# Récupérer l'IP du nœud
$Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
if (-not $Node) {
  $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}

Write-Host "Accès à l'application: http://$($Node):$NodePort"
```

### 5.2 Via LoadBalancer (Cloud uniquement)

```powershell
# Récupérer l'adresse publique (peut prendre quelques minutes)
kubectl get service webapp-service-lb -n devsecops -w

# L'IP externe apparaîtra après que le LoadBalancer soit provisionné
```

### 5.3 Via Port-Forward (Développement)

```powershell
# Application web
kubectl port-forward -n devsecops svc/webapp-service 3000:80

# Base de données (depuis un autre terminal)
kubectl port-forward -n devsecops svc/postgres-service 5432:5432

# Accéder à l'application: http://localhost:3000
# Accéder à la DB: localhost:5432
```

## 🧪 Étape 6: Tester les fonctionnalités

### 6.1 Test de l'API

```powershell
# Récupérer le NodePort
$NodePort = kubectl get service webapp-service -n devsecops -o jsonpath='{.spec.ports[0].nodePort}'
$Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
if (-not $Node) { $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' }
$BaseUrl = "http://$($Node):$NodePort"

# Test 1: Health check
$Health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -UseBasicParsing
Write-Host "Health: $($Health | ConvertTo-Json)"

# Test 2: Récupérer les tâches
$Tasks = Invoke-RestMethod -Uri "$BaseUrl/api/tasks" -UseBasicParsing
Write-Host "Tâches: $($Tasks | ConvertTo-Json)"

# Test 3: Créer une tâche
$NewTask = @{
    title = "Tâche test de déploiement Kubernetes"
    description = "Vérifier que la création fonctionne"
} | ConvertTo-Json

$Created = Invoke-RestMethod -Uri "$BaseUrl/api/tasks" -Method POST `
    -ContentType "application/json" -Body $NewTask -UseBasicParsing
Write-Host "Tâche créée: $($Created | ConvertTo-Json)"

# Test 4: Mettre à jour une tâche
$TaskId = $Created.task.id
$Update = @{ completed = $true } | ConvertTo-Json

$Updated = Invoke-RestMethod -Uri "$BaseUrl/api/tasks/$TaskId" -Method PUT `
    -ContentType "application/json" -Body $Update -UseBasicParsing
Write-Host "Tâche mise à jour: $($Updated | ConvertTo-Json)"

# Test 5: Supprimer une tâche
Invoke-RestMethod -Uri "$BaseUrl/api/tasks/$TaskId" -Method DELETE -UseBasicParsing
Write-Host "Tâche supprimée"
```

### 6.2 Test via l'interface web

1. Ouvrir le navigateur : `http://<node-ip>:30080`
2. Tester les fonctionnalités :
   - Ajouter une nouvelle tâche
   - Marquer une tâche comme complétée
   - Supprimer une tâche
   - Rafraîchir la page et vérifier la persistance

## 💾 Étape 7: Valider la persistance des données

### 7.1 Test de redémarrage du Pod PostgreSQL

```powershell
# 1. Créer une tâche via l'API
# (Voir section 6.1 - Test 3)

# 2. Supprimer le pod PostgreSQL
$PgPod = kubectl get pods -n devsecops -l app=postgres -o jsonpath='{.items[0].metadata.name}'
kubectl delete pod -n devsecops $PgPod

# 3. Attendre que le nouveau pod se lève
kubectl rollout status deployment/postgres-deployment -n devsecops --timeout=2m

# 4. Vérifier que les données sont toujours présentes
# Consulter l'API GET /api/tasks
```

### 7.2 Test de redémarrage du Pod Application

```powershell
# 1. Supprimer un pod application
$WebPod = kubectl get pods -n devsecops -l app=webapp -o jsonpath='{.items[0].metadata.name}'
kubectl delete pod -n devsecops $WebPod

# 2. Attendre que le nouveau pod se lève
kubectl rollout status deployment/webapp-deployment -n devsecops --timeout=2m

# 3. L'application fonctionne avec les mêmes données dans PostgreSQL
```

### 7.3 Vérifier le stockage PVC

```powershell
# Accéder au pod PostgreSQL
$PgPod = kubectl get pods -n devsecops -l app=postgres -o jsonpath='{.items[0].metadata.name}'

# Vérifier le volume PVC
kubectl exec -n devsecops $PgPod -- df -h /var/lib/postgresql/data

# Dump de la base de données
kubectl exec -n devsecops $PgPod -- pg_dump -U admin tasksdb | Out-File "./tasksdb_backup.sql"
```

## 🔒 Configuration de sécurité

### Secrets

Les secrets sont stockés dans `k8s/postgres-secret.yaml` et `k8s/webapp-secret.yaml`.

⚠️ **Important** : En production, utiliser:
- Un gestionnaire de secrets (HashiCorp Vault, AWS Secrets Manager)
- Chiffrer les secrets dans le repository (Sealed Secrets, SOPS)
- Mettre à jour les mots de passe fort

```powershell
# Mettre à jour un secret
$NewPassword = "VotreNouveauMotDePasseFort"
$Base64Pass = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NewPassword))

kubectl patch secret postgres-secret -n devsecops -p `
  "{\"data\":{\"POSTGRES_PASSWORD\":\"$Base64Pass\"}}"
```

### Network Policy

Pour restricter le trafic réseau (optionnel) :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-network-policy
  namespace: devsecops
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: webapp
    ports:
    - protocol: TCP
      port: 5432
```

## 🛠️ Maintenance et Dépannage

### Logs

```powershell
# Logs PostgreSQL
kubectl logs -n devsecops -l app=postgres -f

# Logs Application (tous les pods)
kubectl logs -n devsecops -l app=webapp -f --all-containers=true

# Logs d'un pod spécifique
$Pod = kubectl get pods -n devsecops -l app=webapp -o jsonpath='{.items[0].metadata.name}'
kubectl logs -n devsecops $Pod --previous  # Si le pod a redémarré
```

### Exec dans un pod

```powershell
# Shell PostgreSQL
$PgPod = kubectl get pods -n devsecops -l app=postgres -o jsonpath='{.items[0].metadata.name}'
kubectl exec -it -n devsecops $PgPod -- psql -U admin -d tasksdb

# Shell Application
$WebPod = kubectl get pods -n devsecops -l app=webapp -o jsonpath='{.items[0].metadata.name}'
kubectl exec -it -n devsecops $WebPod -- sh
```

### Événements

```powershell
# Tous les événements du namespace
kubectl get events -n devsecops --sort-by='.lastTimestamp'

# Événements d'un pod
$Pod = kubectl get pods -n devsecops -l app=postgres -o jsonpath='{.items[0].metadata.name}'
kubectl describe pod -n devsecops $Pod
```

### Dépannage courant

**Les pods ne démarrent pas**
```powershell
kubectl describe pod -n devsecops <pod-name>
kubectl logs -n devsecops <pod-name>
```

**La base de données ne se connecte pas**
```powershell
# Vérifier le service
kubectl get service postgres-service -n devsecops -o yaml

# Tester la connectivité
$WebPod = kubectl get pods -n devsecops -l app=webapp -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n devsecops $WebPod -- nslookup postgres-service.devsecops.svc.cluster.local
```

**L'application ne répond pas**
```powershell
# Vérifier le service NodePort
kubectl get service webapp-service -n devsecops

# Port forwarding pour accès local
kubectl port-forward -n devsecops svc/webapp-service 3000:80
```

## 📊 Étape 8: Monitoring et mise à l'échelle

### Scaling manuel

```powershell
# Augmenter le nombre de replicas
kubectl scale deployment webapp-deployment -n devsecops --replicas=3

# Vérifier
kubectl get pods -n devsecops -l app=webapp
```

### Métriques

```powershell
# Utilisation des ressources (si metrics-server est installé)
kubectl top nodes
kubectl top pods -n devsecops
```

## 🧹 Nettoyage

### Supprimer le déploiement complet

```powershell
# Supprimer le namespace (supprime tout en dessous)
kubectl delete namespace devsecops

# Ou supprimer les ressources individuellement
kubectl delete deployment,service,secret,configmap,pvc -n devsecops -l app=postgres,app=webapp
```

### Supprimer l'image Docker

```powershell
docker rmi kubernetes-webapp:latest
```
