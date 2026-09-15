<#
.SYNOPSIS
    Downloads and configures the Azure VPN Client profile for the deployed
    Point-to-Site (P2S) VPN Gateway, so this workstation can connect directly
    to the private VNet (no jump VM / Bastion required).

.DESCRIPTION
    Prerequisites:
      - The environment must have been deployed with deployVpnGateway=true
        (e.g. `DEPLOY_VPN_GATEWAY=true azd up`, or `azd env set DEPLOY_VPN_GATEWAY true`
        followed by `azd provision`).
      - Azure VPN Client must be installed on this machine:
          https://learn.microsoft.com/azure/vpn-gateway/point-to-site-vpn-client-cert-windows#azure-vpn-client
      - You must have permission to authenticate with Microsoft Entra ID against
        this tenant (the gateway uses Entra ID / AAD authentication, not certificates).

    This script:
      1. Resolves the resource group / VPN gateway name from azd env outputs if not passed explicitly.
      2. Downloads the VPN client configuration package via `az network vnet-gateway vpn-client generate`.
      3. Extracts the Azure VPN Client XML profile and opens/points you to it for import.

    After importing the profile into the Azure VPN Client and connecting, this
    workstation gets a private IP in the VNet's client address pool and can reach
    the storage account (and any other private-endpoint-only resource) exactly
    like the Container Apps / jump VM do today. The storage account's public
    network access remains fully "Disabled" throughout - nothing is opened publicly.

.PARAMETER ResourceGroup
    Resource group containing the VPN gateway. Defaults to the azd env's
    AZURE_RESOURCE_GROUP value.

.PARAMETER GatewayName
    Name of the virtual network gateway. Defaults to the azd env's
    vpnGatewayName output.

.EXAMPLE
    .\connect_vpn_gateway.ps1

.EXAMPLE
    .\connect_vpn_gateway.ps1 -ResourceGroup rg-dev080626c -GatewayName vnetdev080626c-vpngw
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$GatewayName
)

$ErrorActionPreference = 'Stop'

function Get-AzdValue {
    param([string]$Key)
    try {
        $value = (azd env get-value $Key 2>$null)
        if ($LASTEXITCODE -eq 0 -and $value) { return $value.Trim() }
    } catch {}
    return $null
}

if (-not $ResourceGroup) {
    $ResourceGroup = Get-AzdValue -Key 'AZURE_RESOURCE_GROUP'
}
if (-not $ResourceGroup) {
    throw "Could not resolve resource group. Pass -ResourceGroup explicitly or run this from a directory with an azd environment selected."
}

if (-not $GatewayName) {
    $GatewayName = Get-AzdValue -Key 'vpnGatewayName'
}
if (-not $GatewayName) {
    throw "Could not resolve VPN gateway name. Pass -GatewayName explicitly, or confirm deployVpnGateway=true was used during provisioning."
}

Write-Host "Resource group: $ResourceGroup"
Write-Host "VPN gateway:    $GatewayName"

$downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "vpnclient-$GatewayName"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

Write-Host "Requesting VPN client configuration package (this can take a minute)..."
$packageUrl = az network vnet-gateway vpn-client generate `
    --resource-group $ResourceGroup `
    --name $GatewayName `
    --authentication-method EAPTLS `
    -o tsv

if (-not $packageUrl) {
    throw "Failed to generate VPN client package. Confirm the gateway exists and vpnClientConfiguration.vpnAuthenticationTypes includes AAD."
}

$zipPath = Join-Path $downloadDir 'vpnclientconfiguration.zip'
Write-Host "Downloading package to $zipPath ..."
Invoke-WebRequest -Uri $packageUrl -OutFile $zipPath

Expand-Archive -Path $zipPath -DestinationPath $downloadDir -Force

$azureVpnProfile = Get-ChildItem -Path $downloadDir -Recurse -Filter 'AzureVPN' -Directory | Select-Object -First 1
if ($azureVpnProfile) {
    $profileXml = Get-ChildItem -Path $azureVpnProfile.FullName -Filter '*.xml' | Select-Object -First 1
    if ($profileXml) {
        Write-Host ""
        Write-Host "Azure VPN Client profile ready: $($profileXml.FullName)"
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  1. Install the Azure VPN Client (https://aka.ms/azvpnclient) if not already installed."
        Write-Host "  2. Open Azure VPN Client -> Import -> select the XML file above."
        Write-Host "  3. Click Connect and sign in with your Microsoft Entra ID account."
        Write-Host "  4. Once connected, run the blob-file-manager app locally with STORAGE_ACCOUNT_NAME set"
        Write-Host "     (see apps/blob-file-manager/README.md) - it will reach the storage account through"
        Write-Host "     the private endpoint, the same way it does inside the VNet."
        exit 0
    }
}

Write-Warning "Could not locate the AzureVPN profile XML automatically. Inspect the extracted files under: $downloadDir"
