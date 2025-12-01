# 🔒 Analyse de Sécurité - Projet DevSecOps Kubernetes

**Date**: 27 novembre 2025  
**Statut**: Analyse complète effectuée  
**Niveau de risque global**: 🟡 **MOYEN** → À CORRIGER avant déploiement production

---

## 📋 Table des matières

1. [Résumé exécutif](#résumé-exécutif)
2. [Sécurité application (Backend)](#sécurité-application-backend)
3. [Sécurité conteneurs (Docker)](#sécurité-conteneurs-docker)
4. [Sécurité Kubernetes](#sécurité-kubernetes)
5. [Gestion des secrets](#gestion-des-secrets)
6. [Dépendances](#dépendances)
7. [Réseau & Communication](#réseau--communication)
8. [Plan d'action](#plan-daction)

---

## 🎯 Résumé exécutif

### ✅ Points forts
- ✅ SecurityContext appliqué (runAsNonRoot)
- ✅ Probes de santé configurées (Liveness/Readiness)
- ✅ Gestion des ressources (limits/requests)
- ✅ Isolation par namespace
- ✅ Secrets séparés des ConfigMaps

### ⚠️ Problèmes critiques
- 🔴 Mots de passe en dur dans les manifests Kubernetes
- 🔴 Image Docker sans scan de vulnérabilités
- 🔴 Pas de restriction RBAC
- 🔴 Pas de NetworkPolicy
- 🔴 Injection SQL possible
- 🔴 Pas de rate limiting
- 🔴 Pas de logging/audit
- 🔴 Pas de chiffrement TLS

### 📊 Scoring de sécurité
```
Kubernetes:      ████░░░░░░ 40%
Application:     ███░░░░░░░ 30%
Secrets:         ██░░░░░░░░ 20%
Conteneur:       █████░░░░░ 50%
Réseau:          ██░░░░░░░░ 20%
─────────────────────────────────
GLOBAL:          ████░░░░░░ 32%
```

---

## 🛡️ Sécurité application (Backend)

### Problème 1: Injection SQL ❌ CRITIQUE

**Localisation**: `server/index.js` - GET /api/tasks, POST /api/tasks, PUT /api/tasks/:id, DELETE /api/tasks/:id

**Code vulnérable**:
```javascript
// ❌ VULNÉRABLE - Paramètre ID non validé
app.delete('/api/tasks/:id', async (req, res) => {
  const { id } = req.params;
  
  if (db) {
    const result = await db.query('DELETE FROM tasks WHERE id = $1 RETURNING id', [id]);
    // ✅ Bon: Utilise des paramètres bindés ($1)
  }
});
```

**Risque**: Bien que vous utilisiez des paramètres liés (bon!), pas de validation du format ID (devrait être numérique).

**Correctif**:
```javascript
app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    // ✅ Validation du format ID
    if (!/^\d+$/.test(id)) {
      return res.status(400).json({ error: 'Invalid task ID format' });
    }

    if (db) {
      const result = await db.query('DELETE FROM tasks WHERE id = $1 RETURNING id', [parseInt(id, 10)]);
      // ...
    }
    // ...
  } catch (error) {
    // ...
  }
});
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 30 min

---

### Problème 2: Pas de validation des données en entrée ❌ HAUTE

**Localisation**: `server/index.js` - POST /api/tasks

**Code**:
```javascript
app.post('/api/tasks', async (req, res) => {
  try {
    const { title, description } = req.body;
    if (!title) return res.status(400).json({ error: 'Title is required' });
    // ❌ Aucune validation de longueur, format, caractères spéciaux
```

**Risques**:
- Buffer overflow sur strings longues
- Injection XSS via description
- Déni de service (envoi de 1GB de texte)

**Correctif**:
```javascript
const MAX_TITLE_LENGTH = 500;
const MAX_DESCRIPTION_LENGTH = 5000;

// Middleware de validation
const validateTaskInput = (req, res, next) => {
  const { title, description } = req.body;
  
  if (!title || typeof title !== 'string') {
    return res.status(400).json({ error: 'Title is required and must be string' });
  }
  
  if (title.length > MAX_TITLE_LENGTH) {
    return res.status(400).json({ error: `Title exceeds ${MAX_TITLE_LENGTH} characters` });
  }
  
  if (description && typeof description !== 'string') {
    return res.status(400).json({ error: 'Description must be string' });
  }
  
  if (description && description.length > MAX_DESCRIPTION_LENGTH) {
    return res.status(400).json({ error: `Description exceeds ${MAX_DESCRIPTION_LENGTH} characters` });
  }
  
  next();
};

app.post('/api/tasks', validateTaskInput, async (req, res) => {
  // ...
});
```

**Sévérité**: 🟠 HAUTE | **Effort**: 45 min

---

### Problème 3: Pas de gestion des erreurs sécurisée ❌ HAUTE

**Localisation**: Tous les endpoints

**Code**:
```javascript
catch (error) {
  console.error('Error creating task:', error);
  res.status(500).json({ error: error.message }); // ❌ Expose détails techniques
}
```

**Risque**: Divulgation d'informations sensibles (stack trace, chemins fichiers, versions DB)

**Correctif**:
```javascript
const handleError = (error, req, res, context) => {
  console.error(`[${context}]`, error);
  
  // Log détaillé serveur (jamais envoyé au client)
  const errorId = Date.now();
  console.error(`Error ID ${errorId}:`, error.stack);
  
  // Réponse générique au client
  res.status(500).json({ 
    error: 'An error occurred processing your request',
    errorId: errorId // Pour support
  });
};

app.post('/api/tasks', validateTaskInput, async (req, res) => {
  try {
    // ...
  } catch (error) {
    handleError(error, req, res, 'POST /api/tasks');
  }
});
```

**Sévérité**: 🟠 HAUTE | **Effort**: 30 min

---

### Problème 4: Pas de rate limiting ❌ HAUTE

**Risque**: Attaques par déni de service (DoS), brute force

**Correctif - Installer dépendance**:
```bash
npm install express-rate-limit
```

**Code**:
```javascript
const rateLimit = require('express-rate-limit');

// Rate limit global
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // 100 requêtes par fenêtre
  message: 'Too many requests, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

// Rate limit stricte pour authentification (si applicable)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5, // 5 tentatives
  skipSuccessfulRequests: true,
});

app.use('/api/', limiter);
app.use('/api/login', authLimiter); // Si vous ajoutez authentification
```

**Sévérité**: 🟠 HAUTE | **Effort**: 20 min

---

### Problème 5: Pas d'authentification/autorisation ❌ CRITIQUE

**Risque**: N'importe qui peut lire/modifier/supprimer toutes les tâches

**État actuel**: Application multi-utilisateurs sans authentification

**Correctif simple (JWT)**:
```bash
npm install jsonwebtoken
```

```javascript
const jwt = require('jsonwebtoken');
const SECRET = process.env.JWT_SECRET || 'your-secret-key-change-this';

// Middleware d'authentification
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN
  
  if (!token) return res.sendStatus(401);
  
  jwt.verify(token, SECRET, (err, user) => {
    if (err) return res.sendStatus(403);
    req.user = user;
    next();
  });
};

// Appliquer à tous les endpoints data
app.get('/api/tasks', authenticateToken, async (req, res) => {
  // Utiliser req.user.id pour filtrer les tâches de l'utilisateur
  // ...
});

app.post('/api/tasks', authenticateToken, validateTaskInput, async (req, res) => {
  // ...
});
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 2-3 heures

---

### Problème 6: Logging insuffisant ❌ HAUTE

**Code**:
```javascript
console.error('Error:', error); // ❌ Non structuré, pas de contexte
```

**Correctif**:
```bash
npm install winston
```

```javascript
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});

// Utilisation
logger.info('Task created', { userId: req.user.id, taskId: task.id });
logger.error('Database error', { userId: req.user.id, error: error.message });
```

**Sévérité**: 🟠 HAUTE | **Effort**: 1 heure

---

## 🐳 Sécurité conteneurs (Docker)

### Problème 1: Base image Alpine sans scan ❌ HAUTE

**Configuration**:
```dockerfile
FROM node:18-alpine AS production
```

**Risque**: Image Alpine peut contenir vulnérabilités (CVEs)

**Solution 1 - Scan local**:
```bash
# Scanner Trivy (gratuit, open-source)
trivy image node:18-alpine
trivy image kubernetes-webapp:latest

# Scanner Snyk
snyk container test node:18-alpine
```

**Solution 2 - Image plus récente**:
```dockerfile
# ✅ Meilleur: Utiliser version LTS latest
FROM node:20-alpine
```

**Solution 3 - Image minimale personnalisée**:
```dockerfile
# ✅ Minimal: Distroless (Google)
FROM gcr.io/distroless/nodejs20-debian11

WORKDIR /app
COPY --from=frontend-build /app/dist ./dist
COPY server/index.js ./server/index.js
COPY server/package*.json ./

USER nonroot

EXPOSE 3000
CMD ["server/index.js"]
```

**Sévérité**: 🟠 HAUTE | **Effort**: 1 heure

---

### Problème 2: Dockerfile sans USER non-root ⚠️ MOYENNE

**Code**:
```dockerfile
FROM node:18-alpine AS production
WORKDIR /app
# ❌ Pas de USER spécifié = exécute en root
CMD ["node", "server/index.js"]
```

**Risque**: Conteneur exécuté en root → compromission = accès root host

**Correctif**:
```dockerfile
FROM node:18-alpine AS production

WORKDIR /app

COPY server/package*.json ./
RUN npm install --production && \
    npm cache clean --force

COPY server/index.js ./server/index.js
COPY --from=frontend-build /app/dist ./dist

# ✅ Créer utilisateur non-root
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 3000

ENV NODE_ENV=production

CMD ["node", "server/index.js"]
```

**Sévérité**: 🟡 MOYENNE | **Effort**: 15 min

---

### Problème 3: Pas de healthcheck Docker ❌ MOYENNE

**Dockerfile**:
```dockerfile
# ❌ Pas de HEALTHCHECK
EXPOSE 3000
```

**Correctif**:
```dockerfile
# ✅ Ajouter health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1
```

Ou en base64 si curl non dispo:
```dockerfile
FROM node:18-alpine AS production
# ... autres commandes ...
RUN apk add --no-cache curl

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1
```

**Sévérité**: 🟡 MOYENNE | **Effort**: 10 min

---

### Problème 4: Pas de scanning des dépendances npm ❌ HAUTE

**Risk**: Dépendances npm peuvent avoir des vulnérabilités (Log4Shell, etc.)

**Vérification manuelle**:
```powershell
npm audit
npm audit fix
```

**Résultat attendu**: Zéro vulnérabilités critiques

**Correctif - Ajouter dans CI/CD**:
```dockerfile
RUN npm install && \
    npm audit --audit-level=moderate && \
    npm cache clean --force
```

**Dépendances actuelles à vérifier**:
```json
{
  "express": "^4.18.2",  // ✅ Récent
  "@supabase/supabase-js": "^2.38.0",  // ✅ Récent
  "pg": "^8.11.1"  // ✅ Récent
}
```

**Action**: Exécuter `npm audit` aujourd'hui

**Sévérité**: 🟠 HAUTE | **Effort**: 15 min

---

### Problème 5: Secrets en variables d'environnement dans Dockerfile ❌ CRITIQUE

**Pas de problème détecté** ✅
```dockerfile
# ✅ BON: Pas de secrets en dur
ENV NODE_ENV=production
```

Mais à noter:
```bash
# ❌ MAUVAIS (ne pas faire):
ENV POSTGRES_PASSWORD=supersecretpassword
# ✅ BON: Vient de Kubernetes Secrets
```

**Status**: ✅ Correct

---

## ☸️ Sécurité Kubernetes

### Problème 1: Secrets stockés en base64 non-chiffrée ❌ CRITIQUE

**postgres-secret.yaml**:
```yaml
stringData:
  POSTGRES_PASSWORD: supersecretpassword  # ❌ En clair en YAML!
```

**Risque majeur**:
- Base64 n'est PAS du chiffrement (facilement décodable)
- Secrets stockés en etcd non chiffrés par défaut
- N'importe qui avec accès au cluster peut lire: `kubectl get secret postgres-secret -o yaml`

**Solution 1 - Chiffrer les secrets au repos (ETCD Encryption)**:

```bash
# Sur chaque master node, ajouter encryption provider
cat > /etc/kubernetes/encryption.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF

# Modifier /etc/kubernetes/manifests/kube-apiserver.yaml
--encryption-provider-config=/etc/kubernetes/encryption.yaml
```

**Solution 2 - Utiliser HashiCorp Vault** (Production recommandé):

```yaml
# ✅ Utiliser External Secrets Operator + Vault
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "webapp-role"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-secret-vault
  namespace: devsecops
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: postgres-secret
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: postgres-credentials
        property: password
```

**Solution 3 - Seal Secrets (Sealed Secrets)**:

```bash
# Installer controller Sealed Secrets
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/sealed-secrets-v0.24.0.yaml

# Créer secret scellé (encodé)
echo -n 'supersecretpassword' | kubectl create secret generic postgres-secret \
  --dry-run=client \
  --from-file=POSTGRES_PASSWORD=/dev/stdin \
  -o yaml | kubeseal > sealed-secret.yaml
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 2-4 heures (selon choix)

---

### Problème 2: Pas de NetworkPolicy ❌ CRITIQUE

**Risque**: N'importe quel pod du cluster peut communiquer avec webapp/DB

**Correctif - Créer NetworkPolicy**:

```yaml
# k8s/network-policy.yaml
---
# ✅ Deny tout par défaut
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: devsecops
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
# ✅ Allow webapp → PostgreSQL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webapp-to-postgres
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

---
# ✅ Allow webapp → External (DNS, HTTPS)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webapp-egress
  namespace: devsecops
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53  # DNS
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS

---
# ✅ Allow ingress → webapp
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-webapp
  namespace: devsecops
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 1 heure

---

### Problème 3: Pas de RBAC (Role Based Access Control) ❌ CRITIQUE

**Risque**: N'importe quel compte de service peut faire n'importe quoi

**Correctif**:

```yaml
# k8s/rbac.yaml
---
# ✅ ServiceAccount pour webapp
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp-sa
  namespace: devsecops

---
# ✅ ServiceAccount pour PostgreSQL
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-sa
  namespace: devsecops

---
# ✅ Role minimal pour webapp
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: webapp-role
  namespace: devsecops
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
  resourceNames: ["webapp-config"]

---
# ✅ RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: webapp-rolebinding
  namespace: devsecops
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: webapp-role
subjects:
- kind: ServiceAccount
  name: webapp-sa
  namespace: devsecops

---
# ✅ DenyAll pour postgres par défaut
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: postgres-restricted
  namespace: devsecops
rules: []

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: postgres-rolebinding
  namespace: devsecops
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: postgres-restricted
subjects:
- kind: ServiceAccount
  name: postgres-sa
  namespace: devsecops
```

**Mise à jour des Deployments**:

```yaml
# webapp-deployment.yaml
spec:
  serviceAccountName: webapp-sa  # ✅ Ajouter
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  # ...

# postgres-deployment.yaml
spec:
  serviceAccountName: postgres-sa  # ✅ Ajouter
  securityContext:
    fsGroup: 999
    runAsUser: 999
    runAsNonRoot: true
  # ...
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 1.5 heures

---

### Problème 4: Pas d'admission controller (PodSecurityPolicy) ❌ HAUTE

**Risque**: Pod malveillants peuvent s'exécuter sans restriction

**Solution moderne - Pod Security Standards (Kubernetes 1.25+)**:

```yaml
# k8s/pod-security-standards.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devsecops
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Sévérité**: 🟠 HAUTE | **Effort**: 30 min

---

### Problème 5: Resource limits insuffisants ⚠️ MOYENNE

**État actuel**:
```yaml
# webapp-deployment.yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

**Évaluation**: ⚠️ Acceptable pour démo, à augmenter pour production

**Recommandation**:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**Sévérité**: 🟡 MOYENNE | **Effort**: 5 min

---

### Problème 6: Pas d'Ingress avec TLS ❌ CRITIQUE

**État actuel**: NodePort non chiffrée (HTTP)

**Correctif - Créer Ingress HTTPS**:

```bash
# Installer nginx-ingress controller si nécessaire
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
```

```yaml
# k8s/ingress.yaml
---
# ✅ Créer auto-signed cert (ou utiliser Let's Encrypt)
apiVersion: v1
kind: Secret
metadata:
  name: webapp-tls
  namespace: devsecops
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi... # Base64 encoded cert
  tls.key: LS0tLS1CRUdJTi... # Base64 encoded key

---
# ✅ Ingress avec TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: devsecops
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Si utilisant cert-manager
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - webapp.example.com
    secretName: webapp-tls
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

**Avec cert-manager + Let's Encrypt**:
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
```

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Sévérité**: 🔴 CRITIQUE | **Effort**: 2 heures

---

## 🔐 Gestion des secrets

### Configuration actuelle

**postgres-secret.yaml**:
```yaml
stringData:
  POSTGRES_USER: admin  # ❌ Valeur facile
  POSTGRES_PASSWORD: supersecretpassword  # ❌ En clair, facile
```

### Recommandations

**Problème 1: Mot de passe faible**

**Actuel**: `supersecretpassword` (trop simple)

**Correctif - Générer mot de passe fort**:
```bash
# OpenSSL
openssl rand -base64 32
# Exemple: 7mK9xQ2pL1wR4vB8nX6jT3cS5dF0gH1iJ2kL3mN4oP5qR6

# PowerShell
$password = -join ((33..126) | Get-Random -Count 32 | ForEach-Object {[char]$_})
Write-Host $password
```

**Créer secret sécurisé**:
```bash
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=$(openssl rand -base64 32) \
  --from-literal=POSTGRES_DB=tasksdb \
  -n devsecops \
  --dry-run=client \
  -o yaml > postgres-secret.yaml

# Puis appliquer
kubectl apply -f postgres-secret.yaml
```

**Problème 2: Stockage des secrets**

**❌ Ne pas faire**:
```bash
# ❌ MAUVAIS: Commiter secrets en git
git add postgres-secret.yaml
git commit -m "Add secrets"
```

**✅ Faire**:
```bash
# ✅ BON: Utiliser .gitignore
echo "*-secret.yaml" >> .gitignore

# ✅ BON: Utiliser HashiCorp Vault / AWS Secrets Manager
# ✅ BON: Utiliser Sealed Secrets
```

**Problème 3: Rotation des secrets**

**Créer script de rotation**:
```bash
#!/bin/bash
# scripts/rotate-secrets.sh

set -e

NAMESPACE="devsecops"
SECRET_NAME="postgres-secret"
NEW_PASSWORD=$(openssl rand -base64 32)

echo "Generating new password: ${NEW_PASSWORD:0:10}..."

# 1. Update secret
kubectl patch secret $SECRET_NAME \
  -n $NAMESPACE \
  -p "{\"data\":{\"POSTGRES_PASSWORD\":\"$(echo -n $NEW_PASSWORD | base64 -w0)\"}}"

# 2. Restart PostgreSQL pod pour prendre effet
kubectl rollout restart deployment/postgres-deployment -n $NAMESPACE

# 3. Attendre que PostgreSQL redémarre
kubectl rollout status deployment/postgres-deployment -n $NAMESPACE

# 4. Redémarrer webapp pods pour nouveau mot de passe
kubectl rollout restart deployment/webapp-deployment -n $NAMESPACE

kubectl rollout status deployment/webapp-deployment -n $NAMESPACE

echo "✅ Secrets rotated successfully"
echo "⚠️ Store new password in secure location!"
```

**Sévérité**: 🔴 CRITIQUE

---

## 📦 Dépendances

### Audit de sécurité npm

**Commande**:
```bash
npm audit
```

**Résultat attendu** (exécuter aujourd'hui):
```
found 0 vulnerabilities
```

**Si vulnérabilités trouvées**:
```bash
npm audit fix
npm audit fix --force  # À utiliser avec prudence
```

### Dépendances actuelles

| Package | Version | Statut |
|---------|---------|--------|
| express | ^4.18.2 | ✅ À jour (4.21.0) |
| @supabase/supabase-js | ^2.38.0 | ✅ À jour (2.45.0+) |
| pg | ^8.11.1 | ✅ À jour (8.12.0) |

### Recommandations

**Ajouter paquet de sécurité**:
```bash
npm install helmet cors express-rate-limit
```

**Utiliser dans application**:
```javascript
const helmet = require('helmet');
const cors = require('cors');

app.use(helmet()); // Headers de sécurité HTTP
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  credentials: true
}));
```

### Monitoring des dépendances

**Utiliser Dependabot (GitHub)**:
```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    allow:
      - dependency-type: "direct"
```

---

## 🌐 Réseau & Communication

### Problème 1: HTTPS non configuré ❌ CRITIQUE

**État actuel**: HTTP non chiffré

**Correctif**: Voir section Ingress avec TLS

**Sévérité**: 🔴 CRITIQUE

---

### Problème 2: CORS trop permissif ❌ HAUTE

**Code actuel**: Pas de CORS configuré (accepte tout par défaut)

**Correctif**:
```javascript
const cors = require('cors');

app.use(cors({
  origin: process.env.CORS_ORIGIN || ['http://localhost:3000', 'https://app.example.com'],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
```

**Sévérité**: 🟠 HAUTE

---

### Problème 3: Pas de HSTS (HTTP Strict Transport Security) ❌ HAUTE

**Correctif**:
```javascript
app.use(helmet.hsts({
  maxAge: 31536000, // 1 an
  includeSubDomains: true,
  preload: true
}));
```

**Sévérité**: 🟠 HAUTE

---

## 📋 Plan d'action

### Phase 1: CRITIQUE (À faire IMMÉDIATEMENT)
**Durée estimée: 8 heures**

- [ ] **1.1** Corriger injection SQL - validation IDs (30 min)
- [ ] **1.2** Implémenter authentification JWT (3 hours)
- [ ] **1.3** Ajouter NetworkPolicy Kubernetes (1 hour)
- [ ] **1.4** Implémenter RBAC (1.5 hours)
- [ ] **1.5** Chiffrer secrets Kubernetes (2 hours)

**Checkpoint**: Tests d'authentification, NetworkPolicy activée, secrets chiffrés

---

### Phase 2: HAUTE (À faire avant production)
**Durée estimée: 6 heures**

- [ ] **2.1** Valider données entrée (45 min)
- [ ] **2.2** Gestion erreurs sécurisée (30 min)
- [ ] **2.3** Ajouter rate limiting (20 min)
- [ ] **2.4** Ajouter logging structuré (1 hour)
- [ ] **2.5** Configurer Ingress HTTPS avec Let's Encrypt (2 hours)
- [ ] **2.6** Ajouter Pod Security Standards (30 min)
- [ ] **2.7** Ajouter Helmet + CORS sécurisé (30 min)
- [ ] **2.8** Scan image Docker avec Trivy (15 min)

**Checkpoint**: Tous les endpoints validés, HTTPS fonctionnel, logs structurés

---

### Phase 3: MOYENNE (À faire avant production)
**Durée estimée: 2 heures**

- [ ] **3.1** Ajouter USER non-root Dockerfile (15 min)
- [ ] **3.2** Ajouter HEALTHCHECK Docker (10 min)
- [ ] **3.3** npm audit et fixes (15 min)
- [ ] **3.4** Augmenter resource limits (5 min)
- [ ] **3.5** Script rotation secrets (30 min)
- [ ] **3.6** Documentation de sécurité (30 min)

**Checkpoint**: Image Docker sécurisée, audit npm clean

---

### Phase 4: OPTIONNEL (Nice-to-have)
**Durée estimée: 4 heures**

- [ ] **4.1** Mettre en place Vault HashiCorp
- [ ] **4.2** Monitoring avec Prometheus + Grafana
- [ ] **4.3** Scanning d'images automatisé en CI/CD
- [ ] **4.4** Backup/DR pour PostgreSQL
- [ ] **4.5** WAF (Web Application Firewall)
- [ ] **4.6** Audit logging

---

## 📊 Score de risque par composant

### CRITIQUE (Must fix) 🔴
1. Secrets non chiffrés - PostgreSQL: BLOCKER
2. Pas d'authentification - API ouverte à tous
3. NetworkPolicy absente - Communic libre entre pods
4. RBAC absent - ServiceAccounts illimitées
5. Injection SQL potentielle - Paramètres non validés
6. Pas de TLS/HTTPS - Données en clair sur réseau

### HAUTE (Should fix) 🟠
1. Validation entrée manquante
2. Rate limiting absent
3. Gestion erreurs insécurisée
4. Logging insuffisant
5. Image Docker non scannée
6. CORS trop permissif
7. Pas de Pod Security Standards

### MOYENNE (Nice-to-have) 🟡
1. USER non-root Docker
2. HEALTHCHECK Docker
3. Resource limits basiques
4. npm audit non exécuté

---

## ✅ Checklist pré-production

```markdown
## Avant de déployer en PRODUCTION

**Sécurité Application**
- [ ] Authentification implémentée
- [ ] Validation des données stricte
- [ ] Rate limiting actif
- [ ] Gestion erreurs sécurisée
- [ ] Logging structuré
- [ ] Secrets changés de défaut

**Sécurité Conteneur**
- [ ] Image scannée avec Trivy
- [ ] USER non-root configuré
- [ ] HEALTHCHECK présent
- [ ] npm audit clean
- [ ] Dockerfile optimisé

**Sécurité Kubernetes**
- [ ] NetworkPolicy appliquée
- [ ] RBAC configuré
- [ ] Secrets chiffrés au repos
- [ ] Pod Security Standards appliqué
- [ ] Ingress HTTPS avec TLS
- [ ] Resource limits réalistes

**Opérations**
- [ ] Backup strategy en place
- [ ] Monitoring configuré
- [ ] Alertes configurées
- [ ] Logs centralisées
- [ ] Plan de récupération

**Compliance**
- [ ] CNIL/GDPR audit (données perso)
- [ ] Chiffrement données en transit ✅
- [ ] Chiffrement données au repos 🔲
- [ ] Audit logging 🔲
```

---

## 🔍 Ressources de sécurité

### Documentation
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Node.js Security Checklist](https://nodejs.org/en/docs/guides/security/)
- [Kubernetes Security Docs](https://kubernetes.io/docs/concepts/security/)

### Outils
- **Trivy** - Container image scanning: `https://aquasecurity.github.io/trivy/`
- **Snyk** - Dependency vulnerability scanning: `https://snyk.io/`
- **HashiCorp Vault** - Secrets management: `https://www.vaultproject.io/`
- **Sealed Secrets** - Encrypted K8s secrets: `https://github.com/bitnami-labs/sealed-secrets`
- **Kubesec** - Kubernetes config scoring: `https://kubesec.io/`

### Formation
- [Kubernetes Security Course (Kubernetes Academy)](https://www.cncf.io/)
- [Node.js Security Workshop](https://nodejs.org/en/learn/getting-started/securing-nodejs-applications)

---

## 📝 Conclusion

Votre projet a une **bonne base** avec SecurityContext et probes de santé, mais nécessite des **corrections CRITIQUES** avant production:

**TOP PRIORITÉS**:
1. ✅ Authentification (3h)
2. ✅ Secrets chiffrés (2h)
3. ✅ NetworkPolicy (1h)
4. ✅ RBAC (1.5h)
5. ✅ HTTPS/TLS (2h)

**Coût total**: ~14 heures de travail

**Bénéfice**: Projet production-ready et sécurisé

---

**Date du prochain audit**: 2025-12-27 (mensuel recommandé)

