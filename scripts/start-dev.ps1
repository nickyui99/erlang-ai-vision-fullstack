param(
    [string]$BackendHost = "127.0.0.1",
    [int]$BackendPort = 8000,
    [string]$FlutterDevice = "chrome",
    [string]$FirebaseConfig = "config/firebase.json"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FrontendDir = Join-Path $RepoRoot "frontend/sentineledge_app"
$FirebaseConfigPath = Join-Path $FrontendDir $FirebaseConfig
$EnvPath = Join-Path $RepoRoot ".env"
$BackendUrl = "http://${BackendHost}:${BackendPort}"

if (-not (Test-Path $EnvPath)) {
    Write-Error "Missing .env. Copy .env.example to .env and fill the backend Firebase Admin settings."
}

if (-not (Test-Path $FirebaseConfigPath)) {
    Write-Error "Missing $FirebaseConfigPath. Copy config/firebase.example.json to config/firebase.json and fill the Firebase Web app settings."
}

if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter was not found on PATH. Open a shell where flutter is available, then rerun this script."
}

$BackendCommand = @"
`$ErrorActionPreference = 'Stop'
Set-Location '$RepoRoot'
`$env:PYTHONPATH = 'backend'
python -m uvicorn app.main:app --reload --host $BackendHost --port $BackendPort
"@

$FrontendCommand = @"
`$ErrorActionPreference = 'Stop'
Set-Location '$FrontendDir'
flutter run -d $FlutterDevice --dart-define-from-file=$FirebaseConfig --dart-define=SENTINELEDGE_API_BASE_URL=$BackendUrl
"@

Write-Host "Starting SentinelEdge backend at $BackendUrl"
Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    $BackendCommand
)

Start-Sleep -Seconds 2

Write-Host "Starting SentinelEdge Flutter frontend on $FlutterDevice"
Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    $FrontendCommand
)

Write-Host ""
Write-Host "Backend:  $BackendUrl"
Write-Host "Frontend: Flutter $FlutterDevice window"
Write-Host "Stop the services by closing the opened PowerShell windows or pressing Ctrl+C in each window."
