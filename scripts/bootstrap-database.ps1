param([string]$ProjectDir = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-DatabaseAccessToken {
    param([hashtable]$Settings)

    $subscriptionTenant = & az account show --subscription $Settings.AZURE_SUBSCRIPTION_ID `
        --query tenantId --output tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or
        ($subscriptionTenant -join '').Trim() -ne $Settings.AZURE_TENANT_ID) {
        throw 'The selected subscription does not resolve to the approved database tenant. Verify the isolated Azure CLI login and azd tenant/subscription settings.'
    }
    $tokenResult = & az account get-access-token --resource 'https://ossrdbms-aad.database.windows.net' `
        --subscription $Settings.AZURE_SUBSCRIPTION_ID `
        --query accessToken --output tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($tokenResult -join ''))) {
        throw 'Could not obtain the PostgreSQL Entra token. Sign in to Azure CLI as the approved database administrator in the target tenant.'
    }
    return ($tokenResult -join '').Trim()
}

function Invoke-DatabaseSql {
    param(
        [hashtable]$Settings,
        [string]$Database,
        [string]$Sql,
        [string]$Token,
        [bool]$UseDocker
    )
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $arguments = @('-X', '--no-password', '--set=ON_ERROR_STOP=1',
        "--set=app_role=$($Settings.POSTGRES_MANAGED_IDENTITY_USERNAME)",
        "--set=app_oid=$($Settings.POSTGRES_MANAGED_IDENTITY_OBJECT_ID)",
        "--set=app_database=$($Settings.POSTGRES_DATABASE)",
        "--set=developer_role=$($Settings.POSTGRES_USERNAME)", '--file=-')
    if ($UseDocker) {
        $processInfo.FileName = (Get-Command docker -ErrorAction Stop).Source
        foreach ($argument in @('run', '--rm', '-i', '--network=bridge',
            '--volume', "$($Settings.POSTGRES_DEVELOPER_SSL_ROOT_CERT):/tmp/postgresql-roots.pem:ro",
            '--env', "PGHOST=$($Settings.POSTGRES_HOST)", '--env', "PGPORT=$($Settings.POSTGRES_PORT)",
            '--env', "PGUSER=$($Settings.POSTGRES_USERNAME)", '--env', "PGDATABASE=$Database",
            '--env', 'PGSSLMODE=verify-full', '--env', 'PGSSLROOTCERT=/tmp/postgresql-roots.pem', '--env', 'PGCONNECT_TIMEOUT=20',
            'postgres:17', 'sh', '-c',
            'IFS= read -r PGPASSWORD; export PGPASSWORD; exec psql "$@"', 'bootstrap')) {
            $processInfo.ArgumentList.Add($argument)
        }
    } else {
        $processInfo.FileName = (Get-Command psql -ErrorAction Stop).Source
        $processInfo.Environment['PGHOST'] = $Settings.POSTGRES_HOST
        $processInfo.Environment['PGPORT'] = $Settings.POSTGRES_PORT
        $processInfo.Environment['PGUSER'] = $Settings.POSTGRES_USERNAME
        $processInfo.Environment['PGDATABASE'] = $Database
        $processInfo.Environment['PGSSLMODE'] = 'verify-full'
        $processInfo.Environment['PGSSLROOTCERT'] = 'system'
        $processInfo.Environment['PGCONNECT_TIMEOUT'] = '20'
        $processInfo.Environment['PGPASSWORD'] = $Token
    }
    foreach ($argument in $arguments) { $processInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    try {
        if (-not $process.Start()) { throw 'Could not start PostgreSQL bootstrap client.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($UseDocker) { $process.StandardInput.Write($Token + "`n") }
        $process.StandardInput.Write($Sql)
        $process.StandardInput.Close()
        $process.WaitForExit()
        # Never forward raw client output: it may contain connection secrets on failure.
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Database bootstrap failed for $Database (exit $($process.ExitCode)). Check approved firewall IP, Entra administrator mapping, token tenant, and role compatibility. Client output is withheld to protect credentials."
        }
    } finally {
        $processInfo.Environment.Remove('PGPASSWORD') | Out-Null
        $process.Dispose()
    }
}

Push-Location $ProjectDir
try {
    $values = & azd env get-values --output json
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the selected azd environment.' }
    $settings = ($values -join "`n") | ConvertFrom-Json -AsHashtable
    foreach ($name in @('POSTGRES_HOST', 'POSTGRES_PORT', 'POSTGRES_DATABASE', 'POSTGRES_USERNAME',
        'POSTGRES_MANAGED_IDENTITY_USERNAME', 'POSTGRES_MANAGED_IDENTITY_OBJECT_ID', 'AZURE_TENANT_ID',
        'AZURE_SUBSCRIPTION_ID')) {
        if (-not $settings.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($settings[$name])) {
            throw "Missing $name. Provision infrastructure before bootstrapping the database."
        }
    }
    $useDocker = $null -eq (Get-Command psql -ErrorAction SilentlyContinue)
    if ($useDocker) {
        $null = Get-Command docker -ErrorAction Stop
        if (-not $settings.ContainsKey('POSTGRES_DEVELOPER_SSL_ROOT_CERT') -or
            [string]::IsNullOrWhiteSpace($settings.POSTGRES_DEVELOPER_SSL_ROOT_CERT)) {
            & azd springboot configure --project-dir (Get-Location).Path
            if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the public PostgreSQL trust bundle.' }
            $values = & azd env get-values --output json
            if ($LASTEXITCODE -ne 0) { throw 'Could not reload PostgreSQL trust configuration.' }
            $settings = ($values -join "`n") | ConvertFrom-Json -AsHashtable
        }
        if (-not $settings.ContainsKey('POSTGRES_DEVELOPER_SSL_ROOT_CERT') -or
            -not (Test-Path -LiteralPath $settings.POSTGRES_DEVELOPER_SSL_ROOT_CERT -PathType Leaf)) {
            throw 'The Docker PostgreSQL client requires a readable public POSTGRES_DEVELOPER_SSL_ROOT_CERT PEM bundle.'
        }
        $settings.POSTGRES_DEVELOPER_SSL_ROOT_CERT = [IO.Path]::GetFullPath($settings.POSTGRES_DEVELOPER_SSL_ROOT_CERT)
    }
    # Capture token output, never echo it or store it in azd environment/files/container configuration.
    $token = Get-DatabaseAccessToken -Settings $settings
    Invoke-DatabaseSql -Settings $settings -Database 'postgres' `
        -Sql (Get-Content (Join-Path $PSScriptRoot 'bootstrap-principal.sql') -Raw) -Token $token -UseDocker $useDocker
    Invoke-DatabaseSql -Settings $settings -Database $settings.POSTGRES_DATABASE `
        -Sql (Get-Content (Join-Path $PSScriptRoot 'bootstrap-grants.sql') -Raw) -Token $token -UseDocker $useDocker
    Write-Host 'Database managed-identity principal and application grants bootstrapped.'
} finally {
    $token = $null
    $tokenResult = $null
    Pop-Location
}
