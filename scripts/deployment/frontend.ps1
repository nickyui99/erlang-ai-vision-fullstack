<#
.SYNOPSIS
    Build the Erlang AI Vision Flutter web app (WASM) and deploy it to OSS.

.DESCRIPTION
    One-shot frontend deploy: builds build/web/ as a WASM bundle, then uploads
    it to the OSS static-website bucket with correct Content-Type per file
    (.wasm as application/wasm) and cache headers. Creates the bucket
    (public-read + static website hosting) if it does not exist.

    Config (Firebase keys, API base URL) is injected via
    --dart-define-from-file, matching scripts/start-dev.ps1. OSS credentials
    come from ALIBABA_CLOUD_ACCESS_KEY_ID / _SECRET in the environment or the
    repo .env. Pass -SkipUpload to only build.

    -ApiBaseUrl is optional: release web builds default to the page origin
    (Caddy serves app + API from one host), so omit it for the standard
    deploy and pass it only to target a different backend host.

.EXAMPLE
    ./scripts/deployment/frontend.ps1

.EXAMPLE
    ./scripts/deployment/frontend.ps1 -ApiBaseUrl https://api.example.com -SkipUpload
#>
param(
    [string]$ApiBaseUrl,
    [string]$FirebaseConfig = "config/firebase.json",
    [string]$Bucket = "erlang-vision",
    [string]$Region = "ap-southeast-3",
    [switch]$SkipUpload
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
if (-not $SkipUpload) {
    if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
        Write-Error "python was not found on PATH (needed for the OSS upload)."
    }
    python -c "import oss2" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installing oss2 SDK..." -ForegroundColor Cyan
        python -m pip install --quiet oss2
        if ($LASTEXITCODE -ne 0) { Write-Error "pip install oss2 failed." }
    }
}

# --- Build ------------------------------------------------------------------

# Dart native-assets build hooks invoke the SDK with unquoted paths and break
# when the SDK, pub cache, or project sits under a directory with spaces
# (e.g. C:\Users\Kenneth Chua). 8.3 short paths dodge that; ShortPath is a
# no-op where paths have no spaces or 8.3 names are disabled.
$fso = New-Object -ComObject Scripting.FileSystemObject
$FlutterBinDir = Split-Path (Get-Command "flutter").Source
$env:Path = $fso.GetFolder($FlutterBinDir).ShortPath + [IO.Path]::PathSeparator + $env:Path
$DefaultPubCache = Join-Path $env:LOCALAPPDATA "Pub/Cache"
if (-not $env:PUB_CACHE -and (Test-Path $DefaultPubCache)) {
    $env:PUB_CACHE = $fso.GetFolder($DefaultPubCache).ShortPath
}
$FrontendDir = $fso.GetFolder($FrontendDir).ShortPath

Push-Location $FrontendDir
try {
    Write-Host "Fetching packages..." -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get failed." }

    # --wasm matches the deploy architecture (Flutter Web WASM on OSS).
    # dart-define-from-file supplies Firebase keys; API base URL is passed
    # separately so the same firebase.json works across environments.
    $BuildArgs = @("build", "web", "--wasm", "--dart-define-from-file=$FirebaseConfig")
    if ($ApiBaseUrl) {
        $BuildArgs += "--dart-define=ERLANG_API_BASE_URL=$ApiBaseUrl"
        Write-Host "Building web (WASM) against $ApiBaseUrl..." -ForegroundColor Cyan
    }
    else {
        Write-Host "Building web (WASM); release default is same-origin API..." -ForegroundColor Cyan
    }
    flutter @BuildArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "flutter build web failed." }

    # Serve the engine binaries (skwasm/CanvasKit, the largest downloads) from
    # Google's free flutter-canvaskit CDN instead of the high-RTT OSS origin.
    # The loader already defaults to gstatic; this rewrites the index.html
    # preload hints to the same revision-pinned URL so the early fetch is the
    # one the engine reuses.
    $BootstrapPath = Join-Path $FrontendDir "build/web/flutter_bootstrap.js"
    $Bootstrap = Get-Content -Raw $BootstrapPath
    if ($Bootstrap -notmatch '"engineRevision":"([0-9a-f]+)"') { Write-Error "engineRevision was not found in flutter_bootstrap.js." }
    $EngineBase = "https://www.gstatic.com/flutter-canvaskit/$($Matches[1])/"
    $IndexPath = Join-Path $FrontendDir "build/web/index.html"
    $Index = Get-Content -Raw $IndexPath
    $LocalEngineBase = "var engineBase = 'canvaskit/';"
    if (-not $Index.Contains($LocalEngineBase)) { Write-Error "engineBase preload placeholder was not found in index.html." }
    $Index = $Index.Replace($LocalEngineBase, "var engineBase = '$EngineBase';")
    [System.IO.File]::WriteAllText($IndexPath, $Index, [System.Text.UTF8Encoding]::new($false))
}
finally {
    Pop-Location
}

$Output = Join-Path $FrontendDir "build/web"
Write-Host ""
Write-Host "Built web bundle at $Output" -ForegroundColor Green

if ($SkipUpload) {
    Write-Host "Skipping upload (-SkipUpload)." -ForegroundColor Yellow
    return
}

# --- Upload to OSS ----------------------------------------------------------
# oss2 handles request signing; PowerShell hands it the bucket/region/paths.

$env:ERLANG_OSS_BUCKET = $Bucket
$env:ERLANG_OSS_REGION = $Region
$env:ERLANG_WEB_BUILD_DIR = $Output
$env:ERLANG_REPO_ROOT = $RepoRoot

Write-Host "Uploading to OSS bucket $Bucket ($Region)..." -ForegroundColor Cyan
@'
import brotli, mimetypes, os, sys
from pathlib import Path
import oss2

repo_root = Path(os.environ["ERLANG_REPO_ROOT"])
build_dir = Path(os.environ["ERLANG_WEB_BUILD_DIR"])
bucket_name = os.environ["ERLANG_OSS_BUCKET"]
region = os.environ["ERLANG_OSS_REGION"]

env_file = repo_root / ".env"
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

key_id = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_ID")
key_secret = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_SECRET")
if not key_id or not key_secret:
    sys.exit("ALIBABA_CLOUD_ACCESS_KEY_ID / _SECRET not set (env or .env).")

CONTENT_TYPES = {
    ".wasm": "application/wasm",
    ".js": "text/javascript",
    ".mjs": "text/javascript",
    ".json": "application/json",
    ".woff2": "font/woff2",
    ".otf": "font/otf",
    ".frag": "application/octet-stream",
    ".webp": "image/webp",
}
# Entry/manifest files the browser must revalidate so deploys take effect
# immediately; everything else is version-gated by the service worker.
NO_CACHE = {"index.html", "flutter_service_worker.js", "version.json", "flutter_bootstrap.js"}
# Fonts, images, and icons only change on rebrands; a day of caching keeps
# repeat visits off the high-RTT EIP while the ETag still catches updates.
LONG_CACHE_PREFIXES = ("assets/", "icons/")
# The engine binaries are served from Google's flutter-canvaskit CDN (see the
# index.html preload patch above), so the local copies are dead weight.
SKIP_PREFIXES = ("canvaskit/",)
# Flutter's WebAssembly and CanvasKit binaries are several megabytes each. OSS
# does not compress proxied objects automatically, so upload Brotli-encoded
# variants with the original object names; browsers transparently decompress
# them before the Flutter loader sees the bytes.
BROTLI_SUFFIXES = {".js", ".mjs", ".wasm", ".json", ".frag"}

auth = oss2.Auth(key_id, key_secret)
bucket = oss2.Bucket(auth, f"https://oss-{region}.aliyuncs.com", bucket_name)

try:
    bucket.get_bucket_info()
except oss2.exceptions.NoSuchBucket:
    print(f"Creating bucket {bucket_name} in {region} (public-read)...")
    bucket.create_bucket(
        oss2.BUCKET_ACL_PUBLIC_READ,
        oss2.models.BucketCreateConfig(oss2.BUCKET_STORAGE_CLASS_STANDARD),
    )
# New buckets ship with Block Public Access on, which overrides the
# public-read ACL with 403s.
bucket.put_bucket_public_access_block(False)
bucket.put_bucket_website(oss2.models.BucketWebsite("index.html", "index.html"))

uploaded = 0
for file in sorted(build_dir.rglob("*")):
    if not file.is_file():
        continue
    key = file.relative_to(build_dir).as_posix()
    if key.startswith(SKIP_PREFIXES):
        continue
    content_type = CONTENT_TYPES.get(file.suffix) or mimetypes.guess_type(file.name)[0] or "application/octet-stream"
    if key in NO_CACHE:
        cache = "no-cache"
    elif key.startswith(LONG_CACHE_PREFIXES):
        cache = "public, max-age=86400"
    else:
        cache = "public, max-age=3600"
    headers = {"Content-Type": content_type, "Cache-Control": cache}
    if file.suffix in BROTLI_SUFFIXES:
        headers["Content-Encoding"] = "br"
        headers["Vary"] = "Accept-Encoding"
        with file.open("rb") as source:
            bucket.put_object(key, brotli.compress(source.read(), quality=11), headers=headers)
    else:
        bucket.put_object_from_file(key, str(file), headers=headers)
    uploaded += 1

print(f"Uploaded {uploaded} files to {bucket_name}.")
'@ | python -
if ($LASTEXITCODE -ne 0) { Write-Error "OSS upload failed." }

# OSS forces Content-Disposition: attachment for HTML on the default
# *.aliyuncs.com endpoint; browsers only render the site through a custom
# domain bound to the bucket (OSS console > Bucket > Domain Names).
Write-Host ""
Write-Host "Deployed to https://$Bucket.oss-$Region.aliyuncs.com" -ForegroundColor Green
Write-Host "Browsers render it only via a custom domain bound to the bucket." -ForegroundColor Yellow
