param([Parameter(Mandatory)][string]$Stage)

$ErrorActionPreference = 'Stop'
if ($env:SPRINGBOOT_IMAGE -ne $env:LIFECYCLE_EXPECTED_IMAGE) {
    throw "$Stage received a stale image: environment refresh did not occur."
}
@{
    stage = $Stage
    observedImage = $env:SPRINGBOOT_IMAGE
} | ConvertTo-Json -Compress | Add-Content (Join-Path $PSScriptRoot 'trace.jsonl')
