param(
    [string]$BackendHost = "127.0.0.1",
    [int]$BackendPort = 8000,
    [string]$FlutterDevice = "web-server",
    [string]$FlutterHost = "localhost",
    [int]$FlutterPort = 8080,
    [string]$FirebaseConfig = "config/firebase.json",
    [bool]$OpenBrowser = $true
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FrontendDir = Join-Path $RepoRoot "frontend/sentineledge_app"
$FirebaseConfigPath = Join-Path $FrontendDir $FirebaseConfig
$EnvPath = Join-Path $RepoRoot ".env"
$BackendUrl = "http://${BackendHost}:${BackendPort}"
$FrontendUrl = "http://${FlutterHost}:${FlutterPort}"

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

if ($FlutterDevice -eq "web-server") {
    $FlutterCommand = "flutter run -d web-server --web-hostname $FlutterHost --web-port $FlutterPort --dart-define-from-file=$FirebaseConfig --dart-define=SENTINELEDGE_API_BASE_URL=$BackendUrl"
}
else {
    $FlutterCommand = "flutter run -d $FlutterDevice --dart-define-from-file=$FirebaseConfig --dart-define=SENTINELEDGE_API_BASE_URL=$BackendUrl"
}

$FrontendCommand = @"
`$ErrorActionPreference = 'Stop'
Set-Location '$FrontendDir'
$FlutterCommand
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

if ($FlutterDevice -eq "web-server" -and $OpenBrowser) {
    Start-Sleep -Seconds 5
    Write-Host "Opening $FrontendUrl in your default browser"
    Start-Process $FrontendUrl
}

Write-Host ""
Write-Host "Backend:  $BackendUrl"
if ($FlutterDevice -eq "web-server") {
    Write-Host "Frontend: $FrontendUrl"
}
else {
    Write-Host "Frontend: Flutter $FlutterDevice window"
}
Write-Host "Stop the services by closing the opened PowerShell windows or pressing Ctrl+C in each window."
