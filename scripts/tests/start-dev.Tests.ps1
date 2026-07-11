$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$scriptPath = Join-Path $repoRoot "scripts/start-dev.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
$frontendDeploySource = Get-Content -Raw -LiteralPath (
    Join-Path $repoRoot "scripts/deployment/frontend.ps1"
)

Describe "start-dev Flutter project path" {
    It "targets the existing Flutter project" {
        $source | Should Match 'frontend/sentineledge_app'
        Test-Path (Join-Path $repoRoot "frontend/sentineledge_app/pubspec.yaml") |
            Should Be $true
        Test-Path (Join-Path $repoRoot "frontend/sentineledge_app/config/firebase.json") |
            Should Be $true
    }

    It "uses the same Flutter project for frontend deployment" {
        $frontendDeploySource | Should Match 'frontend/sentineledge_app'
        $frontendDeploySource | Should Not Match 'frontend/erlang_ai_vision_app'
    }
}
