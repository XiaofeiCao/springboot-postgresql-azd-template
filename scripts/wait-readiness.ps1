param(
    [string]$ProjectDir = (Split-Path $PSScriptRoot -Parent),
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 300,
    [ValidateRange(1, 60)][int]$IntervalSeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $ProjectDir
try {
    $values = & azd env get-values --output json
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the selected azd environment for readiness checking.' }
    $settings = ($values -join "`n") | ConvertFrom-Json -AsHashtable
    if (-not $settings.ContainsKey('SERVICE_API_ENDPOINT_URL')) {
        throw 'SERVICE_API_ENDPOINT_URL is missing; deploy the API before checking readiness.'
    }
    $endpoint = $null
    if (-not [uri]::TryCreate($settings.SERVICE_API_ENDPOINT_URL, [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -ne 'https' -or $endpoint.DnsSafeHost -notmatch '^[a-z0-9.-]+\.azurecontainerapps\.io$' -or
        $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment -or $endpoint.AbsolutePath -ne '/') {
        throw 'SERVICE_API_ENDPOINT_URL must be a credential-free HTTPS Azure Container Apps endpoint.'
    }
    $readinessUri = [uri]::new($endpoint, '/actuator/health/readiness')
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $remaining = [int][Math]::Ceiling($TimeoutSeconds - $timer.Elapsed.TotalSeconds)
        try {
            $health = Invoke-RestMethod -Uri $readinessUri -Method Get -TimeoutSec ([Math]::Min(10, $remaining))
            if ($health.status -eq 'UP') {
                Write-Host 'Container App database-backed readiness is UP after extension configuration.'
                return
            }
        } catch {
            # A new revision can be unavailable during startup; never forward raw request diagnostics.
        }
        $remaining = [int][Math]::Ceiling($TimeoutSeconds - $timer.Elapsed.TotalSeconds)
        if ($remaining -gt 0) { Start-Sleep -Seconds ([Math]::Min($IntervalSeconds, $remaining)) }
    }
    throw "Container App readiness did not become UP within $TimeoutSeconds seconds. Inspect the selected app's revision, database bootstrap, managed identity, and CA trust configuration."
} finally {
    Pop-Location
}
