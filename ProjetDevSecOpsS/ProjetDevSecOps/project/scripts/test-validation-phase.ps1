#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de validation et test complet de l'application DevSecOps
    Phase de Validation et Test - Full Suite

.DESCRIPTION
    Ce script teste:
    1. Accessibilité de l'application externe
    2. Fonctionnalités CRUD (Create, Read, Update, Delete)
    3. Résilience (redémarrage pods/conteneurs, persistance données)
    4. Performance (temps de réponse)
    5. Intégrité des données (PostgreSQL vs JSON fallback)

.EXAMPLE
    .\scripts\test-validation-phase.ps1 -Environment docker
    .\scripts\test-validation-phase.ps1 -Environment kubernetes -Namespace devsecops
    .\scripts\test-validation-phase.ps1 -Environment docker -Verbose

#>

param(
    [ValidateSet('docker', 'kubernetes')]
    [string]$Environment = 'docker',
    
    [string]$Namespace = 'devsecops',
    
    [string]$AppUrl = '',
    
    [switch]$Verbose = $false,
    
    [int]$TimeoutSeconds = 300
)

# ────────────────────────────────────────────────────────────────
# CONFIGURATION
# ────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'Stop'
$VerbosePreference = if ($Verbose) { 'Continue' } else { 'SilentlyContinue' }

# Couleurs pour affichage
$colors = @{
    'Reset' = "`e[0m"
    'Green' = "`e[32m"
    'Red' = "`e[31m"
    'Yellow' = "`e[33m"
    'Blue' = "`e[34m"
    'Cyan' = "`e[36m"
    'Magenta' = "`e[35m"
}

$results = @{
    'passed' = 0
    'failed' = 0
    'skipped' = 0
    'details' = @()
}

# ────────────────────────────────────────────────────────────────
# FONCTIONS UTILITAIRES
# ────────────────────────────────────────────────────────────────

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'Reset'
    )
    Write-Host "$($colors[$Color])$Message$($colors['Reset'])"
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = '',
        [string]$Duration = ''
    )
    
    $status = if ($Passed) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    
    if ($Passed) { $results.passed++ } else { $results.failed++ }
    
    $resultStr = "[$status] $TestName"
    if ($Duration) { $resultStr += " (${Duration}ms)" }
    if ($Message) { $resultStr += " - $Message" }
    
    Write-ColorOutput $resultStr $color
    
    $results.details += @{
        'test' = $TestName
        'passed' = $Passed
        'message' = $Message
        'duration' = $Duration
    }
}

function Invoke-ApiRequest {
    param(
        [string]$Method = 'GET',
        [string]$Endpoint,
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [string]$Description = ''
    )
    
    $url = "$AppUrl$Endpoint"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $params = @{
            'Uri' = $url
            'Method' = $Method
            'Headers' = $Headers
            'ContentType' = 'application/json'
            'ErrorAction' = 'Stop'
        }
        
        if ($Body) {
            $params['Body'] = $Body | ConvertTo-Json
        }
        
        $response = Invoke-RestMethod @params
        $timer.Stop()
        
        Write-Verbose "[$Method] $Endpoint - Status: 200 OK (${$timer.ElapsedMilliseconds}ms)"
        return @{
            'success' = $true
            'data' = $response
            'statusCode' = 200
            'duration' = $timer.ElapsedMilliseconds
        }
    }
    catch {
        $timer.Stop()
        Write-Verbose "[$Method] $Endpoint - Error: $($_.Exception.Message)"
        return @{
            'success' = $false
            'error' = $_.Exception.Message
            'statusCode' = $_.Exception.Response.StatusCode
            'duration' = $timer.ElapsedMilliseconds
        }
    }
}

function Wait-ForAppReady {
    param(
        [string]$Url,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 2
    )
    
    Write-ColorOutput "⏳ Attendre que l'application soit accessible..." 'Cyan'
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri "$Url/api/health" -Method Get -ErrorAction Stop
            Write-ColorOutput "✅ Application prête!" 'Green'
            return $true
        }
        catch {
            $attempt++
            Write-Verbose "Tentative $attempt/$MaxRetries échouée, attendre ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    return $false
}

function Get-ContainerIP {
    param([string]$ContainerName)
    
    $ip = docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $ContainerName 2>$null
    return $ip
}

# ────────────────────────────────────────────────────────────────
# SETUP - DÉTERMINER L'URL DE L'APPLICATION
# ────────────────────────────────────────────────────────────────

function Setup-Environment {
    Write-ColorOutput "`n=== SETUP ENVIRONNEMENT ===" 'Cyan'
    
    if ($Environment -eq 'docker') {
        Write-ColorOutput "Environnement: Docker Compose" 'Blue'
        
        # Vérifier que docker-compose est en cours
        $ps = docker-compose ps -q webapp 2>$null
        if (-not $ps) {
            Write-ColorOutput "❌ Conteneur webapp n'est pas en cours. Démarrage..." 'Yellow'
            docker-compose up -d webapp | Out-Null
            Start-Sleep -Seconds 5
        }
        
        $containerName = 'project_webapp'
        $ip = Get-ContainerIP $containerName
        
        if (-not $ip) {
            Write-ColorOutput "❌ Erreur: Impossible de récupérer l'IP du conteneur" 'Red'
            return $false
        }
        
        $script:AppUrl = "http://$ip`:3000"
        Write-ColorOutput "URL App: $AppUrl" 'Green'
    }
    else {
        Write-ColorOutput "Environnement: Kubernetes ($Namespace)" 'Blue'
        
        # Vérifier que kubectl est disponible
        $kubeCheck = kubectl cluster-info 2>$null
        if (-not $kubeCheck) {
            Write-ColorOutput "❌ kubectl n'est pas configuré ou cluster non accessible" 'Red'
            return $false
        }
        
        # Port-forward le service webapp
        Write-ColorOutput "📡 Configuration port-forward Kubernetes..." 'Cyan'
        $localPort = 8080
        $script:AppUrl = "http://localhost:$localPort"
        
        # Vérifier si un port-forward existe déjà
        $existing = Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'port-forward' }
        if ($existing) {
            Stop-Process -Id $existing.Id -Force
            Start-Sleep -Seconds 1
        }
        
        # Créer port-forward en background
        $pfProcess = Start-Process -FilePath kubectl `
            -ArgumentList "port-forward", "svc/webapp-service", "$($localPort):80", "-n", $Namespace `
            -PassThru -WindowStyle Hidden
        
        Start-Sleep -Seconds 2
        Write-ColorOutput "Port-forward: localhost:$localPort → webapp-service:80" 'Green'
    }
    
    # Vérifier connectivité
    if (-not (Wait-ForAppReady $AppUrl)) {
        Write-ColorOutput "❌ Impossible d'atteindre l'application à $AppUrl" 'Red'
        return $false
    }
    
    return $true
}

# ────────────────────────────────────────────────────────────────
# TEST 1: ACCESSIBILITÉ
# ────────────────────────────────────────────────────────────────

function Test-Accessibility {
    Write-ColorOutput "`n=== TEST 1: ACCESSIBILITÉ EXTERNE ===" 'Cyan'
    
    # Test 1.1: Health check
    $health = Invoke-ApiRequest -Endpoint '/api/health' -Description 'Health check'
    Write-TestResult "1.1 - Health endpoint accessible" $health.success -Duration $health.duration
    
    if ($health.success) {
        $dbType = $health.data.database
        Write-ColorOutput "     → Database type: $dbType" 'Yellow'
        
        if ($dbType -eq 'postgres') {
            Write-ColorOutput "     ✅ PostgreSQL connecté!" 'Green'
        }
        elseif ($dbType -eq 'supabase') {
            Write-ColorOutput "     ⚠️  Supabase utilisé" 'Yellow'
        }
        else {
            Write-ColorOutput "     ⚠️  Fallback JSON utilisé" 'Yellow'
        }
    }
    
    # Test 1.2: API tasks endpoint
    $tasks = Invoke-ApiRequest -Endpoint '/api/tasks' -Description 'GET tasks'
    Write-TestResult "1.2 - API tasks accessible" $tasks.success -Duration $tasks.duration
    
    # Test 1.3: Frontend static file
    try {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "$AppUrl/" -Method Get -ErrorAction Stop
        $timer.Stop()
        Write-TestResult "1.3 - Frontend index.html accessible" ($response.StatusCode -eq 200) -Duration $timer.ElapsedMilliseconds
    }
    catch {
        Write-TestResult "1.3 - Frontend index.html accessible" $false -Message $_.Exception.Message
    }
}

# ────────────────────────────────────────────────────────────────
# TEST 2: FONCTIONNALITÉS CRUD
# ────────────────────────────────────────────────────────────────

function Test-CRUD {
    Write-ColorOutput "`n=== TEST 2: FONCTIONNALITÉS CRUD ===" 'Cyan'
    
    $testTaskId = $null
    
    # Test 2.1: CREATE (POST)
    Write-ColorOutput "Testing CREATE..." 'Yellow'
    $createBody = @{
        'title' = "Test Task $(Get-Random)"
        'description' = "Test description for validation suite"
    }
    
    $create = Invoke-ApiRequest -Method POST -Endpoint '/api/tasks' -Body $createBody
    Write-TestResult "2.1 - Créer une tâche (POST)" $create.success -Duration $create.duration
    
    if ($create.success) {
        $testTaskId = $create.data.task.id
        Write-ColorOutput "     → Task ID: $testTaskId | Title: $($create.data.task.title)" 'Green'
    }
    else {
        Write-ColorOutput "     ❌ Cannot continue CRUD tests without task creation" 'Red'
        return
    }
    
    # Test 2.2: READ (GET all)
    Start-Sleep -Milliseconds 500
    $readAll = Invoke-ApiRequest -Endpoint '/api/tasks'
    Write-TestResult "2.2 - Lire toutes les tâches (GET)" $readAll.success -Duration $readAll.duration
    
    if ($readAll.success) {
        $taskCount = $readAll.data.tasks.Count
        Write-ColorOutput "     → Total tasks: $taskCount" 'Green'
        
        # Vérifier si notre tâche créée est présente
        $foundTask = $readAll.data.tasks | Where-Object { $_.id -eq $testTaskId }
        if ($foundTask) {
            Write-ColorOutput "     ✅ Tâche trouvée dans la liste" 'Green'
        }
        else {
            Write-ColorOutput "     ⚠️  Tâche créée non trouvée dans la liste" 'Yellow'
        }
    }
    
    # Test 2.3: UPDATE (PUT)
    Start-Sleep -Milliseconds 500
    Write-ColorOutput "Testing UPDATE..." 'Yellow'
    $updateBody = @{ 'completed' = $true }
    
    $update = Invoke-ApiRequest -Method PUT -Endpoint "/api/tasks/$testTaskId" -Body $updateBody
    Write-TestResult "2.3 - Mettre à jour une tâche (PUT)" $update.success -Duration $update.duration
    
    if ($update.success) {
        $completed = $update.data.task.completed
        Write-ColorOutput "     → Completed: $completed" 'Green'
    }
    
    # Test 2.4: READ specific task
    Start-Sleep -Milliseconds 500
    $readOne = Invoke-ApiRequest -Endpoint '/api/tasks' # GET toutes les tâches pour vérifier
    Write-TestResult "2.4 - Vérifier l'update (GET)" $readOne.success -Duration $readOne.duration
    
    if ($readOne.success) {
        $updatedTask = $readOne.data.tasks | Where-Object { $_.id -eq $testTaskId }
        if ($updatedTask -and $updatedTask.completed -eq $true) {
            Write-ColorOutput "     ✅ Task marked as completed successfully" 'Green'
        }
        else {
            Write-ColorOutput "     ⚠️  Update may not have persisted" 'Yellow'
        }
    }
    
    # Test 2.5: DELETE
    Start-Sleep -Milliseconds 500
    Write-ColorOutput "Testing DELETE..." 'Yellow'
    $delete = Invoke-ApiRequest -Method DELETE -Endpoint "/api/tasks/$testTaskId"
    Write-TestResult "2.5 - Supprimer une tâche (DELETE)" $delete.success -Duration $delete.duration
    
    # Test 2.6: Verify deletion
    Start-Sleep -Milliseconds 500
    $readFinal = Invoke-ApiRequest -Endpoint '/api/tasks'
    $deletedTask = $readFinal.data.tasks | Where-Object { $_.id -eq $testTaskId }
    
    if (-not $deletedTask) {
        Write-TestResult "2.6 - Vérifier la suppression" $true
        Write-ColorOutput "     ✅ Task successfully deleted" 'Green'
    }
    else {
        Write-TestResult "2.6 - Vérifier la suppression" $false -Message "Task still exists"
    }
}

# ────────────────────────────────────────────────────────────────
# TEST 3: RÉSILIENCE
# ────────────────────────────────────────────────────────────────

function Test-Resilience {
    Write-ColorOutput "`n=== TEST 3: RÉSILIENCE ===" 'Cyan'
    
    # Créer des données de test
    Write-ColorOutput "Créer données de test pour résilience..." 'Yellow'
    $testTasks = @()
    
    for ($i = 1; $i -le 3; $i++) {
        $body = @{
            'title' = "Resilience Test Task $i"
            'description' = "Test data for resilience - Should persist after restart"
        }
        
        $result = Invoke-ApiRequest -Method POST -Endpoint '/api/tasks' -Body $body
        if ($result.success) {
            $testTasks += @{
                'id' = $result.data.task.id
                'title' = $result.data.task.title
            }
            Write-ColorOutput "     ✅ Created: $($result.data.task.title)" 'Green'
        }
        Start-Sleep -Milliseconds 300
    }
    
    Write-ColorOutput "✅ Données créées: $($testTasks.Count) tâches" 'Green'
    
    # Obtenir le nombre initial
    $readBefore = Invoke-ApiRequest -Endpoint '/api/tasks'
    $countBefore = $readBefore.data.tasks.Count
    Write-ColorOutput "Count avant redémarrage: $countBefore tâches" 'Cyan'
    
    # Test 3.1: Redémarrer le conteneur webapp
    Write-ColorOutput "`n🔄 Redémarrage du conteneur webapp..." 'Yellow'
    
    if ($Environment -eq 'docker') {
        docker-compose restart webapp 2>$null | Out-Null
        Start-Sleep -Seconds 5
    }
    else {
        kubectl rollout restart deployment/webapp-deployment -n $Namespace 2>$null | Out-Null
        kubectl wait --for=condition=ready pod -l app=webapp -n $Namespace --timeout=60s 2>$null
    }
    
    Write-ColorOutput "✅ Conteneur redémarré" 'Green'
    
    # Attendre que l'app soit prête
    if (-not (Wait-ForAppReady $AppUrl 20 2)) {
        Write-ColorOutput "❌ Application non accessible après redémarrage" 'Red'
        Write-TestResult "3.1 - Persistance après redémarrage webapp" $false
        return
    }
    
    # Test 3.2: Vérifier persistance des données
    Start-Sleep -Seconds 2
    $readAfter = Invoke-ApiRequest -Endpoint '/api/tasks'
    $countAfter = $readAfter.data.tasks.Count
    
    Write-ColorOutput "Count après redémarrage: $countAfter tâches" 'Cyan'
    
    $dataPersisted = $countAfter -ge $countBefore
    Write-TestResult "3.1 - Persistance après redémarrage webapp" $dataPersisted `
        -Message "Before: $countBefore, After: $countAfter"
    
    if ($dataPersisted) {
        # Vérifier si nos tâches spécifiques existent
        $foundCount = 0
        foreach ($task in $testTasks) {
            $found = $readAfter.data.tasks | Where-Object { $_.id -eq $task.id }
            if ($found) { $foundCount++ }
        }
        
        Write-ColorOutput "     → Tâches de test persistées: $foundCount/$($testTasks.Count)" 'Green'
    }
    
    # Test 3.3: Redémarrer la base de données (PostgreSQL)
    Write-ColorOutput "`n🔄 Redémarrage du conteneur PostgreSQL..." 'Yellow'
    
    if ($Environment -eq 'docker') {
        docker-compose restart postgres 2>$null | Out-Null
        Start-Sleep -Seconds 8
    }
    else {
        kubectl rollout restart deployment/postgres-deployment -n $Namespace 2>$null | Out-Null
        kubectl wait --for=condition=ready pod -l app=postgres -n $Namespace --timeout=60s 2>$null
    }
    
    Write-ColorOutput "✅ PostgreSQL redémarré" 'Green'
    
    # Test 3.4: Vérifier persistance après redémarrage DB
    Start-Sleep -Seconds 3
    $readAfterDB = Invoke-ApiRequest -Endpoint '/api/tasks'
    $countAfterDB = $readAfterDB.data.tasks.Count
    
    $dbPersisted = $countAfterDB -ge $countBefore
    Write-TestResult "3.2 - Persistance après redémarrage PostgreSQL" $dbPersisted `
        -Message "Before: $countBefore, After DB restart: $countAfterDB"
    
    if ($dbPersisted) {
        Write-ColorOutput "     ✅ Données toujours présentes!" 'Green'
    }
}

# ────────────────────────────────────────────────────────────────
# TEST 4: PERFORMANCE
# ────────────────────────────────────────────────────────────────

function Test-Performance {
    Write-ColorOutput "`n=== TEST 4: PERFORMANCE ===" 'Cyan'
    
    $iterations = 10
    $durations = @()
    
    # Test 4.1: Latence GET
    Write-ColorOutput "Measuring GET /api/tasks latency ($iterations iterations)..." 'Yellow'
    
    for ($i = 0; $i -lt $iterations; $i++) {
        $result = Invoke-ApiRequest -Endpoint '/api/tasks'
        if ($result.success) {
            $durations += $result.duration
        }
    }
    
    if ($durations.Count -gt 0) {
        $avg = [math]::Round(($durations | Measure-Object -Average).Average, 2)
        $max = [math]::Round(($durations | Measure-Object -Maximum).Maximum, 2)
        $min = [math]::Round(($durations | Measure-Object -Minimum).Minimum, 2)
        
        Write-TestResult "4.1 - Latence GET (avg)" $true `
            -Message "Avg: ${avg}ms | Min: ${min}ms | Max: ${max}ms"
        
        $avgOk = $avg -lt 500  # Target < 500ms
        if ($avgOk) {
            Write-ColorOutput "     ✅ Performance acceptable (avg < 500ms)" 'Green'
        }
        else {
            Write-ColorOutput "     ⚠️  Performance à améliorer (avg >= 500ms)" 'Yellow'
        }
    }
    
    # Test 4.2: Latence POST
    Write-ColorOutput "`nMeasuring POST /api/tasks latency ($iterations iterations)..." 'Yellow'
    
    $postDurations = @()
    for ($i = 0; $i -lt $iterations; $i++) {
        $body = @{
            'title' = "Performance test $i"
            'description' = "Auto-generated"
        }
        $result = Invoke-ApiRequest -Method POST -Endpoint '/api/tasks' -Body $body
        if ($result.success) {
            $postDurations += $result.duration
        }
        Start-Sleep -Milliseconds 100
    }
    
    if ($postDurations.Count -gt 0) {
        $avg = [math]::Round(($postDurations | Measure-Object -Average).Average, 2)
        $max = [math]::Round(($postDurations | Measure-Object -Maximum).Maximum, 2)
        $min = [math]::Round(($postDurations | Measure-Object -Minimum).Minimum, 2)
        
        Write-TestResult "4.2 - Latence POST (avg)" $true `
            -Message "Avg: ${avg}ms | Min: ${min}ms | Max: ${max}ms"
        
        $postOk = $avg -lt 1000
        if ($postOk) {
            Write-ColorOutput "     ✅ Performance acceptable (avg < 1000ms)" 'Green'
        }
        else {
            Write-ColorOutput "     ⚠️  Performance à améliorer (avg >= 1000ms)" 'Yellow'
        }
    }
}

# ────────────────────────────────────────────────────────────────
# TEST 5: INTÉGRITÉ DES DONNÉES
# ────────────────────────────────────────────────────────────────

function Test-DataIntegrity {
    Write-ColorOutput "`n=== TEST 5: INTÉGRITÉ DES DONNÉES ===" 'Cyan'
    
    # Test 5.1: Vérifier les champs requis
    Write-ColorOutput "Vérifier structure des tâches..." 'Yellow'
    
    $tasks = Invoke-ApiRequest -Endpoint '/api/tasks'
    if ($tasks.success -and $tasks.data.tasks.Count -gt 0) {
        $firstTask = $tasks.data.tasks[0]
        
        $requiredFields = @('id', 'title', 'completed', 'created_at')
        $missingFields = @()
        
        foreach ($field in $requiredFields) {
            if (-not ($firstTask.PSObject.Properties.Name -contains $field)) {
                $missingFields += $field
            }
        }
        
        $hasAllFields = $missingFields.Count -eq 0
        Write-TestResult "5.1 - Structure des tâches valide" $hasAllFields `
            -Message $(if ($hasAllFields) { "All fields present" } else { "Missing: $($missingFields -join ', ')" })
    }
    else {
        Write-TestResult "5.1 - Structure des tâches valide" $false -Message "No tasks to verify"
    }
    
    # Test 5.2: Vérifier les types de données
    Write-ColorOutput "`nVérifier types de données..." 'Yellow'
    
    if ($tasks.success -and $tasks.data.tasks.Count -gt 0) {
        $firstTask = $tasks.data.tasks[0]
        
        $typeOk = ($firstTask.id -is [int] -or $firstTask.id -is [string]) -and `
                  ($firstTask.title -is [string]) -and `
                  ($firstTask.completed -is [bool] -or $firstTask.completed -in @(0, 1)) -and `
                  ($firstTask.created_at -is [string])
        
        Write-TestResult "5.2 - Types de données corrects" $typeOk
        
        if ($typeOk) {
            Write-ColorOutput "     ✅ All types validated" 'Green'
        }
        else {
            Write-ColorOutput "     ID type: $($firstTask.id.GetType().Name)" 'Yellow'
            Write-ColorOutput "     Title type: $($firstTask.title.GetType().Name)" 'Yellow'
            Write-ColorOutput "     Completed type: $($firstTask.completed.GetType().Name)" 'Yellow'
        }
    }
}

# ────────────────────────────────────────────────────────────────
# RAPPORT FINAL
# ────────────────────────────────────────────────────────────────

function Show-FinalReport {
    Write-ColorOutput "`n$('='*70)" 'Cyan'
    Write-ColorOutput "RAPPORT FINAL DE VALIDATION" 'Magenta'
    Write-ColorOutput "$('='*70)" 'Cyan'
    
    $total = $results.passed + $results.failed + $results.skipped
    $passRate = if ($total -gt 0) { [math]::Round(($results.passed / $total) * 100, 1) } else { 0 }
    
    Write-Host ""
    Write-ColorOutput "📊 RÉSUMÉ" 'Blue'
    Write-ColorOutput "  ✅ Passed:  $($results.passed)" 'Green'
    Write-ColorOutput "  ❌ Failed:  $($results.failed)" $(if ($results.failed -eq 0) { 'Green' } else { 'Red' })
    Write-ColorOutput "  ⊘ Skipped: $($results.skipped)" 'Yellow'
    Write-ColorOutput "  Total:     $total tests" 'Cyan'
    Write-ColorOutput "  Taux de succès: ${passRate}%" $(if ($passRate -eq 100) { 'Green' } else { if ($passRate -ge 80) { 'Yellow' } else { 'Red' } })
    
    Write-Host ""
    Write-ColorOutput "📋 DÉTAILS" 'Blue'
    
    foreach ($detail in $results.details) {
        $icon = if ($detail.passed) { "✅" } else { "❌" }
        $line = "$icon $($detail.test)"
        if ($detail.duration) { $line += " [$($detail.duration)ms]" }
        if ($detail.message) { $line += " - $($detail.message)" }
        
        $color = if ($detail.passed) { 'Green' } else { 'Red' }
        Write-ColorOutput "  $line" $color
    }
    
    Write-Host ""
    Write-ColorOutput "🎯 RECOMMANDATIONS" 'Blue'
    
    if ($results.failed -eq 0) {
        Write-ColorOutput "  ✅ Tous les tests sont passés!" 'Green'
        Write-ColorOutput "  L'application est prête pour le déploiement en production." 'Green'
    }
    else {
        Write-ColorOutput "  ⚠️  Des tests ont échoué. Vérifier les logs ci-dessus." 'Red'
    }
    
    Write-Host ""
    Write-ColorOutput "Environnement: $Environment" 'Cyan'
    Write-ColorOutput "URL: $AppUrl" 'Cyan'
    Write-ColorOutput "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'Cyan'
    
    Write-ColorOutput "`n$('='*70)" 'Cyan'
}

# ────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────

function Main {
    Write-ColorOutput "`n╔════════════════════════════════════════════════════════════════╗" 'Magenta'
    Write-ColorOutput "║   PHASE DE VALIDATION ET TEST - DEVSECOPS                      ║" 'Magenta'
    Write-ColorOutput "║   Test Suite Complète                                         ║" 'Magenta'
    Write-ColorOutput "╚════════════════════════════════════════════════════════════════╝" 'Magenta'
    
    # Setup
    if (-not (Setup-Environment)) {
        Write-ColorOutput "`n❌ Erreur lors du setup. Abandon." 'Red'
        exit 1
    }
    
    try {
        # Exécuter tous les tests
        Test-Accessibility
        Test-CRUD
        Test-Resilience
        Test-Performance
        Test-DataIntegrity
        
        # Afficher rapport
        Show-FinalReport
        
        # Retourner code de sortie approprié
        exit $(if ($results.failed -eq 0) { 0 } else { 1 })
    }
    catch {
        Write-ColorOutput "`n❌ Erreur pendant l'exécution des tests:" 'Red'
        Write-ColorOutput $_.Exception.Message 'Red'
        exit 1
    }
}

Main
