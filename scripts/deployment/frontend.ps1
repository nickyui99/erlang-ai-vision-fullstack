<#
.SYNOPSIS
    Build the Erlang AI Vision Flutter web app (WASM) for static hosting.

.DESCRIPTION
    First stage of the frontend pipeline: produce build/web/ as a WASM bundle
    ready to upload to OSS. Config (Firebase keys, API base URL) is injected via
    --dart-define-from-file, matching scripts/start-dev.ps1. Tests/analyze are
    CI's job; OSS upload is a later step.

    Output serves from frontend/sentineledge_app/build/web/. Per the deploy
    architecture, the OSS bucket must serve .wasm as application/wasm.

.EXAMPLE
    ./scripts/deployment/frontend.ps1 -ApiBaseUrl https://api.example.com

.EXAMPLE
    ./scripts/deployment/frontend.ps1 -FirebaseConfig config/firebase.json -ApiBaseUrl https://api.example.com
#>
param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [string]$FirebaseConfig = "config/firebase.json"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$FrontendDir = Join-Path $RepoRoot "frontend/sentineledge_app"
$FirebaseConfigPath = Join-Path $FrontendDir $FirebaseConfig

# --- Preflight -------------------------------------------------------------

if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Error "flutter was not found on PATH. Open a shell where flutter is available, then rerun this script."
}
if (-not (Test-Path $FrontendDir)) {
    Write-Error "Missing $FrontendDir."
}
if (-not (Test-Path $FirebaseConfigPath)) {
    Write-Error "Missing $FirebaseConfigPath. Copy config/firebase.example.json to config/firebase.json and fill the Firebase Web app settings."
}

Push-Location $FrontendDir
try {
    Write-Host "Fetching packages..." -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get failed." }

    # --wasm matches the deploy architecture (Flutter Web WASM on OSS).
    # dart-define-from-file supplies Firebase keys; API base URL is passed
    # separately so the same firebase.json works across environments.
    Write-Host "Building web (WASM) against $ApiBaseUrl..." -ForegroundColor Cyan
    flutter build web --wasm `
        --dart-define-from-file=$FirebaseConfig `
        --dart-define=SENTINELEDGE_API_BASE_URL=$ApiBaseUrl
    if ($LASTEXITCODE -ne 0) { Write-Error "flutter build web failed." }
}
finally {
    Pop-Location
}

$Output = Join-Path $FrontendDir "build/web"
Write-Host ""
Write-Host "Built web bundle at $Output" -ForegroundColor Green
Write-Host "Upload its contents to OSS (serve .wasm as application/wasm)." -ForegroundColor Green
