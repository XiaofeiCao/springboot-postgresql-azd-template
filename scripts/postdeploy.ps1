$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& azd springboot apply --project-dir $root
if ($LASTEXITCODE -ne 0) { throw 'Spring Boot extension runtime configuration failed.' }
& (Join-Path $PSScriptRoot 'wait-readiness.ps1') -ProjectDir $root
