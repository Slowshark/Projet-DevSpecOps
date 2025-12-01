<#
Run the `kubernetes-webapp:latest` image locally. The script:
- checks port 3000 and uses 3001 if 3000 is already in use
- reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from environment or prompts for them
- runs the container with the provided env vars

Usage:
  powershell.exe -File .\scripts\run-local.ps1
#>

function Test-PortInUse {
    param([int]$Port)
    $out = netstat -ano | Select-String ":$Port "
    return ($out -ne $null)
}

# decide host port
$hostPort = 3000
if (Test-PortInUse -Port 3000) {
    Write-Host "Port 3000 is in use on host; falling back to 3001"
    $hostPort = 3001
}

# read env vars or prompt
if (-not $env:SUPABASE_URL) {
    $supabaseUrl = Read-Host 'Enter SUPABASE_URL (e.g. https://your-project.supabase.co)'
} else {
    $supabaseUrl = $env:SUPABASE_URL
}

if (-not $env:SUPABASE_ANON_KEY) {
    $anonKey = Read-Host 'Enter SUPABASE_ANON_KEY'
} else {
    $anonKey = $env:SUPABASE_ANON_KEY
}

if (-not $supabaseUrl -or -not $anonKey) {
    Write-Host 'SUPABASE_URL and SUPABASE_ANON_KEY are required. Aborting.' -ForegroundColor Red
    exit 1
}

Write-Host "Running container on host port $hostPort (container port 3000)"

docker run --rm -p ${hostPort}:3000 `
    -e SUPABASE_URL="$supabaseUrl" `
    -e SUPABASE_ANON_KEY="$anonKey" `
    kubernetes-webapp:latest
