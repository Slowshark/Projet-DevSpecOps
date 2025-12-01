# Guide de Demarrage Rapide

## Deploiement en 5 Minutes

### 1. Preparer l'Image Docker

```bash
chmod +x scripts/*.sh
./scripts/build.sh
```

### 2. Configurer Supabase

Editer `k8s/webapp-secret.yaml` et remplacer:
```yaml
SUPABASE_URL: https://your-project.supabase.co
SUPABASE_ANON_KEY: your-actual-anon-key
```

### 3. Deployer sur Kubernetes

```bash
./scripts/deploy.sh
```

### 4. Acceder a l'Application

**Avec Minikube:**
```bash
minikube service webapp-service
```

**Avec K8s Cluster:**
```bash
kubectl get nodes -o wide
# Ouvrir http://<NODE-IP>:30080
```

### 5. Verifier

```bash
curl http://<URL>/api/health
```

## Commandes Utiles

### Voir les Logs
```bash
kubectl logs -f deployment/webapp-deployment
kubectl logs -f deployment/postgres-deployment
```

### Mise a l'Echelle
```bash
kubectl scale deployment webapp-deployment --replicas=3
```

### Statut
```bash
kubectl get all
kubectl get pods
kubectl get services
```

### Nettoyage
```bash
./scripts/cleanup.sh
```

## Troubleshooting Rapide

### Pod ne demarre pas
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Service inaccessible
```bash
kubectl get endpoints webapp-service
kubectl get svc
```

### Base de donnees
```bash
kubectl exec -it <postgres-pod> -- psql -U admin -d tasksdb
```

## Documentation Complete

Pour plus de details, consultez:
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Guide complet
- [README.md](./README.md) - Documentation generale
- [LIVRABLES.md](./LIVRABLES.md) - Liste des livrables

## Support

Les logs sont votre meilleur ami:
```bash
kubectl logs -f deployment/webapp-deployment
```
