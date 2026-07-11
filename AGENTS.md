<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

## Deployment (Alibaba Cloud, ap-southeast-3 / Kuala Lumpur)

Two self-contained scripts, one per tier. Credentials come from `ALIBABA_CLOUD_ACCESS_KEY_ID/_SECRET` in the repo `.env`.

- **Frontend**: `./scripts/deployment/frontend.ps1` — Flutter web WASM build + upload to OSS bucket `erlang-vision` (creates bucket, disables Block Public Access, sets content types/cache headers). Needs Flutter ≥ 3.44 and `config/firebase.json`. Omit `-ApiBaseUrl`: release web builds default to same-origin (see below).
- **Backend**: `./scripts/deployment/backend.ps1 -Deploy` — docker build/smoke → push to ACR → ECI container group `erlang-backend` (FastAPI + Caddy sidecar) on the RDS vSwitch, with security group + RDS whitelist handled. Public entry is the standing EIP `erlang-eic-static-ip` (47.250.155.149), bound via `-EipId` so the IP survives group recreates.

Hard-won constraints (do not rediscover these):

- **OSS force-downloads HTML** on `*.aliyuncs.com` endpoints (`x-oss-force-download`) — no setting disables it. Browsers render the app only through the Caddy sidecar, which proxies the bucket over the region-internal endpoint and strips `Content-Disposition`, or through a bucket-bound custom domain. Never suggest an ALB in front of OSS (no OSS backend type; Host rewrite re-triggers the download).
- **ACR**: use the Personal Edition instance domain `crpi-9kvwsegbpo7ict75.ap-southeast-3.personal.cr.aliyuncs.com` (VPC pulls: insert `-vpc`). The legacy `registry-intl.<region>` domain 403s docker login for this account. Temp tokens come from the legacy 2016-06-07 `/tokens` ROA call — that SDK drops response bodies (`body_type='none'`), so use `call_api` with `body_type='json'` as in backend.ps1.
- **Spaced paths break Dart native-assets hooks** (`C:\Users\Kenneth Chua`): frontend.ps1 converts the SDK, pub cache, and project dir to 8.3 short paths before building. Flutter SDK lives at `C:\Users\Kenneth Chua\flutter` (not on PATH).
- **API base URL**: web release builds call the page origin (Caddy serves app + API on one host); dev builds default to `localhost:8000` (`10.0.2.2` on Android emulator). An explicit `--dart-define=ERLANG_API_BASE_URL` always wins; mobile builds must pass it.
- Backend DB switching (SQLite local vs RDS via KMS) is documented in `.env.example`; the KMS master switch is `ALICLOUD_KMS_SECRET_NAME`.
