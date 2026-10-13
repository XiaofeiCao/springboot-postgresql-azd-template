$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'bootstrap-database.ps1') -ProjectDir $root
& azd springboot configure --project-dir $root
if ($LASTEXITCODE -ne 0) { throw 'Spring Boot extension configuration failed.' }
