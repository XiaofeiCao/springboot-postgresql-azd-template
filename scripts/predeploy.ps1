$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    # Standalone deploy does not invoke project package hooks; run package explicitly before image resolution.
    & azd package --all
    if ($LASTEXITCODE -ne 0) { throw 'Spring Boot packaging failed; deployment cancelled.' }
} finally {
    Pop-Location
}
