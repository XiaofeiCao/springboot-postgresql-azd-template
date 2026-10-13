param([string]$ProjectDir = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $ProjectDir
try {
    $values = & azd env get-values --output json
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the selected azd environment.' }
    $settings = ($values -join "`n") | ConvertFrom-Json -AsHashtable
    foreach ($name in @('POSTGRES_ADMIN_OBJECT_ID', 'POSTGRES_ADMIN_USERNAME', 'DEVELOPER_IPV4')) {
        if (-not $settings.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($settings[$name])) {
            throw "Set $name explicitly with azd env set before provisioning."
        }
    }
    $objectId = [guid]::Empty
    if (-not [guid]::TryParse($settings.POSTGRES_ADMIN_OBJECT_ID, [ref]$objectId)) {
        throw 'POSTGRES_ADMIN_OBJECT_ID must be the approved developer object GUID in the target tenant.'
    }
    foreach ($name in @('DEVELOPER_IPV4', 'DEVELOPER_IPV4_SECONDARY')) {
    if ($name -eq 'DEVELOPER_IPV4_SECONDARY' -and
        (-not $settings.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($settings[$name]))) {
        continue
    }
    $address = $null
    $text = [string]$settings[$name]
    if ($text -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or
        -not [System.Net.IPAddress]::TryParse($text, [ref]$address) -or
        $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
        $address.ToString() -cne $text -or
        $text -in @('0.0.0.0', '255.255.255.255')) {
        throw "$name must be one explicitly approved IPv4 address, not a range, wildcard, or Azure-services sentinel."
    }
    $octets = $address.GetAddressBytes()
    if ($octets[0] -in @(0, 10, 127) -or $octets[0] -ge 224 -or
        ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
        ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127)) {
        throw "$name must be the approved public outbound address, not a private, loopback, link-local, or multicast address."
    }
    }
    if (-not $settings.ContainsKey('ALLOW_AZURE_SERVICES') -or $settings.ALLOW_AZURE_SERVICES -cne 'true') {
        throw 'This public-network prototype requires explicit ALLOW_AZURE_SERVICES=true approval. It allows Azure-origin traffic from other subscriptions; see README. For restricted production access, redesign with private networking instead.'
    }
} finally {
    Pop-Location
}
