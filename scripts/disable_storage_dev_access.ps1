<#
.SYNOPSIS
    Reverts the Storage Account back to fully private after using
    enable_storage_dev_access.ps1 for local development.

.DESCRIPTION
    Sets the Storage Account's public network access back to 'Disabled',
    matching the default, fully network-isolated configuration this
    accelerator deploys. Private endpoint connectivity (Container Apps, Jump
    VM) is unaffected either way.

.PARAMETER ResourceGroup
    Resource group containing the Storage Account. Defaults to
    $env:AZURE_RESOURCE_GROUP or the current `azd env` value.

.PARAMETER StorageAccountName
    Name of the Storage Account. If omitted, it is resolved from the
    `STORAGE_ACCOUNT_NAME` azd environment value.

.EXAMPLE
    ./disable_storage_dev_access.ps1 -ResourceGroup rg-dev080626c
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$StorageAccountName
)

$ErrorActionPreference = 'Stop'

function Get-AzdValue {
    param([string]$Name)
    try {
        $value = & azd env get-value $Name 2>$null
        if ($LASTEXITCODE -eq 0) { return [string]$value }
    } catch { }
    return $null
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
}
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    Write-Error "ResourceGroup is required. Pass -ResourceGroup or set AZURE_RESOURCE_GROUP / run from an azd environment."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    $StorageAccountName = Get-AzdValue 'STORAGE_ACCOUNT_NAME'
}
if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    Write-Error "StorageAccountName is required. Pass -StorageAccountName or set it via azd env (STORAGE_ACCOUNT_NAME)."
    exit 1
}

Write-Host "Locking down Storage Account '$StorageAccountName' (public network access -> Disabled)..." -ForegroundColor Cyan

az storage account update `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --public-network-access Disabled `
    --only-show-errors | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to disable public network access on the Storage Account."
    exit 1
}

Write-Host "[OK] Storage Account is fully private again. Private endpoint access (Container Apps, Jump VM) is unaffected." -ForegroundColor Green
