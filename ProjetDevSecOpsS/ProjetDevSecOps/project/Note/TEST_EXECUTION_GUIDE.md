# 📖 GUIDE DE REPRODUCTION DES TESTS

Guide complet pour reproduire la phase de validation et test sur votre propre système.

---

## 🚀 Démarrage rapide

### 1. Prérequis

```powershell
# Vérifier que Docker est installé et en cours d'exécution
docker --version
docker-compose --version

# Vérifier que vous êtes dans le bon répertoire
cd C:\Users\mathb\Desktop\ProjetDevSecOps\project
```

### 2. Construire l'image Docker

```powershell
# Construire l'image complète avec curl pour healthcheck
docker build --no-cache -t kubernetes-webapp:latest .

# Vérifier que l'image est créée
docker images | grep kubernetes-webapp
# Output: kubernetes-webapp    latest    96115b2b58ed   ...
```

### 3. Démarrer les conteneurs

```powershell
# Démarrer docker-compose
docker-compose up -d

# Attendre que les conteneurs soient healthy
Start-Sleep -Seconds 10

# Vérifier le statut
docker-compose ps
```

**Résultat attendu**:
```
NAME               IMAGE              STATUS
project_postgres   postgres:15-alpine Up ... (healthy)
project_webapp     kubernetes-webapp  Up ... (healthy)
```

### 4. Exécuter les tests

```powershell
# Lancer le script de validation complet
.\scripts\validate-complete.ps1

# Temps d'exécution estimé: 60-90 secondes
```

---

## 🧪 Tests manuels détaillés

### Test 1: Vérifier l'accessibilité

```powershell
# 1. Vérifier que les conteneurs tournent
docker-compose ps

# 2. Tester l'endpoint health
Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get | ConvertTo-Json

# Résultat attendu:
# {
#   "status": "healthy",
#   "timestamp": "2025-11-27T13:34:56.789Z",
#   "database": "postgres"
# }

# 3. Tester l'accès au frontend
Invoke-WebRequest -Uri "http://localhost:3000/" | Select-Object StatusCode, StatusDescription
# Expected: StatusCode: 200, StatusDescription: OK
```

### Test 2: Test CREATE (POST)

```powershell
# Créer une nouvelle tâche
$body = '{"title":"Mon première tâche","description":"Test de création"}'

$response = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" `
    -Method Post `
    -Body $body `
    -ContentType "application/json"

$response | ConvertTo-Json

# Résultat attendu:
# {
#   "task": {
#     "id": 1,
#     "title": "Mon première tâche",
#     "description": "Test de création",
#     "completed": false,
#     "created_at": "2025-11-27T13:35:00.123Z"
#   }
# }

# Sauvegarder l'ID pour les tests suivants
$taskId = $response.task.id
Write-Host "Task ID created: $taskId"
```

### Test 3: Test READ (GET)

```powershell
# Lire toutes les tâches
$tasks = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get

$tasks | ConvertTo-Json

# Ou afficher uniquement le nombre
Write-Host "Total tasks: $($tasks.tasks.Count)"

# Vérifier que notre tâche est présente
$tasks.tasks | Where-Object { $_.id -eq $taskId } | ConvertTo-Json
```

### Test 4: Test UPDATE (PUT)

```powershell
# Modifier une tâche
$updateBody = '{"completed":true}'

$updated = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks/$taskId" `
    -Method Put `
    -Body $updateBody `
    -ContentType "application/json"

$updated | ConvertTo-Json

# Résultat attendu: completed = true
```

### Test 5: Test DELETE (DELETE)

```powershell
# Supprimer la tâche
$deleted = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks/$taskId" `
    -Method Delete

$deleted | ConvertTo-Json

# Résultat attendu: message = "Task deleted successfully"

# Vérifier que la tâche est supprimée
$afterDelete = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
$found = $afterDelete.tasks | Where-Object { $_.id -eq $taskId }

if (-not $found) {
    Write-Host "SUCCESS: Task successfully deleted" -ForegroundColor Green
}
else {
    Write-Host "ERROR: Task still exists" -ForegroundColor Red
}
```

---

## 🔄 Tests de résilience

### Test 6: Redémarrage de l'application

```powershell
# 1. Créer 3 tâches de test
for ($i = 1; $i -le 3; $i++) {
    $body = '{"title":"Resilience Test ' + $i + '","description":"Test data"}'
    Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" `
        -Method Post `
        -Body $body `
        -ContentType "application/json" | Out-Null
    Start-Sleep -Milliseconds 200
}

# 2. Compter les tâches avant redémarrage
$before = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
$countBefore = $before.tasks.Count
Write-Host "Tasks before restart: $countBefore"

# 3. Redémarrer le conteneur webapp
Write-Host "Restarting webapp container..."
docker-compose restart webapp

# 4. Attendre que l'app redémarre
Start-Sleep -Seconds 5

# 5. Attendre qu'elle soit prête
$ready = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get
        $ready = $true
        Write-Host "Application is ready"
        break
    }
    catch {
        Write-Host "Waiting... ($i/10)"
        Start-Sleep -Seconds 1
    }
}

# 6. Compter les tâches après redémarrage
Start-Sleep -Seconds 1
$after = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
$countAfter = $after.tasks.Count
Write-Host "Tasks after restart: $countAfter"

# 7. Vérifier la persistance
if ($countAfter -ge $countBefore) {
    Write-Host "SUCCESS: Data persisted after restart" -ForegroundColor Green
}
else {
    Write-Host "ERROR: Data lost" -ForegroundColor Red
}
```

### Test 7: Redémarrage de la base de données

```powershell
# 1. Noter le count actuel
$before = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
$countBefore = $before.tasks.Count
Write-Host "Tasks before DB restart: $countBefore"

# 2. Redémarrer PostgreSQL
Write-Host "Restarting PostgreSQL..."
docker-compose restart postgres

# 3. Attendre que PostgreSQL redémarre et que l'app se reconnecte
Start-Sleep -Seconds 8

# 4. Attendre la reconnexion
for ($i = 1; $i -le 15; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get
        if ($health.database -eq "postgres") {
            Write-Host "Reconnected to PostgreSQL"
            break
        }
        Start-Sleep -Seconds 1
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

# 5. Compter les tâches
Start-Sleep -Seconds 2
$after = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
$countAfter = $after.tasks.Count
Write-Host "Tasks after DB restart: $countAfter"

# 6. Vérifier la persistance
if ($countAfter -ge $countBefore) {
    Write-Host "SUCCESS: Data persisted after DB restart" -ForegroundColor Green
}
else {
    Write-Host "WARNING: Data temporarily lost, checking again..."
    Start-Sleep -Seconds 3
    $final = Invoke-RestMethod -Uri "http://localhost:3000/api/tasks" -Method Get
    $countFinal = $final.tasks.Count
    Write-Host "Tasks after second check: $countFinal"
}
```

---

## 📊 Tests de performance

### Test 8: Mesurer les latences

```powershell
function Test-ApiLatency {
    param(
        [string]$Method = "GET",
        [string]$Endpoint = "/api/tasks",
        [int]$Iterations = 10
    )
    
    $durations = @()
    
    Write-Host "Testing $Method $Endpoint ($Iterations iterations)..." -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Iterations; $i++) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:3000$Endpoint" `
                -Method $Method `
                -TimeoutSec 10 `
                -ErrorAction Stop
            
            $timer.Stop()
            $durations += $timer.ElapsedMilliseconds
            Write-Host "  Iteration $($i+1): $($timer.ElapsedMilliseconds)ms"
        }
        catch {
            Write-Host "  Iteration $($i+1): FAILED" -ForegroundColor Red
        }
    }
    
    if ($durations.Count -gt 0) {
        $avg = ($durations | Measure-Object -Average).Average
        $min = ($durations | Measure-Object -Minimum).Minimum
        $max = ($durations | Measure-Object -Maximum).Maximum
        $std = ($durations | Measure-Object -StandardDeviation).StandardDeviation
        
        Write-Host ""
        Write-Host "Results for $Method $Endpoint"
        Write-Host "  Min: $min ms"
        Write-Host "  Max: $max ms"
        Write-Host "  Avg: $([Math]::Round($avg, 2)) ms"
        Write-Host "  StdDev: $([Math]::Round($std, 2)) ms"
        Write-Host ""
    }
}

# Exécuter les tests de performance
Test-ApiLatency -Method GET -Endpoint "/api/tasks" -Iterations 10
Test-ApiLatency -Method GET -Endpoint "/api/health" -Iterations 10
```

---

## 🔍 Diagnostique et dépannage

### Vérifier les logs

```powershell
# Logs du conteneur webapp
docker-compose logs webapp --tail=50

# Logs du conteneur postgres
docker-compose logs postgres --tail=50

# Logs en temps réel
docker-compose logs -f

# Logs avec filtre
docker-compose logs webapp | Select-String "Connected\|Error\|Failed"
```

### Inspecter les conteneurs

```powershell
# Information détaillée du conteneur
docker inspect project_webapp

# Afficher les variables d'environnement
docker inspect project_webapp | ConvertFrom-Json | Select-Object -ExpandProperty Config | Select-Object -ExpandProperty Env

# Vérifier la connectivité réseau
docker exec project_webapp ping postgres

# Tester la connexion PostgreSQL
docker exec project_postgres psql -U admin -d tasksdb -c "SELECT NOW();"
```

### Vérifier la base de données

```powershell
# Connecter directement à PostgreSQL
docker exec -it project_postgres psql -U admin -d tasksdb

# Commandes SQL utiles
# \dt                    - Lister les tables
# \d tasks               - Description de la table tasks
# SELECT * FROM tasks;   - Afficher les tâches
# SELECT COUNT(*) FROM tasks;  - Compter les tâches
# \q                     - Quitter
```

### Nettoyer et recommencer

```powershell
# Arrêter les conteneurs
docker-compose down

# Supprimer les volumes
docker-compose down -v

# Supprimer les images
docker rmi kubernetes-webapp:latest

# Nettoyer tout
docker system prune -a

# Recommencer depuis le début
docker build --no-cache -t kubernetes-webapp:latest .
docker-compose up -d
```

---

## 🎯 Vérifications finales

### Avant de déployer en production

```powershell
# 1. Tous les tests passent
.\scripts\validate-complete.ps1

# 2. Image Docker sécurisée
docker image inspect kubernetes-webapp:latest | ConvertFrom-Json | Select-Object RepoTags, Size, Config

# 3. Secrets bien configurés
docker-compose config | Select-String "POSTGRES_PASSWORD\|SUPABASE"

# 4. Healthchecks actifs
docker-compose ps | Select-String "healthy"

# 5. Pas d'erreurs dans les logs
docker-compose logs | Select-String "ERROR\|CRITICAL\|FATAL" -NotMatch

# 6. Performance acceptable
.\scripts\validate-complete.ps1 | Select-String "PASS"
```

---

## 📝 Template de rapport

Utilisez ce template pour documenter vos tests:

```markdown
# Test Report

Date: [DATE]
Tester: [NAME]
Environment: [docker/kubernetes]

## Test Results

| Test | Status | Duration | Notes |
|------|--------|----------|-------|
| Accessibility | PASS/FAIL | Xms | - |
| CRUD Create | PASS/FAIL | Xms | - |
| CRUD Read | PASS/FAIL | Xms | - |
| CRUD Update | PASS/FAIL | Xms | - |
| CRUD Delete | PASS/FAIL | Xms | - |
| Resilience (webapp) | PASS/FAIL | Xs | - |
| Resilience (db) | PASS/FAIL | Xs | - |
| Performance | PASS/FAIL | - | Avg latency: Xms |

## Issues Found

- [Issue 1]
- [Issue 2]

## Recommendations

- [Rec 1]
- [Rec 2]

## Sign-off

Approved: YES/NO
Approved by: [NAME]
Date: [DATE]
```

---

## 🚀 Prochaines étapes

Une fois tous les tests réussis:

1. **Déployer en Kubernetes**
   ```powershell
   .\scripts\deploy-k8s.ps1 -Namespace devsecops -WaitForRollout
   ```

2. **Vérifier le déploiement Kubernetes**
   ```bash
   kubectl get all -n devsecops
   kubectl get pods -n devsecops
   kubectl logs -f deployment/webapp-deployment -n devsecops
   ```

3. **Exécuter les tests sur Kubernetes**
   ```powershell
   .\scripts\verify-k8s-deployment.ps1 -Namespace devsecops
   ```

4. **Implémenter la sécurité**
   - Voir SECURITY_ANALYSIS.md
   - Implémenter les corrections CRITIQUES
   - Valider les configurations

5. **Mettre en place le monitoring**
   - Prometheus metrics
   - Centralized logging
   - Alerting

---

Pour toute question ou problème, consultez:
- VALIDATION_TEST_REPORT.md - Résultats détaillés
- SECURITY_ANALYSIS.md - Recommandations de sécurité
- DEPLOYMENT_GUIDE_KUBERNETES.md - Guide de déploiement

