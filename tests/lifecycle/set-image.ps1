$ErrorActionPreference = 'Stop'
if ($env:SPRINGBOOT_IMAGE -eq $env:LIFECYCLE_EXPECTED_IMAGE) {
    throw 'The first project hook must start with the old image, not the expected replacement.'
}
@{
    stage = 'first-project-prepackage'
    observedImage = $env:SPRINGBOOT_IMAGE
    replacementImage = $env:LIFECYCLE_EXPECTED_IMAGE
} | ConvertTo-Json -Compress | Add-Content (Join-Path $PSScriptRoot 'trace.jsonl')
& $env:LIFECYCLE_AZD_PATH env set SPRINGBOOT_IMAGE $env:LIFECYCLE_EXPECTED_IMAGE --no-prompt
if ($LASTEXITCODE -ne 0) { throw 'The hook could not save the replacement image.' }
