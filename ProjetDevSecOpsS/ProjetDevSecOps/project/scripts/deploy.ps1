<#
Deploy Kubernetes manifests in `k8s/` and create the `webapp-secret` from env or prompt.
Usage:
  powershell.exe -File .\scripts\deploy.ps1

Behavior:
- Requires `kubectl` available and a configured context (current-context set).
- Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from environment or prompts interactively.
- Creates/updates the `webapp-secret` and applies all files in `k8s/`.
- Waits for `webapp-deployment` rollout and prints helpful follow-ups.
#>

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host 'kubectl not found in PATH. Install or configure kubectl before running this script.' -ForegroundColor Red
    exit 1
}

# check current context
$context = (& kubectl config current-context) 2>$null
if (-not $context) {
    Write-Host 'kubectl current-context is not set or cluster is not reachable. Configure your kubeconfig or start Minikube/Docker Desktop Kubernetes.' -ForegroundColor Yellow
    exit 1
}

# get or prompt for Supabase values
if (-not $env:SUPABASE_URL) {
    $supabaseUrl = Read-Host 'Enter SUPABASE_URL (e.g. https://your-project.supabase.co)'
} else { $supabaseUrl = $env:SUPABASE_URL }

if (-not $env:SUPABASE_ANON_KEY) {
    $anonKey = Read-Host 'Enter SUPABASE_ANON_KEY'
} else { $anonKey = $env:SUPABASE_ANON_KEY }

if (-not $supabaseUrl -or -not $anonKey) {
    Write-Host 'SUPABASE_URL and SUPABASE_ANON_KEY are required. Aborting.' -ForegroundColor Red
    exit 1
}

Write-Host 'Creating/updating Kubernetes secret `webapp-secret`'
kubectl create secret generic webapp-secret `
    --from-literal=SUPABASE_URL="$supabaseUrl" `
    --from-literal=SUPABASE_ANON_KEY="$anonKey" `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host 'Applying manifests in `k8s/`'
kubectl apply -f k8s/

Write-Host 'Waiting for webapp deployment rollout (timeout 120s)'
& kubectl rollout status deployment/webapp-deployment --timeout=120s

Write-Host 'Done. Current pods and services:'
kubectl get pods,svc

Write-Host "If the webapp is not reachable, try port-forwarding:"
Write-Host '  kubectl port-forward svc/webapp-service 3000:3000'
