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
    [string]$Bucket = "erlang-vision",
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
# an auto-created EIP. Caddy routes /api + /healthz to FastAPI and reverse-
# proxies everything else to the OSS web bucket over the region-internal
# endpoint, stripping the forced-download headers so browsers render the SPA.
# Registry: ACR Personal Edition (activate once from the ROOT account in the
# console; RAM users cannot). Login uses a temporary API-minted token that
# lives only inside this process — no registry password needed here.
if (-not $Deploy) { return }

if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
    Write-Error "python was not found on PATH (needed for the ACR/ECI API calls)."
}
python -c "import alibabacloud_eci20180808, alibabacloud_rds20140815, alibabacloud_ecs20140526, alibabacloud_cr20160607" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Alibaba Cloud SDKs..." -ForegroundColor Cyan
    python -m pip install --quiet alibabacloud_eci20180808 alibabacloud_rds20140815 alibabacloud_ecs20140526 alibabacloud_cr20160607 alibabacloud_tea_openapi
    if ($LASTEXITCODE -ne 0) { Write-Error "pip install of Alibaba Cloud SDKs failed." }
}

$env:SE_REPO_ROOT = $RepoRoot
$env:SE_REGION = $Region
$env:SE_IMAGE_NAME = $Name
$env:SE_IMAGE_TAG = $Tag
$env:SE_BUCKET = $Bucket
$env:SE_GROUP_NAME = $GroupName
$env:SE_ACR_NAMESPACE = $AcrNamespace
$env:SE_ACR_DOMAIN = $AcrDomain

# Single phase: mint ACR token, docker push, then provision ECI. All in one
# python process so the token never crosses a process boundary or hits disk.
Write-Host "Pushing to ACR and provisioning ECI ($GroupName)..." -ForegroundColor Cyan
@'
import base64, json, os, subprocess, sys, time
from pathlib import Path
from alibabacloud_tea_openapi import models as om
from alibabacloud_tea_util import models as util_models

repo_root = Path(os.environ["SE_REPO_ROOT"])
region = os.environ["SE_REGION"]
bucket = os.environ["SE_BUCKET"]
group_name = os.environ["SE_GROUP_NAME"]
acr_namespace = os.environ["SE_ACR_NAMESPACE"]
image_name = os.environ["SE_IMAGE_NAME"]
image_tag = os.environ["SE_IMAGE_TAG"]

for line in (repo_root / ".env").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip())
AK = os.environ["ALIBABA_CLOUD_ACCESS_KEY_ID"]
SK = os.environ["ALIBABA_CLOUD_ACCESS_KEY_SECRET"]

def cfg(endpoint):
    return om.Config(access_key_id=AK, access_key_secret=SK, endpoint=endpoint, region_id=region)

# --- ACR: ensure namespace/repo, mint temp token, docker push ---------------
# The 2016-06-07 SDK declares body_type='none' on most calls and silently
# drops response bodies, so talk to the ROA API through call_api directly.
from alibabacloud_cr20160607.client import Client as Cr
cr = Cr(cfg(f"cr.{region}.aliyuncs.com"))

def roa(action, method, pathname, body=None):
    req = om.OpenApiRequest(headers={}, body=json.dumps(body) if body else None)
    params = om.Params(action=action, version="2016-06-07", protocol="HTTPS",
                       pathname=pathname, method=method, auth_type="AK", style="ROA",
                       req_body_type="json", body_type="json")
    return cr.call_api(params, req, util_models.RuntimeOptions())

try:
    roa("GetNamespace", "GET", f"/namespace/{acr_namespace}")
except Exception as exc:
    if "USER_NOT_REGISTERED" in str(exc):
        sys.exit("Container Registry Personal Edition is not activated. One-time step "
                 "from the ROOT account: console > Container Registry > Personal Edition "
                 f"> region {region} > activate and set a registry password. Then rerun.")
    if "NAMESPACE_NOT_EXIST" not in str(exc):
        raise
    roa("CreateNamespace", "PUT", "/namespace", {"Namespace": {"Namespace": acr_namespace}})
    print(f"created ACR namespace {acr_namespace}", file=sys.stderr)

try:
    roa("GetRepo", "GET", f"/repos/{acr_namespace}/{image_name}")
except Exception as exc:
    if "REPO_NOT_EXIST" not in str(exc):
        raise
    roa("CreateRepo", "PUT", "/repos", {"Repo": {
        "RepoNamespace": acr_namespace, "RepoName": image_name,
        "RepoType": "PRIVATE", "Summary": "SentinelEdge FastAPI backend"}})
    print(f"created ACR repo {acr_namespace}/{image_name} (private)", file=sys.stderr)

token_data = roa("GetAuthorizationToken", "GET", "/tokens")["body"]["data"]
# Personal Edition instances use instance-specific domains; the legacy
# registry-intl.<region> shared domain 403s docker logins for these accounts.
registry = os.environ["SE_ACR_DOMAIN"]
_head, _tail = registry.split(".", 1)
vpc_registry = f"{_head}-vpc.{_tail}"
image = f"{vpc_registry}/{acr_namespace}/{image_name}:{image_tag}"
push_image = f"{registry}/{acr_namespace}/{image_name}:{image_tag}"

def run(cmd, **kw):
    proc = subprocess.run(cmd, **kw)
    if proc.returncode != 0:
        sys.exit(f"command failed: {cmd[0]} {cmd[1] if len(cmd) > 1 else ''}")

print(f"docker push {push_image}", file=sys.stderr)
run(["docker", "login", registry, "--username", token_data["tempUserName"], "--password-stdin"],
    input=token_data["authorizationToken"].encode())
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
        description="SentinelEdge backend ECI: HTTP in")).body.security_group_id
    for port in ("80/80", "443/443"):
        ecs.authorize_security_group(em.AuthorizeSecurityGroupRequest(
            region_id=region, security_group_id=sg_id, ip_protocol="tcp",
            port_range=port, source_cidr_ip="0.0.0.0/0"))
print(f"security group: {sg_id}", file=sys.stderr)

# --- RDS whitelist: dedicated array for the ECI subnet ----------------------
rds.modify_security_ips(rm.ModifySecurityIpsRequest(
    dbinstance_id=db.dbinstance_id, security_ips=vsw.cidr_block,
    dbinstance_iparray_name="eci", modify_mode="Cover"))
print(f"RDS whitelist 'eci' = {vsw.cidr_block}", file=sys.stderr)

# --- Caddy config ------------------------------------------------------------
oss_internal = f"{bucket}.oss-{region}-internal.aliyuncs.com"
caddyfile = f"""
:80 {{
	@backend path /api/* /healthz /docs /docs/* /openapi.json
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

backend_env = [{"Key": k, "Value": os.environ.get(k, "")} for k in (
    "ALICLOUD_KMS_SECRET_NAME", "ALICLOUD_REGION_ID",
    "ALIBABA_CLOUD_ACCESS_KEY_ID", "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
)] + [{"Key": "APP_ENV", "Value": "production"}]

req = eci_m.CreateContainerGroupRequest().from_map({
    "RegionId": region,
    "SecurityGroupId": sg_id,
    "VSwitchId": vswitch_id,
    "ContainerGroupName": group_name,
    "RestartPolicy": "Always",
    "Cpu": 1.0,
    "Memory": 2.0,
    "AutoCreateEip": True,
    "EipBandwidth": 5,
    "ImageRegistryCredential": [{
        "Server": vpc_registry,
        "UserName": token_data["tempUserName"],
        "Password": token_data["authorizationToken"],
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
            "Port": [{"Port": 80, "Protocol": "TCP"}],
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
Write-Host "Deployed: http://$($Eci.ip)/  (app + API on one origin)" -ForegroundColor Green
Write-Host "Health:   http://$($Eci.ip)/healthz" -ForegroundColor Green
