param(
    [Parameter(Mandatory)][string] $ExtensionPath,
    [Parameter(Mandatory)][string] $ConfigDir,
    [string] $AzdPath = 'azd'
)

$ErrorActionPreference = 'Stop'
$ExtensionPath = (Resolve-Path -LiteralPath $ExtensionPath).Path
$ConfigDir = [IO.Path]::GetFullPath($ConfigDir)
$dist = Join-Path $ExtensionPath 'dist'
$os = (& go env GOOS).Trim()
$arch = (& go env GOARCH).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to detect the Go target.' }
$entry = if ($os -eq 'windows') { 'springboot.exe' } else { 'springboot' }
New-Item -ItemType Directory -Force -Path $dist, $ConfigDir | Out-Null
$binary = Join-Path $dist $entry
Push-Location $ExtensionPath
try {
    & go build -trimpath -o $binary .
    if ($LASTEXITCODE -ne 0) { throw 'Extension build failed.' }
} finally { Pop-Location }

$registry = @{
    schemaVersion = '1.0'
    extensions = @(@{
        id = 'azure.springboot'
        namespace = 'springboot'
        displayName = 'Spring Boot prototype'
        description = 'Buildpack containerization and passwordless PostgreSQL configuration for the prepared sample.'
        versions = @(@{
            version = '0.0.1'
            requiredAzdVersion = '>=1.35.1'
            capabilities = @('custom-commands', 'metadata')
            usage = 'azd springboot <command> [options]'
            entryPoint = $entry
            artifacts = @{
                "$os/$arch" = @{
                    url = $binary
                    checksum = @{
                        algorithm = 'sha256'
                        value = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
                    }
                }
            }
        })
    })
}
$registryPath = Join-Path $dist 'registry.json'
$registry | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $registryPath -Encoding utf8

$previousConfig = $env:AZD_CONFIG_DIR
$previousTelemetry = $env:AZURE_DEV_COLLECT_TELEMETRY
$previousCacheTtl = $env:AZD_EXTENSION_CACHE_TTL
try {
    $env:AZD_CONFIG_DIR = $ConfigDir
    $env:AZURE_DEV_COLLECT_TELEMETRY = 'no'
    $env:AZD_EXTENSION_CACHE_TTL = '0s'
    $sourcesJson = & $AzdPath extension source list --output json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect configured extension sources.' }
    $existing = @($sourcesJson | ConvertFrom-Json) | Where-Object name -eq 'springboot-local'
    if ($existing) {
        if ($existing.type -ne 'file' -or $existing.location -ne $registryPath) {
            throw 'springboot-local already points to a different source. Use a dedicated ConfigDir.'
        }
    } else {
        & $AzdPath extension source add --name springboot-local --type file --location $registryPath --no-prompt
        if ($LASTEXITCODE -ne 0) { throw 'Local registry registration failed.' }
    }
    & $AzdPath extension install azure.springboot --source springboot-local --version 0.0.1 --force --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Local extension installation failed.' }
    & $AzdPath springboot version
    if ($LASTEXITCODE -ne 0) { throw 'Installed extension did not execute.' }
} finally {
    $env:AZD_CONFIG_DIR = $previousConfig
    $env:AZURE_DEV_COLLECT_TELEMETRY = $previousTelemetry
    $env:AZD_EXTENSION_CACHE_TTL = $previousCacheTtl
}
Write-Host "Local extension installed. Use AZD_CONFIG_DIR=$ConfigDir for subsequent azd commands."
