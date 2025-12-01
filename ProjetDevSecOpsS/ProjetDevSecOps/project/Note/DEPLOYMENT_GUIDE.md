# Guide de Deploiement - Application Web sur Kubernetes

Ce guide explique comment deployer une application web Node.js avec une base de donnees sur un cluster Kubernetes.

## Architecture du Projet

L'application est composee de :
- **Frontend** : Application React avec TypeScript
- **Backend** : Serveur Node.js Express
- **Base de donnees** : Supabase (PostgreSQL heberge) + Configuration PostgreSQL locale pour Kubernetes
- **Orchestration** : Kubernetes avec Docker

## Prerequis

- Docker installe (version 20.x ou superieure)
- Kubernetes installe (minikube, kind, ou cluster K8s)
- kubectl configure et connecte au cluster
- Node.js 18+ (pour le developpement local)

## Structure des Fichiers

```
project/
├── src/                          # Code source React
├── server/                       # Serveur Node.js Express
│   ├── index.js
│   └── package.json
├── k8s/                          # Fichiers Kubernetes
│   ├── postgres-secret.yaml
│   ├── postgres-configmap.yaml
│   ├── postgres-pvc.yaml
│   ├── postgres-deployment.yaml
│   ├── service-db.yaml
│   ├── webapp-secret.yaml
│   ├── webapp-deployment.yaml
│   └── service-web.yaml
├── database/                     # Scripts d'initialisation
│   └── init.sql
├── Dockerfile                    # Image Docker de l'application
└── DEPLOYMENT_GUIDE.md          # Ce fichier
```

## Etape 1 : Construction de l'Image Docker

### 1.1 Construction de l'image

```bash
docker build -t kubernetes-webapp:latest .
```

### 1.2 Verification de l'image

```bash
docker images | grep kubernetes-webapp
```

### 1.3 (Optionnel) Test local de l'image

```bash
docker run -p 3000:3000 \
  -e SUPABASE_URL=your-url \
  -e SUPABASE_ANON_KEY=your-key \
  kubernetes-webapp:latest
```

## Etape 2 : Deploiement de la Base de Donnees PostgreSQL

### 2.1 Creer le PersistentVolumeClaim

```bash
kubectl apply -f k8s/postgres-pvc.yaml
```

Verification :
```bash
kubectl get pvc
```

### 2.2 Creer les Secrets et ConfigMaps

```bash
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-configmap.yaml
```

Verification :
```bash
kubectl get secrets
kubectl get configmaps
```

### 2.3 Deployer PostgreSQL

```bash
kubectl apply -f k8s/postgres-deployment.yaml
```

Verification :
```bash
kubectl get deployments
kubectl get pods
kubectl logs -f <postgres-pod-name>
```

### 2.4 Creer le Service de Base de Donnees (ClusterIP)

```bash
kubectl apply -f k8s/service-db.yaml
```

Verification :
```bash
kubectl get services
```

### 2.5 Initialiser la Base de Donnees

```bash
# Se connecter au pod PostgreSQL
kubectl exec -it <postgres-pod-name> -- psql -U admin -d tasksdb

# Executer le script SQL
\i /path/to/init.sql

# Ou copier le fichier et l'executer
kubectl cp database/init.sql <postgres-pod-name>:/tmp/init.sql
kubectl exec -it <postgres-pod-name> -- psql -U admin -d tasksdb -f /tmp/init.sql
```

## Etape 3 : Deploiement de l'Application Web

### 3.1 Configurer les Secrets de l'Application

Editer `k8s/webapp-secret.yaml` et remplacer les valeurs :

```yaml
stringData:
  SUPABASE_URL: https://your-project.supabase.co
  SUPABASE_ANON_KEY: your-actual-anon-key
```

Appliquer :
```bash
kubectl apply -f k8s/webapp-secret.yaml
```

### 3.2 Deployer l'Application Web

```bash
kubectl apply -f k8s/webapp-deployment.yaml
```

Verification :
```bash
kubectl get deployments
kubectl get pods
kubectl logs -f <webapp-pod-name>
```

### 3.3 Creer le Service Web (NodePort)

```bash
kubectl apply -f k8s/service-web.yaml
```

Verification :
```bash
kubectl get services
```

## Etape 4 : Acces a l'Application

### 4.1 Avec Minikube

```bash
minikube service webapp-service
```

Ou obtenir l'URL :
```bash
minikube service webapp-service --url
```

### 4.2 Avec un Cluster Kubernetes

```bash
# Obtenir l'IP d'un noeud
kubectl get nodes -o wide

# L'application est accessible sur :
http://<NODE-IP>:30080
```

### 4.3 Verification de la Sante de l'Application

```bash
curl http://<NODE-IP>:30080/api/health
```

Reponse attendue :
```json
{
  "status": "healthy",
  "timestamp": "2024-11-27T...",
  "database": "connected"
}
```

## Etape 5 : Tests et Validation

### 5.1 Test des Fonctionnalites

1. Ouvrir l'application dans un navigateur
2. Ajouter une nouvelle tache
3. Marquer une tache comme completee
4. Supprimer une tache

### 5.2 Test de Persistance

```bash
# Supprimer un pod
kubectl delete pod <webapp-pod-name>

# Verifier que les donnees persistent
# Les donnees doivent rester apres le redemarrage du pod
```

### 5.3 Test de Mise a l'Echelle

```bash
# Augmenter le nombre de replicas
kubectl scale deployment webapp-deployment --replicas=3

# Verifier
kubectl get pods
```

## Etape 6 : Surveillance et Logs

### 6.1 Voir les Logs

```bash
# Logs de l'application web
kubectl logs -f deployment/webapp-deployment

# Logs de PostgreSQL
kubectl logs -f deployment/postgres-deployment
```

### 6.2 Executer des Commandes dans un Pod

```bash
# Shell dans le pod de l'application
kubectl exec -it <webapp-pod-name> -- sh

# Shell dans le pod PostgreSQL
kubectl exec -it <postgres-pod-name> -- bash
```

### 6.3 Verifier l'Etat du Cluster

```bash
kubectl get all
kubectl describe deployment webapp-deployment
kubectl describe service webapp-service
```

## Etape 7 : Nettoyage

Pour supprimer tous les ressources :

```bash
# Supprimer les deployments
kubectl delete -f k8s/webapp-deployment.yaml
kubectl delete -f k8s/postgres-deployment.yaml

# Supprimer les services
kubectl delete -f k8s/service-web.yaml
kubectl delete -f k8s/service-db.yaml

# Supprimer les secrets et configmaps
kubectl delete -f k8s/webapp-secret.yaml
kubectl delete -f k8s/postgres-secret.yaml
kubectl delete -f k8s/postgres-configmap.yaml

# Supprimer le PVC
kubectl delete -f k8s/postgres-pvc.yaml
```

Ou tout supprimer d'un coup :
```bash
kubectl delete -f k8s/
```

## Configuration Avancee

### Utiliser LoadBalancer au lieu de NodePort

Editer `k8s/service-web.yaml` :

```yaml
spec:
  type: LoadBalancer  # Changer NodePort en LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
```

### Ajouter des Ressources Limites

Les limites sont deja configurees dans les deployments :
- CPU : 100m-200m pour webapp, 250m-500m pour PostgreSQL
- Memoire : 128Mi-256Mi pour webapp, 256Mi-512Mi pour PostgreSQL

### Configurer un Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
spec:
  rules:
  - host: webapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapp-service
            port:
              number: 80
```

## Troubleshooting

### Les Pods ne Demarrent Pas

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Problemes de Connexion a la Base de Donnees

```bash
# Verifier que le service PostgreSQL est accessible
kubectl get endpoints postgres-service

# Tester la connexion depuis un pod
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- psql -h postgres-service -U admin -d tasksdb
```

### L'Application n'est Pas Accessible

```bash
# Verifier le service
kubectl get svc webapp-service

# Verifier les endpoints
kubectl get endpoints webapp-service

# Verifier les logs
kubectl logs -f deployment/webapp-deployment
```

## Notes de Securite

1. **Secrets** : Dans un environnement de production, utilisez des outils comme Sealed Secrets ou un gestionnaire de secrets externe
2. **RLS** : Les politiques RLS de Supabase sont configurees pour un acces public dans cette demo. En production, restreignez l'acces
3. **Network Policies** : Ajoutez des Network Policies pour controler le trafic entre les pods
4. **TLS** : Configurez TLS/HTTPS pour l'acces externe

## Support et Documentation

- Kubernetes : https://kubernetes.io/docs/
- Docker : https://docs.docker.com/
- PostgreSQL : https://www.postgresql.org/docs/
- Supabase : https://supabase.com/docs
- Node.js : https://nodejs.org/docs/

## Conclusion

Vous avez maintenant une application web complete deployee sur Kubernetes avec :
- Persistance des donnees via PersistentVolumeClaim
- Gestion securisee des secrets
- Services internes (ClusterIP) et externes (NodePort)
- Haute disponibilite avec plusieurs replicas
- Health checks et readiness probes
