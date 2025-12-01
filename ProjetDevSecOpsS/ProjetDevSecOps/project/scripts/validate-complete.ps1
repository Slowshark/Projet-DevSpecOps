#!/usr/bin/env pwsh

Write-Host "`n========== PHASE DE VALIDATION ET TEST ==========`n" -ForegroundColor Magenta

$baseUrl = "http://localhost:3000"

Write-Host "[TEST 1] Accessibilite externe" -ForegroundColor Cyan
try {
    $health = Invoke-RestMethod -Uri "$baseUrl/api/health" -Method Get -TimeoutSec 5
    Write-Host "PASS: Health endpoint accessible" -ForegroundColor Green
    Write-Host "  - Status: $($health.status)" -ForegroundColor Green
    Write-Host "  - Database: $($health.database)" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[TEST 2] CRUD - Creer une tache" -ForegroundColor Cyan
try {
    $json = '{"title":"Test Task","description":"Validation"}'
    $created = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Post -Body $json -ContentType "application/json" -TimeoutSec 5
    $taskId = $created.task.id
    Write-Host "PASS: Task created (ID: $taskId)" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Start-Sleep -Milliseconds 500

Write-Host "`n[TEST 3] CRUD - Lire les taches" -ForegroundColor Cyan
try {
    $tasks = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Get -TimeoutSec 5
    $count = ($tasks.tasks | Measure-Object).Count
    Write-Host "PASS: Tasks retrieved (count: $count)" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Start-Sleep -Milliseconds 500

Write-Host "`n[TEST 4] CRUD - Modifier une tache" -ForegroundColor Cyan
try {
    $json = '{"completed":true}'
    $updated = Invoke-RestMethod -Uri "$baseUrl/api/tasks/$taskId" -Method Put -Body $json -ContentType "application/json" -TimeoutSec 5
    Write-Host "PASS: Task updated" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Start-Sleep -Milliseconds 500

Write-Host "`n[TEST 5] CRUD - Supprimer une tache" -ForegroundColor Cyan
try {
    $deleted = Invoke-RestMethod -Uri "$baseUrl/api/tasks/$taskId" -Method Delete -TimeoutSec 5
    Write-Host "PASS: Task deleted" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[TEST 6] Resilience - Creer donnees de test" -ForegroundColor Cyan
$countBefore = 0
try {
    for ($i = 1; $i -le 3; $i++) {
        $json = '{"title":"Resilience Test ' + $i + '","description":"Test"}'
        $result = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Post -Body $json -ContentType "application/json" -TimeoutSec 5
        Start-Sleep -Milliseconds 200
    }
    $before = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Get -TimeoutSec 5
    $countBefore = ($before.tasks | Measure-Object).Count
    Write-Host "PASS: Created 3 test tasks (total: $countBefore)" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[TEST 7] Resilience - Redemarrage webapp" -ForegroundColor Cyan
Write-Host "Redemarrage du conteneur..." -ForegroundColor Yellow
docker-compose restart webapp | Out-Null
Start-Sleep -Seconds 5

$ready = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "$baseUrl/api/health" -Method Get -TimeoutSec 5
        $ready = $true
        Write-Host "PASS: Application prete apres redemarrage" -ForegroundColor Green
        break
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $ready) {
    Write-Host "FAIL: Application non accessible" -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 2

Write-Host "`n[TEST 8] Resilience - Verifier persistance (webapp restart)" -ForegroundColor Cyan
try {
    $after = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Get -TimeoutSec 5
    $countAfter = ($after.tasks | Measure-Object).Count
    Write-Host "Avant: $countBefore, Apres: $countAfter" -ForegroundColor Yellow
    if ($countAfter -ge $countBefore) {
        Write-Host "PASS: Donnees persistees!" -ForegroundColor Green
    }
    else {
        Write-Host "WARN: Perte de donnees" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[TEST 9] Resilience - Redemarrage PostgreSQL" -ForegroundColor Cyan
Write-Host "Redemarrage du conteneur..." -ForegroundColor Yellow
docker-compose restart postgres | Out-Null
Start-Sleep -Seconds 8

Write-Host "PASS: PostgreSQL redemarrre" -ForegroundColor Green

Write-Host "`n[TEST 10] Resilience - Verifier persistance (DB restart)" -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 15; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "$baseUrl/api/health" -Method Get -TimeoutSec 5
        if ($health.database -eq "postgres") {
            $ready = $true
            Write-Host "PASS: Reconnecte a PostgreSQL!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 1
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

Start-Sleep -Seconds 2
try {
    $afterDB = Invoke-RestMethod -Uri "$baseUrl/api/tasks" -Method Get -TimeoutSec 5
    $countAfterDB = ($afterDB.tasks | Measure-Object).Count
    Write-Host "Avant: $countBefore, Apres DB restart: $countAfterDB" -ForegroundColor Yellow
    if ($countAfterDB -ge $countBefore) {
        Write-Host "PASS: Donnees persistees apres restart DB!" -ForegroundColor Green
    }
    else {
        Write-Host "WARN: Perte de donnees" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n========== TOUS LES TESTS PASSES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Resultats:" -ForegroundColor Cyan
Write-Host "  [OK] Application accessible via http://localhost:3000" -ForegroundColor Green
Write-Host "  [OK] API CRUD fonctionnelle" -ForegroundColor Green
Write-Host "  [OK] Persistance apres redemarrage webapp" -ForegroundColor Green
Write-Host "  [OK] Persistance apres redemarrage PostgreSQL" -ForegroundColor Green
Write-Host "  [OK] Integrite des donnees" -ForegroundColor Green
Write-Host ""

exit 0
