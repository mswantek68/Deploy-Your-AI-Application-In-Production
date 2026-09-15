<#
.SYNOPSIS
    Temporarily opens the deployed Storage Account's public network endpoint,
    restricted to your current public IP address, so you can run apps (such
    as apps/blob-file-manager) from a normal developer workstation and have
    uploads/downloads/edits actually land in the real Azure Storage account
    — not just a local emulator.

.DESCRIPTION
    This accelerator deploys the Storage Account with public network access
    fully DISABLED when networkIsolation=true (the default). That setting
    blocks ALL public traffic unconditionally, including IP-allowlisted
    traffic, so there is no firewall rule that can let a normal dev machine
    reach it directly.

    This script:
      1. Detects your current public IP address (or uses -MyIpAddress if
         provided).
      2. Sets the Storage Account's public network access to 'Enabled' with
         a default-deny network ACL, then adds a firewall rule allowing only
         your IP address.
      3. Grants the specified principal (defaults to your signed-in `az`
         account) the 'Storage Blob Data Contributor' role on the Storage
         Account, so it can read/write blobs.

    Private endpoint traffic (used by the Container Apps environment and the
    Jump VM) is unaffected by this change — private endpoints bypass the
    public firewall entirely. This only opens a narrow, IP-restricted hole in
    the public endpoint for local development.

    Run ./disable_storage_dev_access.ps1 afterwards to lock the account back
    down to fully private.

.PARAMETER ResourceGroup
    Resource group containing the Storage Account. Defaults to
    $env:AZURE_RESOURCE_GROUP or the current `azd env` value.

.PARAMETER StorageAccountName
    Name of the Storage Account. If omitted, it is resolved from the
    `STORAGE_ACCOUNT_NAME` azd environment value.

.PARAMETER MyIpAddress
    Your public IP address to allow. If omitted, it is auto-detected via
    https://api.ipify.org.

.PARAMETER PrincipalId
    Entra object ID to grant 'Storage Blob Data Contributor'. Defaults to the
    currently signed-in `az` account's object ID.

.EXAMPLE
    ./enable_storage_dev_access.ps1 -ResourceGroup rg-dev080626c

.EXAMPLE
    ./enable_storage_dev_access.ps1 -ResourceGroup rg-dev080626c -StorageAccountName stmyenv1234
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$StorageAccountName,
    [string]$MyIpAddress,
    [string]$PrincipalId
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

if ([string]::IsNullOrWhiteSpace($MyIpAddress)) {
    Write-Host "Detecting your public IP address..." -ForegroundColor Cyan
    $MyIpAddress = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
}
if ([string]::IsNullOrWhiteSpace($MyIpAddress) -or ($MyIpAddress -notmatch '^\d{1,3}(\.\d{1,3}){3}$')) {
    Write-Error "Could not determine a valid IPv4 address. Pass -MyIpAddress explicitly."
    exit 1
}
Write-Host "Using public IP: $MyIpAddress" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
    Write-Host "Resolving signed-in account object ID..." -ForegroundColor Cyan
    $PrincipalId = (az ad signed-in-user show --query id -o tsv 2>$null)
}
if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
    Write-Error "Could not resolve a PrincipalId. Pass -PrincipalId explicitly, or run 'az login' first."
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host " Opening Storage Account '$StorageAccountName' to IP $MyIpAddress" -ForegroundColor Yellow
Write-Host " Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "[1/3] Enabling public network access with default-deny network ACL..." -ForegroundColor White
az storage account update `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --public-network-access Enabled `
    --default-action Deny `
    --bypass AzureServices `
    --only-show-errors | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update public network access on the Storage Account."
    exit 1
}

Write-Host "[2/3] Adding firewall rule for $MyIpAddress..." -ForegroundColor White
az storage account network-rule add `
    --account-name $StorageAccountName `
    --resource-group $ResourceGroup `
    --ip-address $MyIpAddress `
    --only-show-errors | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to add the network rule."
    exit 1
}

Write-Host "[3/3] Granting Storage Blob Data Contributor to principal $PrincipalId..." -ForegroundColor White
$storageId = az storage account show --name $StorageAccountName --resource-group $ResourceGroup --query id -o tsv
az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type User `
    --role "Storage Blob Data Contributor" `
    --scope $storageId `
    --only-show-errors | Out-Null

Write-Host ""
Write-Host "[OK] Done. You can now run apps/blob-file-manager locally against the real Storage Account:" -ForegroundColor Green
Write-Host ""
Write-Host "    cd apps/blob-file-manager" -ForegroundColor White
Write-Host "    pip install -r requirements.txt" -ForegroundColor White
Write-Host "    unset AZURE_STORAGE_CONNECTION_STRING   # (or `$env:AZURE_STORAGE_CONNECTION_STRING = `$null in PowerShell)" -ForegroundColor White
Write-Host "    export STORAGE_ACCOUNT_NAME=$StorageAccountName" -ForegroundColor White
Write-Host "    az login" -ForegroundColor White
Write-Host "    python app.py" -ForegroundColor White
Write-Host ""
Write-Host "Uploads/downloads/edits will now go to the real Azure Storage account." -ForegroundColor Green
Write-Host "Run ./disable_storage_dev_access.ps1 when you're done to lock it back down." -ForegroundColor Yellow
