# Projet Kubernetes - Application Web avec Base de Donnees

Application de gestion de taches deployee sur Kubernetes avec Node.js, React et PostgreSQL/Supabase.

## Description

Ce projet illustre le deploiement d'une application web complete sur un cluster Kubernetes. L'application permet de gerer des taches (todo list) avec une interface web moderne et une API REST.

## Fonctionnalites

- Interface utilisateur React moderne et responsive
- API REST Node.js/Express
- Base de donnees PostgreSQL avec Supabase
- Deploiement Kubernetes avec :
  - Deployments pour l'application et la base de donnees
  - Services ClusterIP et NodePort
  - Secrets et ConfigMaps pour la configuration
  - PersistentVolumeClaim pour la persistance des donnees
  - Health checks et readiness probes
  - Mise a l'echelle automatique

## Technologies Utilisees

- **Frontend** : React 18, TypeScript, Tailwind CSS
- **Backend** : Node.js 18, Express
- **Base de donnees** : PostgreSQL 15, Supabase
- **Containerisation** : Docker
- **Orchestration** : Kubernetes
- **Build** : Vite

## Structure du Projet

```
project/
├── src/                    # Code source React
├── server/                 # Serveur Node.js
├── k8s/                    # Configurations Kubernetes
│   ├── postgres-*.yaml     # Configuration PostgreSQL
│   ├── webapp-*.yaml       # Configuration application web
│   ├── service-*.yaml      # Services K8s
├── database/               # Scripts SQL
├── Dockerfile              # Image Docker
├── DEPLOYMENT_GUIDE.md     # Guide de deploiement detaille
└── README.md               # Ce fichier
```

## Quick Start

### Prerequis

- Docker
- Kubernetes (minikube/kind/k8s cluster)
- kubectl
- Node.js 18+

### Installation et Deploiement

1. **Cloner le projet et installer les dependances**

```bash
npm install
cd server && npm install && cd ..
```

2. **Construire l'image Docker**

```bash
docker build -t kubernetes-webapp:latest .
```

3. **Deployer sur Kubernetes**

```bash
# Creer tous les ressources
kubectl apply -f k8s/

# Verifier le deploiement
kubectl get all
```

4. **Acceder a l'application**

```bash
# Avec minikube
minikube service webapp-service

# Ou obtenir l'URL
minikube service webapp-service --url
```

### Developpement Local

```bash
# Frontend (dev mode)
npm run dev

# Backend
cd server
npm start
```

## Documentation

Consultez [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) pour :
- Instructions detaillees de deploiement
- Configuration avancee
- Troubleshooting
- Tests et validation
- Gestion des ressources

## Livrables du Projet

### Fichiers de Configuration Kubernetes

- `k8s/postgres-deployment.yaml` - Deployment PostgreSQL
- `k8s/webapp-deployment.yaml` - Deployment application web
- `k8s/service-db.yaml` - Service ClusterIP pour la base de donnees
- `k8s/service-web.yaml` - Service NodePort pour l'application web
- `k8s/postgres-secret.yaml` - Secrets PostgreSQL
- `k8s/webapp-secret.yaml` - Secrets application web
- `k8s/postgres-configmap.yaml` - Configuration PostgreSQL
- `k8s/postgres-pvc.yaml` - PersistentVolumeClaim

### Code Source

- `src/` - Application React TypeScript
- `server/` - API Node.js Express
- `database/init.sql` - Script d'initialisation de la base de donnees

### Documentation

- `DEPLOYMENT_GUIDE.md` - Guide complet de deploiement
- `README.md` - Documentation generale du projet
- `Dockerfile` - Configuration Docker

## API Endpoints

- `GET /api/health` - Verification de l'etat de l'application
- `GET /api/tasks` - Recuperer toutes les taches
- `POST /api/tasks` - Creer une nouvelle tache
- `PUT /api/tasks/:id` - Mettre a jour une tache
- `DELETE /api/tasks/:id` - Supprimer une tache

## Architecture Kubernetes

### Base de Donnees (PostgreSQL)

- **Deployment** : 1 replica avec volume persistent
- **Service** : ClusterIP (acces interne uniquement)
- **Storage** : PersistentVolumeClaim de 1Gi
- **Configuration** : Secrets pour les credentials, ConfigMap pour les parametres

### Application Web

- **Deployment** : 2 replicas pour la haute disponibilite
- **Service** : NodePort (acces externe sur le port 30080)
- **Configuration** : Secrets pour les credentials Supabase
- **Health Checks** : Liveness et Readiness probes configurees

## Tests

### Tests Fonctionnels

1. Ajouter une tache
2. Marquer une tache comme completee
3. Supprimer une tache
4. Verifier la persistance des donnees apres redemarrage

### Tests de Resilience

```bash
# Supprimer un pod et verifier la recreation automatique
kubectl delete pod <pod-name>

# Verifier que les donnees persistent
kubectl get pods
```

### Tests de Performance

```bash
# Mise a l'echelle
kubectl scale deployment webapp-deployment --replicas=5

# Verification
kubectl get pods -w
```

## Securite

- Secrets Kubernetes pour les informations sensibles
- Row Level Security (RLS) sur Supabase
- Variables d'environnement pour la configuration
- Pas d'exposition directe de la base de donnees

## Maintenance

### Logs

```bash
# Logs de l'application
kubectl logs -f deployment/webapp-deployment

# Logs de la base de donnees
kubectl logs -f deployment/postgres-deployment
```

### Mise a Jour

```bash
# Mettre a jour l'image
docker build -t kubernetes-webapp:v2 .
kubectl set image deployment/webapp-deployment webapp=kubernetes-webapp:v2

# Verifier le rollout
kubectl rollout status deployment/webapp-deployment
```

### Sauvegarde

```bash
# Backup de la base de donnees
kubectl exec <postgres-pod> -- pg_dump -U admin tasksdb > backup.sql
```

## Licence

Ce projet est un projet educatif pour apprendre Kubernetes et Docker.

## Auteur

Projet realise dans le cadre du cours de containerisation et orchestration.

## Contact

Pour toute question concernant le deploiement, consultez le [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md).
