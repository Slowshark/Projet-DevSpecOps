# Script de vérification du déploiement Kubernetes
# Usage: .\scripts\verify-k8s-deployment.ps1 [-Namespace devsecops] [-WaitForReady]

param(
    [string]$Namespace = "devsecops",
    [switch]$WaitForReady = $false,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Test-PodHealth {
    Write-Header "Vérification de la santé des pods"
    
    # Check Postgres pod
    Write-Host "📍 Pod PostgreSQL:" -ForegroundColor Yellow
    $PgPods = kubectl get pods -n $Namespace -l app=postgres -o jsonpath='{.items[*].metadata.name}'
    if ($PgPods) {
        foreach ($Pod in $PgPods -split ' ') {
            if ($Pod) {
                $Status = kubectl get pod $Pod -n $Namespace -o jsonpath='{.status.phase}'
                Write-Host "   $Pod : $Status" -ForegroundColor $(if ($Status -eq "Running") {"Green"} else {"Yellow"})
                
                if ($Status -eq "Running") {
                    kubectl logs $Pod -n $Namespace --tail=5 | ForEach-Object { Write-Host "     $_" }
                }
            }
        }
    } else {
        Write-Host "   ❌ Aucun pod PostgreSQL trouvé" -ForegroundColor Red
    }
    
    # Check WebApp pods
    Write-Host "`n📍 Pods application web:" -ForegroundColor Yellow
    $WebPods = kubectl get pods -n $Namespace -l app=webapp -o jsonpath='{.items[*].metadata.name}'
    if ($WebPods) {
        foreach ($Pod in $WebPods -split ' ') {
            if ($Pod) {
                $Status = kubectl get pod $Pod -n $Namespace -o jsonpath='{.status.phase}'
                $Ready = kubectl get pod $Pod -n $Namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
                Write-Host "   $Pod : Phase=$Status, Ready=$Ready" -ForegroundColor $(if ($Ready -eq "True") {"Green"} else {"Yellow"})
            }
        }
    } else {
        Write-Host "   ❌ Aucun pod application trouvé" -ForegroundColor Red
    }
}

function Test-Services {
    Write-Header "Vérification des services"
    
    # Check Postgres service
    Write-Host "🔌 Service PostgreSQL:" -ForegroundColor Yellow
    $PgSvc = kubectl get service postgres-service -n $Namespace -o jsonpath='{.spec.clusterIP}' 2>/dev/null
    if ($PgSvc) {
        Write-Host "   ClusterIP: $PgSvc:5432" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Service PostgreSQL non trouvé" -ForegroundColor Red
    }
    
    # Check WebApp services
    Write-Host "`n🔌 Service NodePort (application):" -ForegroundColor Yellow
    $NodePort = kubectl get service webapp-service -n $Namespace -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null
    if ($NodePort) {
        Write-Host "   NodePort: $NodePort" -ForegroundColor Green
        
        # Get node address
        $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null
        if (-not $Node) {
            $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
        }
        if ($Node) {
            Write-Host "   Accès: http://$($Node):$NodePort" -ForegroundColor Green
        }
    } else {
        Write-Host "   ⚠️  Service NodePort non trouvé" -ForegroundColor Yellow
    }
}

function Test-Database {
    Write-Header "Test de connexion à PostgreSQL"
    
    Write-Host "⏳ Test de connexion à PostgreSQL via port-forward..." -ForegroundColor Yellow
    
    # Start port-forward in background
    $PFJob = Start-Job -ScriptBlock {
        param($Namespace)
        kubectl port-forward -n $Namespace svc/postgres-service 5432:5432 | Out-Null
    } -ArgumentList $Namespace
    
    Start-Sleep -Seconds 2
    
    # Test connection with psql via Docker if available
    $DockerCheck = docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tentative de connexion via Docker..." -ForegroundColor Yellow
        
        # Get postgres password
        $PgPassword = kubectl get secret postgres-secret -n $Namespace -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null
        $PgUser = kubectl get secret postgres-secret -n $Namespace -o jsonpath='{.data.POSTGRES_USER}' 2>/dev/null | base64 -d 2>/dev/null
        $PgDb = kubectl get secret postgres-secret -n $Namespace -o jsonpath='{.data.POSTGRES_DB}' 2>/dev/null | base64 -d 2>/dev/null
        
        if ($PgPassword -and $PgUser) {
            try {
                $Result = docker run --rm --network host postgres:15-alpine psql -h 127.0.0.1 -U $PgUser -d $PgDb -c "SELECT version();" -q 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Connexion PostgreSQL réussie" -ForegroundColor Green
                    Write-Host "   Version: $($Result | Select-Object -First 1)" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  Connexion échouée" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠️  Erreur lors du test: $_" -ForegroundColor Yellow
            }
        }
    }
    
    # Stop port-forward
    Stop-Job $PFJob
    Remove-Job $PFJob
}

function Test-API {
    Write-Header "Test de l'API application"
    
    Write-Host "⏳ Test de l'endpoint /api/health..." -ForegroundColor Yellow
    
    $NodePort = kubectl get service webapp-service -n $Namespace -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null
    if ($NodePort) {
        $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null
        if (-not $Node) {
            $Node = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
        }
        
        if ($Node) {
            try {
                $Health = Invoke-RestMethod -Uri "http://$($Node):$NodePort/api/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
                Write-Host "✅ API répondant" -ForegroundColor Green
                Write-Host "   Status: $($Health.status)" -ForegroundColor Green
                Write-Host "   Database: $($Health.database)" -ForegroundColor Green
                Write-Host "   Timestamp: $($Health.timestamp)" -ForegroundColor Green
            } catch {
                Write-Host "❌ API ne répond pas: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "⚠️  Impossible de déterminer l'adresse du nœud" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  Service NodePort non accessible" -ForegroundColor Yellow
    }
}

function Wait-ForDeployment {
    param([int]$Timeout = 300)
    
    Write-Header "Attente que tous les pods soient prêts"
    Write-Host "⏳ Timeout: ${Timeout}s" -ForegroundColor Yellow
    
    $Start = Get-Date
    while ((Get-Date) - $Start -lt (New-TimeSpan -Seconds $Timeout)) {
        $Deployments = kubectl get deployments -n $Namespace -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.status.readyReplicas}{","}{.status.desiredReplicas}{";"}{end}'
        $AllReady = $true
        
        foreach ($Item in $Deployments -split ';') {
            if ($Item) {
                $Name, $Status = $Item -split '='
                $Ready, $Desired = $Status -split ','
                
                if ($Ready -ne $Desired) {
                    Write-Host "  ⏳ $Name : $Ready/$Desired prêts" -ForegroundColor Yellow
                    $AllReady = $false
                } else {
                    Write-Host "  ✅ $Name : $Ready/$Desired prêts" -ForegroundColor Green
                }
            }
        }
        
        if ($AllReady) {
            Write-Host "`n✅ Tous les déploiements sont prêts" -ForegroundColor Green
            return $true
        }
        
        Start-Sleep -Seconds 5
    }
    
    Write-Host "`n❌ Timeout: Les déploiements ne sont pas prêts dans le délai imparti" -ForegroundColor Red
    return $false
}

# Main execution
try {
    Write-Host "`n🔍 Vérification du déploiement Kubernetes" -ForegroundColor Yellow
    Write-Host "   Namespace: $Namespace" -ForegroundColor Yellow
    
    if ($WaitForReady) {
        Wait-ForDeployment -Timeout $TimeoutSeconds
    }
    
    Test-PodHealth
    Test-Services
    Test-Database
    Test-API
    
    Write-Header "✅ Vérification complétée"
    
} catch {
    Write-Host "`n❌ Erreur lors de la vérification:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
