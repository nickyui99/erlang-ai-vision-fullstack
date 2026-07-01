<#
.SYNOPSIS
    Build (and later push + deploy) the backend container.

.DESCRIPTION
    Single source of truth for shipping the backend. Today it does the first
    stage only: build backend/Dockerfile into a tagged image and verify it
    boots by hitting /healthz. Tests are run by CI, not here. Push-to-registry
    and remote deploy are stubbed below (-Deploy) for once a target is chosen.

.EXAMPLE
    ./scripts/deployment/backend.ps1
    # builds erlang-ai-vision-backend:<git-sha> and :local, smoke-tests it

.EXAMPLE
    ./scripts/deployment/backend.ps1 -Tag v1.2.0 -SkipSmoke
#>
param(
    [string]$Tag,
    [string]$Name = "erlang-ai-vision-backend",
    [switch]$SkipSmoke,
    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$Dockerfile = Join-Path $RepoRoot "backend/Dockerfile"

# --- Preflight -------------------------------------------------------------

if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Error "docker was not found on PATH."
}
if (-not (Test-Path $Dockerfile)) {
    Write-Error "Missing $Dockerfile."
}

# Fail early with a clear message if the daemon is down, rather than a raw
# named-pipe error from `docker build`.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker daemon is not running. Start Docker Desktop and retry."
}

# Default the tag to the current git short SHA so each image is traceable.
if (-not $Tag) {
    if (Get-Command "git" -ErrorAction SilentlyContinue) {
        $Tag = (git -C $RepoRoot rev-parse --short HEAD).Trim()
    }
    if (-not $Tag) {
        Write-Error "Could not derive a tag from git. Pass -Tag explicitly."
    }
}

$Image = "$Name`:$Tag"
Write-Host "Building image: $Image" -ForegroundColor Cyan

# --- Build -----------------------------------------------------------------

docker build -f $Dockerfile -t $Image -t "$Name`:local" $RepoRoot
if ($LASTEXITCODE -ne 0) { Write-Error "docker build failed." }

# --- Smoke: does the image actually boot? ----------------------------------

if (-not $SkipSmoke) {
    Write-Host "Smoke-testing the image (starting container, checking /healthz)..." -ForegroundColor Cyan

    # Let Docker assign the name; capture the container ID so concurrent runs
    # (local + CI) never collide on a fixed name.
    # APP_ENV=test keeps the container keyless/offline (MockQwenClient, no external calls).
    $Container = (docker run -d -e APP_ENV=test -p 18000:8000 $Image).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Container) { Write-Error "Failed to start smoke container." }

    $ok = $false
    try {
        for ($i = 1; $i -le 10; $i++) {
            Start-Sleep -Seconds 2
            try {
                $resp = Invoke-WebRequest -Uri "http://localhost:18000/healthz" -TimeoutSec 5 -UseBasicParsing
                if ($resp.StatusCode -eq 200) { $ok = $true; break }
            }
            catch {
                Write-Host "  attempt $i/10 not ready yet..." -ForegroundColor DarkGray
            }
        }

        if (-not $ok) {
            Write-Host "Container logs:" -ForegroundColor Yellow
            docker logs $Container
            Write-Error "Image built but /healthz did not return 200. See logs above."
        }
    }
    finally {
        docker rm -f $Container 2>$null | Out-Null
    }
}

Write-Host ""
Write-Host "Built and verified $Image (also tagged $Name`:local)." -ForegroundColor Green

# --- Deploy (stub — expand once a target is chosen) ------------------------
# When ready, this block will: docker login <registry>; docker push $Image;
# then ship it to the target (VM: ssh + `BACKEND_IMAGE=$Image docker compose up -d`).
# Kept as a flag so the build path above stays runnable on its own.
if ($Deploy) {
    Write-Error "Deploy is not implemented yet. Build/push is the current scope; wire the target here later."
}
