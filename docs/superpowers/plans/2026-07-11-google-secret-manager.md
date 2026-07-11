# Google Secret Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Alibaba KMS startup loading with two scoped Google Secret Manager secrets while keeping the reader key outside the public repository.

**Architecture:** A focused backend loader decodes an ECI-injected Base64 service-account document in memory, retrieves `erlang-prod-secrets` then `erlang-db-secrets`, merges their JSON objects, and reuses the existing environment-application behavior. The local deployment script reads the key file outside the repository and transports only its Base64 representation to ECI.

**Tech Stack:** Python 3, pytest, Google Cloud Secret Manager Python client, PowerShell, Alibaba ECI SDK, Flutter release build inspection.

## Global Constraints

- Never read `erlang-db-super-secrets` from the application runtime.
- Never commit or copy a service-account key or plaintext secret into the repository, Docker image, or Flutter build.
- Preserve an explicitly configured local `DATABASE_URL`.
- Fail production startup on partial Google configuration or retrieval errors without logging sensitive values.
- Retain Alibaba KMS only as an explicitly configured migration fallback.

---

### Task 1: Test and implement the backend Google secret loader

**Files:**
- Create: `backend/app/core/google_secrets.py`
- Create: `backend/tests/test_google_secrets.py`
- Modify: `backend/app/core/alicloud_secrets.py`
- Modify: `backend/app/core/config.py`
- Modify: `backend/requirements.txt`

**Interfaces:**
- Consumes: `_read_dotenv_key(Path, str)`, `_parse_secret_data(str)`, and `_apply_secret_values(dict)` from the existing secret helper.
- Produces: `load_google_secret_manager_secrets(env_file: Path, client_factory: Callable | None = None) -> bool`; returns `False` when unconfigured and `True` after successful Google loading.

- [ ] **Step 1: Write failing loader tests**

Add tests that isolate `os.environ`, supply a fake client factory, and assert no-op behavior, ordered resource names, later-secret overrides, explicit `DATABASE_URL` preservation, credential removal, malformed Base64/JSON rejection, non-object payload rejection, and sanitized retrieval errors.

- [ ] **Step 2: Run the new tests and verify RED**

Run: `.venv\Scripts\python.exe -m pytest backend/tests/test_google_secrets.py -q`

Expected: collection/import failure because `app.core.google_secrets` does not exist.

- [ ] **Step 3: Implement the minimal loader and shared generic parsing**

Create a loader that reads `GOOGLE_SECRET_MANAGER_PROJECT`, `GOOGLE_SECRET_MANAGER_SECRETS`, and `GOOGLE_SECRET_MANAGER_CREDENTIALS_B64`; requires all three when any is present; decodes credentials; constructs `service_account.Credentials`; calls `projects/{project}/secrets/{name}/versions/latest`; merges JSON objects; removes the bootstrap credential from `os.environ` in `finally`; and applies values only after all reads succeed. Generalize secret-payload error wording so the shared parser is provider-neutral.

- [ ] **Step 4: Integrate startup precedence and dependency**

In `config.py`, call the Google loader first and invoke Alibaba KMS only when Google is unconfigured. Add a pinned compatible `google-cloud-secret-manager` dependency to `backend/requirements.txt`.

- [ ] **Step 5: Run focused and configuration tests**

Run: `.venv\Scripts\python.exe -m pytest backend/tests/test_google_secrets.py -q`

Expected: all tests pass with no credential or secret value in output.

### Task 2: Test and implement safe ECI credential transport

**Files:**
- Create: `scripts/deployment/tests/backend_secret_transport.Tests.ps1`
- Modify: `scripts/deployment/backend.ps1`
- Modify: `.env.example`

**Interfaces:**
- Consumes: local `GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE` path and the project/secret-name settings.
- Produces: ECI variables `GOOGLE_SECRET_MANAGER_PROJECT`, `GOOGLE_SECRET_MANAGER_SECRETS`, and `GOOGLE_SECRET_MANAGER_CREDENTIALS_B64`.

- [ ] **Step 1: Write failing deployment-source tests**

Add Pester assertions that the script requires an existing reader-key file for deployment, encodes file bytes, sends exactly the two Google secret names, does not send the local path, and no longer passes Alibaba KMS secret names or Alibaba access keys into the backend container solely for secret loading.

- [ ] **Step 2: Run the deployment test and verify RED**

Run: `Invoke-Pester scripts/deployment/tests/backend_secret_transport.Tests.ps1 -Output Detailed`

Expected: assertions fail because Google transport is absent.

- [ ] **Step 3: Implement deployment preflight and transport**

Read `.env`, resolve and validate the external JSON path, parse it as JSON, Base64-encode its UTF-8 bytes, store it only in the deployment process environment, and build the ECI environment list from the Google project, the fixed runtime secret list, and the encoded credential. Clear the temporary PowerShell/process variables after deployment in a `finally` block.

- [ ] **Step 4: Document local configuration**

Replace the primary KMS example in `.env.example` with Google variables and comments that the JSON file stays outside Git. Retain a clearly labeled temporary Alibaba KMS fallback section if compatibility remains.

- [ ] **Step 5: Run deployment-source tests**

Run: `Invoke-Pester scripts/deployment/tests/backend_secret_transport.Tests.ps1 -Output Detailed`

Expected: all assertions pass. If Pester is unavailable, run PowerShell parser validation and explicit `Select-String` assertions for the same invariants, and report that limitation.

### Task 3: Verify backend, container, and Flutter secret boundaries

**Files:**
- Modify only if verification reveals a defect in files already in scope.

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: evidence that tests/builds pass and no backend credential is compiled into Flutter output.

- [ ] **Step 1: Run the full backend test suite**

Run: `.venv\Scripts\python.exe -m pytest backend/tests -q`

Expected: zero failures.

- [ ] **Step 2: Validate the deployment script syntax**

Run PowerShell parser validation against `scripts/deployment/backend.ps1`.

Expected: zero parse errors.

- [ ] **Step 3: Build the backend image and run its offline smoke test**

Run: `./scripts/deployment/backend.ps1`

Expected: Docker build succeeds and `/healthz` returns HTTP 200 with `APP_ENV=test`.

- [ ] **Step 4: Inspect Flutter sources and available release output**

Run: `rg -n "PRIVATE KEY|RDS_PASSWORD|SESSION_SECRET_KEY|QWEN_API_KEY|GOOGLE_SECRET_MANAGER_CREDENTIALS" frontend/sentineledge_app/lib frontend/sentineledge_app/build/web`

Expected: no embedded secret values; references in documentation/comments are reviewed separately. If no current release output exists, build Flutter web using the configured deployment flow before scanning.

- [ ] **Step 5: Review the final diff without disturbing unrelated work**

Run: `git diff --check` and `git diff -- backend/app/core backend/tests/test_google_secrets.py backend/requirements.txt scripts/deployment/backend.ps1 scripts/deployment/tests .env.example`

Expected: no whitespace errors and only scoped changes layered on the user's existing dirty worktree.
