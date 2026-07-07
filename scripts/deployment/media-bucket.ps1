<#
.SYNOPSIS
    Create the OSS media bucket and apply retention lifecycle rules.

.DESCRIPTION
    Idempotent, one-shot setup for the media bucket (event clips + recordings).
    Creates the bucket private if missing, then applies lifecycle rules that
    auto-delete objects by prefix age: events/ after -EventRetentionDays and
    recordings/ after -RecordingRetentionDays. put_bucket_lifecycle replaces
    the whole lifecycle config, so rerunning is safe and this script is the
    single source of truth for the bucket's rules.

    -EventRetentionDays 0 (default) reads MEDIA_RETENTION_DAYS from the repo
    .env so the rule stays in sync with the backend's clip expires_at stamping.
    If production config lives in KMS instead, pass the value explicitly.

    Do NOT point this at the web bucket (erlang-vision) — it would wipe that
    bucket's config and expire the deployed app files.

.EXAMPLE
    ./scripts/deployment/media-bucket.ps1

.EXAMPLE
    ./scripts/deployment/media-bucket.ps1 -EventRetentionDays 7 -RecordingRetentionDays 3
#>
param(
    [string]$Bucket = "erlang-media-bucket",
    [string]$Region = "ap-southeast-3",
    [int]$EventRetentionDays = 0,
    [int]$RecordingRetentionDays = 3
)

$ErrorActionPreference = "Stop"

if ($Bucket -eq "erlang-vision") {
    Write-Error "Refusing to manage lifecycle on the web bucket (erlang-vision)."
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")

# --- Preflight -------------------------------------------------------------

if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
    Write-Error "python was not found on PATH (needed for the OSS API calls)."
}
python -c "import oss2" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing oss2 SDK..." -ForegroundColor Cyan
    python -m pip install --quiet oss2
    if ($LASTEXITCODE -ne 0) { Write-Error "pip install oss2 failed." }
}

# --- Apply lifecycle rules --------------------------------------------------
# oss2 handles request signing; PowerShell hands it the bucket/region/values.

$env:SENTINELEDGE_OSS_BUCKET = $Bucket
$env:SENTINELEDGE_OSS_REGION = $Region
$env:SENTINELEDGE_EVENT_RETENTION_DAYS = $EventRetentionDays
$env:SENTINELEDGE_RECORDING_RETENTION_DAYS = $RecordingRetentionDays
$env:SENTINELEDGE_REPO_ROOT = $RepoRoot

Write-Host "Applying lifecycle rules to OSS bucket $Bucket ($Region)..." -ForegroundColor Cyan
@'
import os, sys
from pathlib import Path
import oss2
from oss2.models import BucketLifecycle, LifecycleExpiration, LifecycleRule

repo_root = Path(os.environ["SENTINELEDGE_REPO_ROOT"])
bucket_name = os.environ["SENTINELEDGE_OSS_BUCKET"]
region = os.environ["SENTINELEDGE_OSS_REGION"]
event_days = int(os.environ["SENTINELEDGE_EVENT_RETENTION_DAYS"])
recording_days = int(os.environ["SENTINELEDGE_RECORDING_RETENTION_DAYS"])

env_file = repo_root / ".env"
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

if event_days <= 0:
    event_days = int(os.environ.get("MEDIA_RETENTION_DAYS", "7"))

key_id = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_ID")
key_secret = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_SECRET")
if not key_id or not key_secret:
    sys.exit("ALIBABA_CLOUD_ACCESS_KEY_ID / _SECRET not set (env or .env).")

auth = oss2.Auth(key_id, key_secret)
bucket = oss2.Bucket(auth, f"https://oss-{region}.aliyuncs.com", bucket_name)

try:
    bucket.get_bucket_info()
except oss2.exceptions.NoSuchBucket:
    # Private: media is served exclusively through backend-signed URLs.
    print(f"Creating bucket {bucket_name} in {region} (private)...")
    bucket.create_bucket(
        oss2.BUCKET_ACL_PRIVATE,
        oss2.models.BucketCreateConfig(oss2.BUCKET_STORAGE_CLASS_STANDARD),
    )

bucket.put_bucket_lifecycle(BucketLifecycle([
    LifecycleRule(
        "expire-event-clips", "events/",
        status=LifecycleRule.ENABLED,
        expiration=LifecycleExpiration(days=event_days),
    ),
    LifecycleRule(
        "expire-recordings", "recordings/",
        status=LifecycleRule.ENABLED,
        expiration=LifecycleExpiration(days=recording_days),
    ),
]))

for rule in bucket.get_bucket_lifecycle().rules:
    print(f"  {rule.id}: prefix={rule.prefix!r} expire_days={rule.expiration.days} status={rule.status}")
'@ | python -
if ($LASTEXITCODE -ne 0) { Write-Error "Applying OSS lifecycle rules failed." }

Write-Host ""
Write-Host "Lifecycle rules active on $Bucket." -ForegroundColor Green
Write-Host "Rerun after changing MEDIA_RETENTION_DAYS so the bucket rule stays in sync." -ForegroundColor Yellow
