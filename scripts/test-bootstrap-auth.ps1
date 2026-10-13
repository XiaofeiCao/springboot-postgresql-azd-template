$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'bootstrap-database.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Bootstrap script has PowerShell parse errors.' }
$definition = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-DatabaseAccessToken'
}, $true)
if ($null -eq $definition) { throw 'Token helper is missing.' }
. ([ScriptBlock]::Create($definition.Extent.Text))

$settings = @{
    AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
    AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
}
$script:tenant = $settings.AZURE_TENANT_ID
$script:tokenRequests = 0
$script:failure = ''
function az {
    $global:LASTEXITCODE = 0
    if ($args -notcontains '--subscription' -or $args -notcontains $settings.AZURE_SUBSCRIPTION_ID) {
        throw 'Missing explicit subscription.'
    }
    if ($args[1] -eq 'show') {
        if ($script:failure -eq 'account') { $global:LASTEXITCODE = 1; return }
        return $script:tenant
    }
    if ($args[1] -eq 'get-access-token') {
        if ($args -contains '--tenant') { throw 'CLI rejects simultaneous tenant and subscription.' }
        $script:tokenRequests++
        if ($script:failure -eq 'token') { $global:LASTEXITCODE = 1; return }
        if ($script:failure -eq 'empty') { return '' }
        return 'synthetic-test-token'
    }
    throw 'Unexpected Azure CLI invocation.'
}

if ((Get-DatabaseAccessToken -Settings $settings) -ne 'synthetic-test-token') {
    throw 'Token result was not returned.'
}
if ($script:tokenRequests -ne 1) { throw 'Expected exactly one token request.' }

foreach ($case in 'tenant', 'account', 'token', 'empty') {
    $script:tenant = if ($case -eq 'tenant') { 'wrong-tenant' } else { $settings.AZURE_TENANT_ID }
    $script:failure = $case
    $before = $script:tokenRequests
    $caught = $null
    try { $null = Get-DatabaseAccessToken -Settings $settings } catch { $caught = $_ }
    if ($null -eq $caught) { throw "Expected rejection for $case." }
    if ($caught.ToString().Contains('synthetic-test-token')) { throw 'Error disclosed a token.' }
    if ($case -in 'tenant', 'account' -and $script:tokenRequests -ne $before) {
        throw 'Token requested before verifying subscription tenant.'
    }
}
Write-Host 'Bootstrap authentication regression passed: valid context, tenant mismatch, account failure, token failure, empty token.'
