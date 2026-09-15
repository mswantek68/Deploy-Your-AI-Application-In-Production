# BlobStorageManager.ps1 - Interact with an Azure Storage blob container that sits
# behind a private endpoint (networkIsolation = true, per infra/main.bicepparam).
#
# Authentication uses Microsoft Entra ID (via `az account get-access-token`), the same
# pattern already used by SecurityModule.ps1 for Fabric/Power BI/Purview tokens (the
# 'Storage' resource endpoint is already defined there). No account keys or SAS tokens
# are used or stored, consistent with the repo's Key-Vault-first secrets posture.
#
# Because these functions call the standard `<account>.blob.core.windows.net` REST
# endpoint over HTTPS, they work unmodified whether the storage account is public or
# is published only via a private endpoint: when run from inside the VNet (e.g. the
# Jump VM, a container app on the agent/aca-environment subnet, or a build agent on
# devops-build-agents-subnet) the private DNS zone linked to the VNet resolves the
# account name to its private IP, and traffic never leaves the VNet. When run from
# outside the VNet, the same code will fail to resolve/connect, which is the expected
# behavior for a network-isolated storage account (see docs/Accessing_Private_Resources.md).
#
# Requires -Version 5.1

# Import the shared token/REST helpers (Get-SecureApiToken, New-SecureHeaders, etc.)
. "$PSScriptRoot/../SecurityModule.ps1"

$script:BlobStorageApiVersion = '2025-05-05'

function Get-BlobStorageAccessToken {
    <#
    .SYNOPSIS
        Acquires an Entra ID access token scoped to Azure Storage.
    #>
    [CmdletBinding()]
    param()

    return Get-SecureApiToken -Resource $SecureApiResources.Storage -Description 'Azure Storage'
}

function Get-BlobStorageEndpoint {
    <#
    .SYNOPSIS
        Builds the blob service base URI for a storage account, honoring
        AzureCloud/AzureUSGovernment/AzureChinaCloud DNS suffixes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $suffix = switch ($CloudEnvironment) {
        'AzureUSGovernment' { 'core.usgovcloudapi.net' }
        'AzureChinaCloud'   { 'core.chinacloudapi.cn' }
        default             { 'core.windows.net' }
    }

    return "https://$StorageAccountName.blob.$suffix"
}

function Test-BlobPrivateEndpointConnectivity {
    <#
    .SYNOPSIS
        Verifies that the storage account's blob DNS name resolves to a private
        (RFC1918) address, confirming the private endpoint + private DNS zone
        link are working as expected under networkIsolation = true.
    .DESCRIPTION
        This is a diagnostic helper only; it does not block the other functions
        in this module from running. Use it from the Jump VM (or any host inside
        the VNet) when troubleshooting connectivity per
        docs/Accessing_Private_Resources.md.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment
    $hostName = ([Uri]$endpoint).Host

    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($hostName)
    }
    catch {
        Write-Error "Failed to resolve '$hostName': $($_.Exception.Message)"
        return $false
    }

    $privateRanges = @(
        [PSCustomObject]@{ Network = [System.Net.IPAddress]::Parse('10.0.0.0');     Bits = 8 }
        [PSCustomObject]@{ Network = [System.Net.IPAddress]::Parse('172.16.0.0');   Bits = 12 }
        [PSCustomObject]@{ Network = [System.Net.IPAddress]::Parse('192.168.0.0');  Bits = 16 }
    )

    function Test-IpInRange([System.Net.IPAddress]$Address, [System.Net.IPAddress]$Network, [int]$Bits) {
        $addrBytes = $Address.GetAddressBytes()
        $netBytes = $Network.GetAddressBytes()
        if ($addrBytes.Length -ne $netBytes.Length) { return $false }
        $fullBytes = [Math]::Floor($Bits / 8)
        for ($i = 0; $i -lt $fullBytes; $i++) {
            if ($addrBytes[$i] -ne $netBytes[$i]) { return $false }
        }
        $remainderBits = $Bits % 8
        if ($remainderBits -eq 0) { return $true }
        $mask = [byte](0xFF -shl (8 - $remainderBits))
        return ($addrBytes[$fullBytes] -band $mask) -eq ($netBytes[$fullBytes] -band $mask)
    }

    $isPrivate = $false
    foreach ($ip in $resolved) {
        foreach ($range in $privateRanges) {
            if (Test-IpInRange -Address $ip -Network $range.Network -Bits $range.Bits) {
                $isPrivate = $true
                break
            }
        }
    }

    if ($isPrivate) {
        Write-Host "[+] '$hostName' resolves to a private address ($($resolved -join ', ')) - private endpoint appears active." -ForegroundColor Green
    } else {
        Write-Warning "'$hostName' resolved to $($resolved -join ', '), which is not in a private range. If networkIsolation is enabled, verify the private endpoint and private DNS zone link (see docs/Accessing_Private_Resources.md)."
    }

    return $isPrivate
}

function New-StorageBlobContainer {
    <#
    .SYNOPSIS
        Creates a blob container if it does not already exist (idempotent).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $token = Get-BlobStorageAccessToken
    $headers = New-SecureHeaders -Token $token -AdditionalHeaders @{ 'x-ms-version' = $script:BlobStorageApiVersion }
    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment
    $uri = "$endpoint/$ContainerName`?restype=container"

    try {
        Invoke-SecureRestMethod -Uri $uri -Headers $headers -Method 'PUT' -Description "create container '$ContainerName'" | Out-Null
        Write-Host "[+] Container '$ContainerName' created." -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 409) {
            Write-Host "[i] Container '$ContainerName' already exists." -ForegroundColor Yellow
        } else {
            throw
        }
    }
}

function Get-StorageBlobList {
    <#
    .SYNOPSIS
        Lists blobs in a container behind a private endpoint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $token = Get-BlobStorageAccessToken
    $headers = New-SecureHeaders -Token $token -AdditionalHeaders @{ 'x-ms-version' = $script:BlobStorageApiVersion }
    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment

    $blobs = New-Object System.Collections.Generic.List[object]
    $marker = $null

    do {
        $query = "restype=container&comp=list"
        if ($Prefix) { $query += "&prefix=$([Uri]::EscapeDataString($Prefix))" }
        if ($marker) { $query += "&marker=$([Uri]::EscapeDataString($marker))" }
        $uri = "$endpoint/$ContainerName`?$query"

        $response = Invoke-SecureWebRequest -Uri $uri -Headers $headers -Method 'GET' -Description "list blobs in '$ContainerName'"
        [xml]$xml = $response.Content

        foreach ($blob in $xml.EnumerationResults.Blobs.Blob) {
            $blobs.Add([PSCustomObject]@{
                Name          = $blob.Name
                ContentLength = [int64]$blob.Properties.'Content-Length'
                LastModified  = $blob.Properties.'Last-Modified'
                ContentType   = $blob.Properties.'Content-Type'
                Etag          = $blob.Properties.Etag
            })
        }

        $marker = $xml.EnumerationResults.NextMarker
    } while (-not [string]::IsNullOrEmpty($marker))

    return $blobs
}

function Get-StorageBlobContent {
    <#
    .SYNOPSIS
        Downloads a blob to a local file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$BlobName,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $token = Get-BlobStorageAccessToken
    $headers = New-SecureHeaders -Token $token -AdditionalHeaders @{ 'x-ms-version' = $script:BlobStorageApiVersion }
    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment
    $encodedBlobName = ($BlobName -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $uri = "$endpoint/$ContainerName/$encodedBlobName"

    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if ($destinationDir -and -not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    try {
        Write-Host "Executing secure download of blob '$BlobName'..." -ForegroundColor Green
        Invoke-WebRequest -Uri $uri -Headers $headers -Method 'GET' -OutFile $DestinationPath | Out-Null
        Write-Host "[+] Downloaded '$BlobName' to '$DestinationPath'." -ForegroundColor Green
    }
    catch {
        $sanitizedError = $_.Exception.Message -replace '******', '******'
        Write-Error "Secure download of blob '$BlobName' failed: $sanitizedError" -ErrorAction Stop
    }
}

function Set-StorageBlobContent {
    <#
    .SYNOPSIS
        Uploads a local file as a block blob.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$BlobName,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/octet-stream',

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Source file not found: $SourcePath"
    }

    $token = Get-BlobStorageAccessToken
    $headers = New-SecureHeaders -Token $token -AdditionalHeaders @{
        'x-ms-version' = $script:BlobStorageApiVersion
        'x-ms-blob-type' = 'BlockBlob'
    }
    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment
    $encodedBlobName = ($BlobName -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $uri = "$endpoint/$ContainerName/$encodedBlobName"

    try {
        Write-Host "Executing secure upload of blob '$BlobName'..." -ForegroundColor Green
        Invoke-WebRequest -Uri $uri -Headers $headers -Method 'PUT' -InFile $SourcePath -ContentType $ContentType | Out-Null
        Write-Host "[+] Uploaded '$SourcePath' as '$BlobName'." -ForegroundColor Green
    }
    catch {
        $sanitizedError = $_.Exception.Message -replace '******', '******'
        Write-Error "Secure upload of blob '$BlobName' failed: $sanitizedError" -ErrorAction Stop
    }
}

function Remove-StorageBlob {
    <#
    .SYNOPSIS
        Deletes a blob from a container.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$BlobName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$CloudEnvironment = 'AzureCloud'
    )

    $token = Get-BlobStorageAccessToken
    $headers = New-SecureHeaders -Token $token -AdditionalHeaders @{ 'x-ms-version' = $script:BlobStorageApiVersion }
    $endpoint = Get-BlobStorageEndpoint -StorageAccountName $StorageAccountName -CloudEnvironment $CloudEnvironment
    $encodedBlobName = ($BlobName -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $uri = "$endpoint/$ContainerName/$encodedBlobName"

    Invoke-SecureRestMethod -Uri $uri -Headers $headers -Method 'DELETE' -Description "delete blob '$BlobName'" | Out-Null
    Write-Host "[+] Deleted blob '$BlobName'." -ForegroundColor Green
}
