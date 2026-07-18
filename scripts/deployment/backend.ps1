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
    [switch]$SkipBuild,
    [switch]$Deploy,
    [string]$Region = "ap-southeast-3",
    [string]$AcrDomain = "crpi-9kvwsegbpo7ict75.ap-southeast-3.personal.cr.aliyuncs.com",
    [string]$AcrNamespace = "erlang-ai-vision",
    # Standing EIP (erlang-eic-static-ip, 47.250.155.149) so the public IP
    # survives group recreates. Empty string falls back to a throwaway auto-EIP.
    [string]$EipId = "eip-8pshynfdz57al5mjunni6",
    [string]$Bucket = "erlang-vision",
    # Public DNS name pointing at the standing EIP. Required for production TLS.
    [string]$Domain,
    # Temporary health-check deployment only; browser auth remains unusable until TLS is enabled.
    [switch]$AllowInsecureHttp,
    [string]$GroupName = "erlang-backend"
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

# --- Build -----------------------------------------------------------------

if (-not $SkipBuild) {
    # Demo simulation frames ship in the image (Option A): they're git-ignored
    # and generated locally, so ensure the folder exists for the Dockerfile COPY
    # and warn if it's empty (demo would have no video to play).
    $FramesDir = Join-Path $RepoRoot "data/demo_frames"
    if (-not (Test-Path $FramesDir)) {
        New-Item -ItemType Directory -Force -Path $FramesDir | Out-Null
    }
    $FrameCount = @(Get-ChildItem -Path $FramesDir -Recurse -Filter *.jpg -ErrorAction SilentlyContinue).Count
    if ($FrameCount -eq 0) {
        Write-Warning "data/demo_frames is empty - the deployed demo will have no video. Run scripts/extract_demo_frames.py --videos-dir first (LaptopEdge venv)."
    }
    else {
        Write-Host "Bundling $FrameCount demo frame(s) into the image." -ForegroundColor Cyan
    }

    Write-Host "Building image: $Image" -ForegroundColor Cyan
    docker build -f $Dockerfile -t $Image -t "$Name`:local" $RepoRoot
    if ($LASTEXITCODE -ne 0) { Write-Error "docker build failed." }
}

# --- Smoke: does the image actually boot? ----------------------------------

if (-not $SkipSmoke -and -not $SkipBuild) {
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

# --- Deploy: push to ACR, run on ECI behind a Caddy sidecar -----------------
# Topology: one ECI container group (FastAPI + Caddy) on the RDS vSwitch with
# a standing EIP. Caddy terminates HTTPS and routes /api + /healthz + /readyz to FastAPI, then reverse-
# proxies everything else to the OSS web bucket over the region-internal
# endpoint, stripping the forced-download headers so browsers render the SPA.
# Registry: ACR Personal Edition (activate once from the ROOT account in the
# console; RAM users cannot). Login uses a temporary API-minted token that
# lives only inside this process — no registry password needed here.
if (-not $Deploy) { return }
if (-not $Domain -and -not $AllowInsecureHttp) {
    Write-Error "-Domain is required for deployment. Create an A record to the standing EIP before deploying."
}

if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
    Write-Error "python was not found on PATH (needed for the ACR/ECI API calls)."
}
python -c "import alibabacloud_eci20180808, alibabacloud_rds20140815, alibabacloud_ecs20140526" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Alibaba Cloud SDKs..." -ForegroundColor Cyan
    python -m pip install --quiet alibabacloud_eci20180808 alibabacloud_rds20140815 alibabacloud_ecs20140526 alibabacloud_tea_openapi
    if ($LASTEXITCODE -ne 0) { Write-Error "pip install of Alibaba Cloud SDKs failed." }
}

$env:SE_REPO_ROOT = $RepoRoot
$env:SE_REGION = $Region
$env:SE_IMAGE_NAME = $Name
$env:SE_IMAGE_TAG = $Tag
$env:SE_BUCKET = $Bucket
$env:SE_GROUP_NAME = $GroupName
$env:SE_DOMAIN = $Domain
$env:SE_ALLOW_INSECURE_HTTP = $AllowInsecureHttp.IsPresent.ToString().ToLowerInvariant()
$env:SE_ACR_NAMESPACE = $AcrNamespace
$env:SE_ACR_DOMAIN = $AcrDomain
$env:SE_EIP_ID = $EipId

# Single phase: mint ACR token, docker push, then provision ECI. All in one
# python process so the token never crosses a process boundary or hits disk.
Write-Host "Pushing to ACR and provisioning ECI ($GroupName)..." -ForegroundColor Cyan
@'
import base64, json, os, re, socket, subprocess, sys, time
from pathlib import Path
from alibabacloud_tea_openapi import models as om
from alibabacloud_tea_util import models as util_models

repo_root = Path(os.environ["SE_REPO_ROOT"])
region = os.environ["SE_REGION"]
bucket = os.environ["SE_BUCKET"]
group_name = os.environ["SE_GROUP_NAME"]
allow_insecure_http = os.environ.get("SE_ALLOW_INSECURE_HTTP", "false").lower() == "true"
domain = os.environ["SE_DOMAIN"].strip().lower().rstrip(".")
if allow_insecure_http and domain:
    sys.exit("Use either -Domain for TLS or -AllowInsecureHttp for a temporary HTTP-only deployment, not both")
if not allow_insecure_http:
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", domain):
        sys.exit("-Domain must be a valid public hostname, without http:// or a path")
    try:
        socket.gethostbyname(domain)
    except OSError:
        sys.exit(f"DNS for {domain} is not resolvable. Create its A record to the standing EIP before deploying.")
acr_namespace = os.environ["SE_ACR_NAMESPACE"]
image_name = os.environ["SE_IMAGE_NAME"]
image_tag = os.environ["SE_IMAGE_TAG"]

for line in (repo_root / ".env").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip())

# The reader key stays outside the repo. Only its encoded bytes are sent to the
# backend container; Base64 prevents JSON/newline corruption but is not encryption.
project_id = os.environ.get("GOOGLE_SECRET_MANAGER_PROJECT", "").strip()
expected_secret_names = ("erlang-prod-secrets", "erlang-db-secrets")
secret_names = tuple(
    name.strip()
    for name in os.environ.get("GOOGLE_SECRET_MANAGER_SECRETS", "").split(",")
    if name.strip()
)
if not project_id:
    sys.exit("GOOGLE_SECRET_MANAGER_PROJECT is required in .env for deployment")
if secret_names != expected_secret_names:
    sys.exit(
        "GOOGLE_SECRET_MANAGER_SECRETS must be exactly "
        + ",".join(expected_secret_names)
    )

credential_path_value = os.environ.get(
    "GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE", ""
).strip()
if not credential_path_value:
    sys.exit("GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE is required in .env")
credential_path = Path(credential_path_value).expanduser()
if not credential_path.is_absolute():
    credential_path = repo_root / credential_path
if not credential_path.is_file():
    sys.exit(f"Google Secret Manager reader key was not found: {credential_path}")
credential_bytes = credential_path.read_bytes()
try:
    credential_document = json.loads(credential_bytes.decode("utf-8"))
except (UnicodeDecodeError, json.JSONDecodeError):
    sys.exit("Google Secret Manager reader key must be a valid UTF-8 JSON file")
required_credential_fields = {"type", "client_email", "private_key", "token_uri"}
if not isinstance(credential_document, dict) or not required_credential_fields.issubset(
    credential_document
):
    sys.exit("Google Secret Manager reader key is missing required service-account fields")
reader_credential_b64 = base64.b64encode(credential_bytes).decode("ascii")

AK = os.environ["ALIBABA_CLOUD_ACCESS_KEY_ID"]
SK = os.environ["ALIBABA_CLOUD_ACCESS_KEY_SECRET"]

def cfg(endpoint):
    return om.Config(access_key_id=AK, access_key_secret=SK, endpoint=endpoint, region_id=region)

# --- ACR Personal Edition: fixed Docker credentials, then push ---------------
# Personal Edition does not support API-minted temporary registry tokens. Create
# the instance, namespace and repository once in the console, then put only the
# registry username/password in the untracked local .env file.
registry = os.environ["SE_ACR_DOMAIN"]
_head, _tail = registry.split(".", 1)
vpc_registry = f"{_head}-vpc.{_tail}"
image = f"{vpc_registry}/{acr_namespace}/{image_name}:{image_tag}"
push_image = f"{registry}/{acr_namespace}/{image_name}:{image_tag}"
acr_username = os.environ.get("ACR_USERNAME", "").strip()
acr_password = os.environ.get("ACR_PASSWORD", "")
if not acr_username or not acr_password:
    sys.exit("ACR_USERNAME and ACR_PASSWORD are required in the untracked .env file. "
             "Activate Personal Edition and set its Docker login password in the ACR console first.")

def run(cmd, **kw):
    proc = subprocess.run(cmd, **kw)
    if proc.returncode != 0:
        sys.exit(f"command failed: {cmd[0]} {cmd[1] if len(cmd) > 1 else ''}")

print(f"docker push {push_image}", file=sys.stderr)
run(["docker", "login", registry, "--username", acr_username, "--password-stdin"],
    input=acr_password.encode())
run(["docker", "tag", f"{image_name}:{image_tag}", push_image])
run(["docker", "push", push_image])
# --- discover the RDS network so ECI lands in the same VPC/vSwitch ---------
from alibabacloud_rds20140815.client import Client as Rds
from alibabacloud_rds20140815 import models as rm
rds = Rds(cfg("rds.aliyuncs.com"))
db = rds.describe_dbinstances(rm.DescribeDBInstancesRequest(region_id=region)).body.items.dbinstance[0]
vpc_id, vswitch_id = db.vpc_id, db.v_switch_id

from alibabacloud_ecs20140526.client import Client as Ecs
from alibabacloud_ecs20140526 import models as em
ecs = Ecs(cfg(f"ecs.{region}.aliyuncs.com"))
vsw = [v for v in ecs.describe_vswitches(em.DescribeVSwitchesRequest(
    region_id=region, vpc_id=vpc_id)).body.v_switches.v_switch if v.v_switch_id == vswitch_id][0]

# --- security group: allow HTTP in, everything out --------------------------
sg_name = "erlang-backend-sg"
sgs = ecs.describe_security_groups(em.DescribeSecurityGroupsRequest(
    region_id=region, vpc_id=vpc_id, security_group_name=sg_name)).body.security_groups.security_group
if sgs:
    sg_id = sgs[0].security_group_id
else:
    sg_id = ecs.create_security_group(em.CreateSecurityGroupRequest(
        region_id=region, vpc_id=vpc_id, security_group_name=sg_name,
        description="Erlang AI Vision backend ECI: HTTP in")).body.security_group_id
    for port in ("80/80", "443/443"):
        ecs.authorize_security_group(em.AuthorizeSecurityGroupRequest(
            region_id=region, security_group_id=sg_id, ip_protocol="tcp",
            port_range=port, source_cidr_ip="0.0.0.0/0"))
print(f"security group: {sg_id}", file=sys.stderr)

# --- RDS whitelist: dedicated array for the ECI subnet ----------------------
# Avoid a no-op API mutation: RDS rejects updates while transitioning after a
# restart even when the existing whitelist is already the required subnet.
ip_arrays = rds.describe_dbinstance_iparray_list(
    rm.DescribeDBInstanceIPArrayListRequest(dbinstance_id=db.dbinstance_id)
).body.items.dbinstance_iparray
eci_ips = next(
    (str(item.security_iplist or "") for item in ip_arrays if item.dbinstance_iparray_name == "eci"),
    "",
)
if eci_ips != vsw.cidr_block:
    rds.modify_security_ips(rm.ModifySecurityIpsRequest(
        dbinstance_id=db.dbinstance_id, security_ips=vsw.cidr_block,
        dbinstance_iparray_name="eci", modify_mode="Cover"))
print(f"RDS whitelist 'eci' = {vsw.cidr_block}", file=sys.stderr)

# --- Caddy config ------------------------------------------------------------
oss_internal = f"{bucket}.oss-{region}-internal.aliyuncs.com"
caddy_site = ":80" if allow_insecure_http else domain
cors_origin = "https://pending.invalid" if allow_insecure_http else f"https://{domain}"
caddyfile = f"""
{caddy_site} {{
	header {{
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
		Referrer-Policy "strict-origin-when-cross-origin"
		Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
		Content-Security-Policy "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self' https://accounts.google.com; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com https://apis.google.com https://accounts.google.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com https://accounts.google.com https://apis.google.com https://*.googleapis.com https://*.firebaseapp.com https://*.firebaseio.com wss://*.firebaseio.com; worker-src 'self' blob:; frame-src https://accounts.google.com https://*.firebaseapp.com; media-src 'self' blob: https:; upgrade-insecure-requests"
	}}
	@hidden_docs path /docs /docs/* /openapi.json
	handle @hidden_docs {{
		respond "Not found" 404
	}}
	@backend path /api/* /healthz /readyz
	handle @backend {{
		reverse_proxy localhost:8000 {{
			flush_interval -1
		}}
	}}
	handle {{
		rewrite / /index.html
		reverse_proxy http://{oss_internal} {{
			header_up Host {oss_internal}
			header_down -Content-Disposition
			header_down -x-oss-force-download
			@missing status 404 403
			handle_response @missing {{
				rewrite * /index.html
				reverse_proxy http://{oss_internal} {{
					header_up Host {oss_internal}
					header_down -Content-Disposition
					header_down -x-oss-force-download
				}}
			}}
		}}
	}}
}}
"""
caddy_b64 = base64.b64encode(caddyfile.encode()).decode()

# --- container group ---------------------------------------------------------
from alibabacloud_eci20180808.client import Client as Eci
from alibabacloud_eci20180808 import models as eci_m
eci = Eci(cfg(f"eci.{region}.aliyuncs.com"))

existing = eci.describe_container_groups(eci_m.DescribeContainerGroupsRequest(
    region_id=region, container_group_name=group_name)).body.container_groups
if existing:
    print(f"deleting existing group {existing[0].container_group_id}...", file=sys.stderr)
    eci.delete_container_group(eci_m.DeleteContainerGroupRequest(
        region_id=region, container_group_id=existing[0].container_group_id))
    for _ in range(30):
        time.sleep(5)
        if not eci.describe_container_groups(eci_m.DescribeContainerGroupsRequest(
                region_id=region, container_group_name=group_name)).body.container_groups:
            break

backend_env = [
    {"Key": "APP_ENV", "Value": "production"},
    # The image contains only bundled demo frames; this simulator accepts the dev_judge_ device prefix only.
    {"Key": "DEMO_SIMULATION_ENABLED", "Value": "true"},
    # The web console should surface every demo severity, including low and medium.
    {"Key": "ALERT_MIN_SEVERITY", "Value": "low"},
    {"Key": "CORS_ALLOWED_ORIGINS", "Value": cors_origin},
    {"Key": "CORS_ALLOWED_ORIGIN_REGEX", "Value": ""},
    {"Key": "GOOGLE_SECRET_MANAGER_PROJECT", "Value": project_id},
    {
        "Key": "GOOGLE_SECRET_MANAGER_SECRETS",
        "Value": ",".join(expected_secret_names),
    },
    {
        "Key": "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64",
        "Value": reader_credential_b64,
    },
]

eip_id = os.environ.get("SE_EIP_ID", "")
if eip_id:
    for _ in range(30):
        eip = ecs.describe_eip_addresses(em.DescribeEipAddressesRequest(
            region_id=region, allocation_id=eip_id)).body.eip_addresses.eip_address[0]
        print(f"  waiting for EIP {eip_id}: status={eip.status}", file=sys.stderr)
        if eip.status == "Available":
            break
        time.sleep(5)
    else:
        sys.exit("standing EIP did not become Available after the previous ECI group was deleted")
eip_cfg = {"EipInstanceId": eip_id} if eip_id else {"AutoCreateEip": True, "EipBandwidth": 5}
req = eci_m.CreateContainerGroupRequest().from_map({
    "RegionId": region,
    "SecurityGroupId": sg_id,
    "VSwitchId": vswitch_id,
    "ContainerGroupName": group_name,
    "RestartPolicy": "Always",
    "Cpu": 1.0,
    "Memory": 2.0,
    **eip_cfg,
    "ImageRegistryCredential": [{
        "Server": vpc_registry,
        "UserName": acr_username,
        "Password": acr_password,
    }],
    "Volume": [{
        "Name": "caddy-config",
        "Type": "ConfigFileVolume",
        "ConfigFileVolume": {"ConfigFileToPath": [{"Path": "Caddyfile", "Content": caddy_b64}]},
    }],
    "Container": [
        {
            "Name": "backend",
            "Image": image,
            "Cpu": 0.75,
            "Memory": 1.5,
            "Port": [{"Port": 8000, "Protocol": "TCP"}],
            "EnvironmentVar": backend_env,
        },
        {
            "Name": "caddy",
            "Image": "caddy:2-alpine",
            "Cpu": 0.25,
            "Memory": 0.5,
            "Port": [
                {"Port": 80, "Protocol": "TCP"},
                {"Port": 443, "Protocol": "TCP"},
            ],
            "VolumeMount": [{"Name": "caddy-config", "MountPath": "/etc/caddy"}],
        },
    ],
})
group_id = eci.create_container_group(req).body.container_group_id
print(f"created container group {group_id}", file=sys.stderr)

eip = None
for _ in range(60):
    time.sleep(5)
    g = eci.describe_container_groups(eci_m.DescribeContainerGroupsRequest(
        region_id=region, container_group_ids=json.dumps([group_id]))).body.container_groups[0]
    eip = g.internet_ip or eip
    print(f"  status={g.status} ip={eip}", file=sys.stderr)
    if g.status == "Running" and eip:
        break
    if g.status in ("Failed", "Expired"):
        for c in g.containers:
            state = getattr(c, "current_state", None)
            print(f"  container {c.name}: {getattr(state, 'state', '?')} "
                  f"{getattr(state, 'detail_status', '')}", file=sys.stderr)
        sys.exit(f"container group ended in status {g.status}")
else:
    sys.exit("timed out waiting for the container group to run")

print(json.dumps({"groupId": group_id, "ip": eip}))
'@ | python - | Tee-Object -Variable EciOut
if ($LASTEXITCODE -ne 0) { Write-Error "ECI deployment failed." }
$Eci = ($EciOut | Select-Object -Last 1) | ConvertFrom-Json

Write-Host ""
if ($AllowInsecureHttp) {
    Write-Warning "Temporary HTTP-only deployment: authenticated browser sessions will not work until HTTPS is enabled."
    Write-Host "Deployed: http://$($Eci.ip)/" -ForegroundColor Yellow
}
else {
    Write-Host "Deployed: https://$Domain/  (app + API on one origin)" -ForegroundColor Green
}
if ($AllowInsecureHttp) {
    Write-Host "Health:   http://$($Eci.ip)/healthz" -ForegroundColor Yellow
}
else {
    Write-Host "Health:   https://$Domain/healthz" -ForegroundColor Green
}
