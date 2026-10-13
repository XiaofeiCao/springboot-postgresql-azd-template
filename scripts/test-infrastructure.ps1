param([string]$BicepPath = 'bicep')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$container = "notes-bootstrap-test-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
$containerStarted = $false
$invalidCertificate = $null

function Invoke-TestSql {
    param([string]$Database, [string]$Sql, [string]$ObjectId = '11111111-1111-1111-1111-111111111111')
    $result = $Sql | & docker exec -i $container psql -X -U postgres -d $Database `
        --set=ON_ERROR_STOP=1 --set=app_role=notes_test_app "--set=app_oid=$ObjectId" `
        --set=app_database=notes --set=developer_role=notes_test_developer 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Local SQL validation failed: $($result -join "`n")" }
}

foreach ($name in @('main', 'api')) {
    & $BicepPath build (Join-Path (Join-Path $root 'infra') "$name.bicep") --stdout > $null
    if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed: $name" }
}
Get-ChildItem $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors) { throw "PowerShell syntax errors in $($_.Name): $errors" }
}
Get-ChildItem (Join-Path $root 'infra') -Filter '*.parameters.json' | ForEach-Object {
    $parameters = Get-Content $_.FullName -Raw | ConvertFrom-Json -AsHashtable
    foreach ($value in $parameters.parameters.Values) {
        if (-not $value.ContainsKey('value')) { throw "Parameters must use nested value shape: $($_.Name)" }
    }
}

$testState = @{ Settings = @{
    POSTGRES_ADMIN_OBJECT_ID = '11111111-1111-1111-1111-111111111111'
    POSTGRES_ADMIN_USERNAME = 'developer@example.invalid'
    DEVELOPER_IPV4 = '203.0.113.10'
    DEVELOPER_IPV4_SECONDARY = '203.0.113.11'
    ALLOW_AZURE_SERVICES = 'true'
}; Token = 'DO-NOT-DISCLOSE-test-token' }
Set-Item Function:azd -Value {
    $global:LASTEXITCODE = 0
    $testState.Settings | ConvertTo-Json
}.GetNewClosure()
& (Join-Path $PSScriptRoot 'validate-provision.ps1') -ProjectDir $root
foreach ($case in @(
    @{ Key = 'POSTGRES_ADMIN_OBJECT_ID'; Value = 'not-a-guid' },
    @{ Key = 'POSTGRES_ADMIN_USERNAME'; Value = '' },
    @{ Key = 'DEVELOPER_IPV4'; Value = '0.0.0.0' },
    @{ Key = 'DEVELOPER_IPV4'; Value = '10.0.0.1' },
    @{ Key = 'DEVELOPER_IPV4'; Value = '1.2.3.4/24' },
    @{ Key = 'DEVELOPER_IPV4'; Value = '::1' },
    @{ Key = 'DEVELOPER_IPV4_SECONDARY'; Value = '0.0.0.0' },
    @{ Key = 'DEVELOPER_IPV4_SECONDARY'; Value = '10.0.0.1' },
    @{ Key = 'DEVELOPER_IPV4_SECONDARY'; Value = '1.2.3.4/24' },
    @{ Key = 'DEVELOPER_IPV4_SECONDARY'; Value = '::1' },
    @{ Key = 'ALLOW_AZURE_SERVICES'; Value = 'false' }
)) {
    $previous = $testState.Settings[$case.Key]
    $testState.Settings[$case.Key] = $case.Value
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot 'validate-provision.ps1') -ProjectDir $root
    } catch { $rejected = $true } finally { $testState.Settings[$case.Key] = $previous }
    if (-not $rejected) { throw "Provision validation accepted invalid $($case.Key)." }
}

try {
    & docker run --detach --rm --name $container --env POSTGRES_HOST_AUTH_METHOD=trust postgres:17 > $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start isolated PostgreSQL test container.' }
    $containerStarted = $true
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        & docker exec $container pg_isready -U postgres > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Local PostgreSQL did not become ready.' }
    # Azure-specific functions are shimmed only for local SQL control-flow tests, not Entra acceptance.
    $shim = @'
CREATE DATABASE notes;
CREATE ROLE notes_test_developer;
CREATE TABLE public.test_principals (role_name text, object_id text);
CREATE FUNCTION pg_catalog.pgaadauth_create_principal_with_oid(text, text, text, boolean, boolean)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('CREATE ROLE %I LOGIN', $1);
  INSERT INTO public.test_principals VALUES ($1, $2);
  RETURN 'Created role';
END;
$$;
CREATE FUNCTION pg_catalog.pgaadauth_list_principals(boolean)
RETURNS TABLE(rolename name, principal_type text, object_id text, tenant_id text, is_mfa integer, is_admin integer)
LANGUAGE sql AS $$
  SELECT role_name::name, 'service'::text, object_id, 'test'::text, 0, 0 FROM public.test_principals;
$$;
'@
    Invoke-TestSql -Database postgres -Sql $shim
    $principal = Get-Content (Join-Path $PSScriptRoot 'bootstrap-principal.sql') -Raw
    $grants = Get-Content (Join-Path $PSScriptRoot 'bootstrap-grants.sql') -Raw
    Invoke-TestSql -Database postgres -Sql $principal
    Invoke-TestSql -Database postgres -Sql $principal
    Invoke-TestSql -Database notes -Sql $grants
    Invoke-TestSql -Database notes -Sql $grants
    Invoke-TestSql -Database notes -Sql @'
SET ROLE notes_test_app;
CREATE TABLE IF NOT EXISTS notes.bootstrap_test (id bigint GENERATED ALWAYS AS IDENTITY, body text);
INSERT INTO notes.bootstrap_test (body) VALUES ('application');
RESET ROLE;
SET ROLE notes_test_developer;
INSERT INTO notes.bootstrap_test (body) VALUES ('developer');
UPDATE notes.bootstrap_test SET body = 'updated';
SELECT * FROM notes.bootstrap_test;
DELETE FROM notes.bootstrap_test;
RESET ROLE;
'@
    $rejected = $false
    try {
        Invoke-TestSql -Database postgres -Sql $principal -ObjectId '22222222-2222-2222-2222-222222222222'
    } catch {
        if ($_ -notmatch 'does not match the expected non-admin managed identity') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Bootstrap must reject an existing role mapped to a different identity.' }

    $invalidCertificate = New-TemporaryFile
    $testState.Settings = @{
        POSTGRES_HOST = 'invalid.invalid'
        POSTGRES_PORT = '5432'
        POSTGRES_DATABASE = 'notes'
        POSTGRES_USERNAME = 'developer'
        POSTGRES_MANAGED_IDENTITY_USERNAME = 'notes_test_app'
        POSTGRES_MANAGED_IDENTITY_OBJECT_ID = '11111111-1111-1111-1111-111111111111'
        AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        POSTGRES_DEVELOPER_SSL_ROOT_CERT = $invalidCertificate.FullName
    }
    Set-Item Function:az -Value {
        $global:LASTEXITCODE = 0
        if ($args[1] -eq 'show') { return $testState.Settings.AZURE_TENANT_ID }
        $testState.Token
    }.GetNewClosure()
    $failure = ''
    try {
        $failure = (& (Join-Path $PSScriptRoot 'bootstrap-database.ps1') -ProjectDir $root 6>&1 | Out-String)
        throw 'Bootstrap unexpectedly succeeded against a deliberately invalid hostname.'
    } catch {
        $failure += $_.ToString()
        if ($failure -notmatch 'Client output is withheld to protect credentials') { throw }
    }
    if ($failure.Contains($testState.Token)) { throw 'Bootstrap output disclosed an authentication token.' }
    Write-Host 'PASS: Bicep, PowerShell, parameters, provision-input gates, repeatable SQL/grants, CRUD privileges, identity mismatch and token non-disclosure.'
    Write-Host 'Azure Entra functions were shimmed; no cloud authentication or provisioning was tested.'
} finally {
    if ($null -ne $invalidCertificate) { Remove-Item -LiteralPath $invalidCertificate.FullName }
    if ($containerStarted) {
        $remaining = & docker ps --all --filter "name=^/$container$" --format '{{.ID}}'
        if ($LASTEXITCODE -ne 0) { throw 'Could not verify bootstrap test-container cleanup.' }
        if ($remaining) {
            & docker rm --force $container > $null 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Could not remove bootstrap test container $container." }
        }
    }
}
