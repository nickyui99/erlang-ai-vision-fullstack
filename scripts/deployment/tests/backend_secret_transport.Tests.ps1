$scriptPath = Join-Path $PSScriptRoot "../backend.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath

Describe "backend Google Secret Manager transport" {
    It "reads and validates an external service-account file" {
        $source | Should Match 'GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE'
        $source | Should Match 'credential_path\.read_bytes\(\)'
        $source | Should Match 'json\.loads\(credential_bytes\.decode\("utf-8"\)\)'
    }

    It "transports the reader credential as Base64" {
        $source | Should Match 'GOOGLE_SECRET_MANAGER_CREDENTIALS_B64'
        $source | Should Match 'base64\.b64encode\(credential_bytes\)'
    }

    It "allows only the two runtime secret names" {
        $source | Should Match 'erlang-prod-secrets'
        $source | Should Match 'erlang-db-secrets'
        $source | Should Not Match 'erlang-db-super-secrets'
    }

    It "does not pass Alibaba KMS credentials into the backend container" {
        $backendEnvBlock = [regex]::Match(
            $source,
            'backend_env\s*=.*?\n\s*eip_id',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        ).Value
        $backendEnvBlock | Should Not Match 'ALICLOUD_KMS_SECRET_NAME'
        $backendEnvBlock | Should Not Match 'ALIBABA_CLOUD_ACCESS_KEY_ID'
        $backendEnvBlock | Should Not Match 'ALIBABA_CLOUD_ACCESS_KEY_SECRET'
        $backendEnvBlock | Should Not Match 'GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE'
    }
}
