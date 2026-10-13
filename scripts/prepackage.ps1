$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& azd springboot configure --project-dir $root
if ($LASTEXITCODE -ne 0) { throw 'Spring Boot extension configuration failed; packaging cancelled.' }
& azd springboot build --project-dir $root
if ($LASTEXITCODE -ne 0) { throw 'Spring Boot extension build/publish failed; refusing to package a stale image.' }
