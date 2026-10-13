$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$state = @{
    Endpoint = 'https://notes-test.example.azurecontainerapps.io'
    Requests = 0
    ReadyAfter = 1
    Calls = [System.Collections.Generic.List[string]]::new()
}
Set-Item Function:azd -Value {
    $state.Calls.Add(($args -join ' '))
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'env') {
        @{ SERVICE_API_ENDPOINT_URL = $state.Endpoint } | ConvertTo-Json -Compress
    }
}.GetNewClosure()
Set-Item Function:Invoke-RestMethod -Value {
    param([uri]$Uri, [string]$Method, [int]$TimeoutSec)
    if ($Uri.AbsolutePath -ne '/actuator/health/readiness' -or $Method -ne 'Get' -or $TimeoutSec -lt 1) {
        throw 'Incorrect readiness request contract.'
    }
    $state.Requests++
    @{ status = $(if ($state.Requests -ge $state.ReadyAfter) { 'UP' } else { 'DOWN' }) }
}.GetNewClosure()

& (Join-Path $PSScriptRoot 'postdeploy.ps1')
if ($state.Calls[0] -notlike 'springboot apply --project-dir *' -or $state.Requests -ne 1) {
    throw 'postdeploy must apply configuration before checking readiness.'
}
$state.Requests = 0
$state.ReadyAfter = 2
& (Join-Path $PSScriptRoot 'wait-readiness.ps1') -ProjectDir $root -TimeoutSeconds 5 -IntervalSeconds 1
if ($state.Requests -ne 2) { throw 'A transient DOWN response was not retried.' }

$state.Requests = 0
$state.ReadyAfter = [int]::MaxValue
$failed = $false
try {
    & (Join-Path $PSScriptRoot 'wait-readiness.ps1') -ProjectDir $root -TimeoutSeconds 1 -IntervalSeconds 1
} catch {
    if ($_ -notmatch 'readiness did not become UP') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Readiness timeout must fail deployment.' }

foreach ($endpoint in @(
    'https://user:DO-NOT-DISCLOSE@notes-test.example.azurecontainerapps.io',
    'https://notes-test.example.azurecontainerapps.io/?sig=DO-NOT-DISCLOSE',
    'http://notes-test.example.azurecontainerapps.io',
    'https://unrelated.invalid'
)) {
    $state.Endpoint = $endpoint
    $state.Requests = 0
    $failed = $false
    try {
        & (Join-Path $PSScriptRoot 'wait-readiness.ps1') -ProjectDir $root -TimeoutSeconds 1
    } catch {
        if ($_ -notmatch 'credential-free HTTPS Azure Container Apps endpoint' -or $_ -match 'DO-NOT-DISCLOSE') { throw }
        $failed = $true
    }
    if (-not $failed -or $state.Requests -ne 0) { throw 'Unsafe endpoint reached the HTTP client.' }
}
Write-Host 'PASS: apply precedes readiness; UP succeeds; transient DOWN retries; timeout fails; unsafe URLs rejected without disclosure.'
Write-Host 'Azure CLI and HTTP were mocked; no Azure operation or network request occurred.'
