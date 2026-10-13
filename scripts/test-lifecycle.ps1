param(
    [Parameter(Mandatory)][string]$AzdPath,
    [string]$EvidenceDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AzdPath = (Resolve-Path -LiteralPath $AzdPath).Path
$root = Split-Path $PSScriptRoot -Parent
$id = [guid]::NewGuid().ToString('N').Substring(0, 12)
if (-not $EvidenceDir) { $EvidenceDir = Join-Path (Join-Path $root '.springboot') "lifecycle-$id" }
if (Test-Path -LiteralPath $EvidenceDir) { throw 'EvidenceDir must not exist; this test never overwrites an existing workspace.' }
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$EvidenceDir = (Resolve-Path -LiteralPath $EvidenceDir).Path
Copy-Item (Join-Path (Join-Path $root 'tests') 'lifecycle\*') $EvidenceDir

$saved = @{}
foreach ($key in @('AZD_CONFIG_DIR', 'AZURE_DEV_COLLECT_TELEMETRY', 'LIFECYCLE_AZD_PATH', 'LIFECYCLE_EXPECTED_IMAGE')) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
Push-Location $EvidenceDir
try {
    $env:AZD_CONFIG_DIR = Join-Path $EvidenceDir '.config'
    $env:AZURE_DEV_COLLECT_TELEMETRY = 'no'
    $env:LIFECYCLE_AZD_PATH = $AzdPath
    $env:LIFECYCLE_EXPECTED_IMAGE = "registry.invalid/lifecycle-proof:replacement-$id"
    # Sentinel references prove host lifecycle state, not image existence or extension containerization.
    $initialImage = "registry.invalid/lifecycle-proof:initial-$id"
    & $AzdPath env new lifecycle --subscription '11111111-1111-1111-1111-111111111111' --location eastus --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize an offline lifecycle environment.' }
    & $AzdPath env set SPRINGBOOT_IMAGE $initialImage --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Could not seed the initial sentinel image.' }
    $packageJson = & $AzdPath package --all --output json --no-prompt 2> (Join-Path $EvidenceDir 'package.stderr.log')
    if ($LASTEXITCODE -ne 0) { throw "Offline package failed; see $EvidenceDir." }
    ($packageJson -join "`n") | Set-Content (Join-Path $EvidenceDir 'package.json')
    if (($packageJson -join "`n") -notmatch [regex]::Escape($env:LIFECYCLE_EXPECTED_IMAGE)) {
        throw 'The package artifact did not contain the replacement sentinel reference.'
    }
    if (($packageJson -join "`n") -match [regex]::Escape($initialImage)) {
        throw 'The package artifact incorrectly retained the old sentinel reference.'
    }
    $trace = @(Get-Content (Join-Path $EvidenceDir 'trace.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    $expectedStages = @('first-project-prepackage', 'second-project-prepackage', 'service-prepackage', 'project-postpackage')
    if (($trace.stage -join ',') -cne ($expectedStages -join ',')) {
        throw "Unexpected hook order: $($trace.stage -join ',')."
    }
    Write-Host "PASS: azd 1.35.1 project-hook environment refresh precedes Java/Container Apps image-passthrough package consumption."
    Write-Host "Evidence: $EvidenceDir"
    Write-Host 'Sentinel-only lifecycle proof: no images were built/pulled/pushed, no Azure commands ran, and no extension-image acceptance is claimed.'
} finally {
    Pop-Location
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
