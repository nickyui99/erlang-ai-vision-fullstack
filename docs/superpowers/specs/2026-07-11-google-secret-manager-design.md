# Google Secret Manager startup integration

## Objective

Replace the deleted Alibaba KMS startup-secret lookup with Google Cloud Secret
Manager while retaining the existing local PowerShell deployment workflow. The
public repository must not contain a Google service-account private key or any
decrypted application secret.

## Secret scope

The production backend reads these secrets, in order:

1. `erlang-prod-secrets`
2. `erlang-db-secrets`

Values from `erlang-db-secrets` override matching values from
`erlang-prod-secrets`. The backend does not read or receive access to
`erlang-db-super-secrets`; database administration remains separate from the
application runtime.

Each Google secret contains a JSON object. The combined values continue to use
the existing configuration names such as `DATABASE_URL`, `RDS_HOST`,
`RDS_USER`, `RDS_PASSWORD`, `SESSION_SECRET_KEY`, `QWEN_API_KEY`, and
`GOOGLE_APPLICATION_CREDENTIALS_JSON`.

## Bootstrap credential

The Google Secret Manager reader service-account JSON stays outside the
repository, for example at:

`C:\Users\nicho\.secrets\sentineledge-eci-secret-reader.json`

The repository `.env` contains only the local file path. During deployment,
`scripts/deployment/backend.ps1` validates the JSON file, Base64-encodes its
bytes, and supplies the result to the backend container as
`GOOGLE_SECRET_MANAGER_CREDENTIALS_B64`. Base64 is transport encoding, not
encryption; access to ECI configuration must therefore be restricted through
Alibaba RAM.

The reader account receives `roles/secretmanager.secretAccessor` only on the
two runtime secrets. It receives no project-wide administrator role and no
access to the superuser secret.

## Runtime flow

Before application settings are instantiated, a focused Google Secret Manager
loader:

1. Detects whether Google Secret Manager configuration is present.
2. Decodes and parses the Base64 service-account credential in memory.
3. Creates a Secret Manager client without writing the reader key to disk.
4. Reads the latest enabled version of both configured secrets.
5. Parses each payload as a JSON object and merges them in configured order.
6. Applies the values through the existing secret-application helpers,
   including RDS URL construction and Firebase credential-file handling.

An explicitly configured local `DATABASE_URL` continues to win, preventing
tests and local tools from being redirected to production RDS. The application
must not print secret payloads or credential contents.

## Configuration behavior

Production configuration uses:

```dotenv
GOOGLE_SECRET_MANAGER_PROJECT=sentineledge-e069b
GOOGLE_SECRET_MANAGER_SECRETS=erlang-prod-secrets,erlang-db-secrets
GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE=C:\Users\nicho\.secrets\sentineledge-eci-secret-reader.json
```

`GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE` is consumed by the deployment script
and is not passed into ECI. `GOOGLE_SECRET_MANAGER_CREDENTIALS_B64` is generated
by that script and consumed by the backend.

Local development remains unchanged when Google Secret Manager variables are
absent. If Google configuration is partially present or a configured retrieval
fails, production startup fails clearly instead of silently falling back to
insecure or stale values.

Alibaba KMS compatibility can remain temporarily available only when its
existing configuration is explicitly present. Google Secret Manager takes
precedence when configured, allowing a controlled migration without breaking
unrelated local environments.

## Error handling

Startup reports actionable, non-sensitive errors for:

- incomplete Google Secret Manager configuration;
- invalid Base64 or malformed service-account JSON;
- malformed secret JSON or a non-object payload;
- authentication, authorization, network, or missing-secret failures.

Errors identify the secret name where useful but never include a secret value,
private key, access token, or full credential document.

## Testing and verification

Unit tests use an injected/fake Secret Manager client and cover:

- no-op behavior when Google configuration is absent;
- retrieval of exactly the two configured secrets in order;
- later-secret override behavior;
- preservation of an explicit local `DATABASE_URL`;
- malformed credentials and secret payloads;
- propagation of access failures without secret leakage;
- exclusion of `erlang-db-super-secrets` from default configuration.

Deployment-script checks cover missing credential files and confirm that only
the Base64 transport variable, project ID, and two runtime secret names are
sent to ECI. Backend unit tests and an appropriate Docker/build validation are
run before completion is reported.
