# PSScriptAnalyzer -SkipRule PSAvoidUsingPlainTextForPassword, PSPossibleIncorrectComparisonWithNull, PSUseDeclaredVarsMoreThanAssignments
param(
  [Parameter(Mandatory = $false)]
  [string] $FabricWorkspaceId = '',

  [Parameter(Mandatory = $false)]
  [string] $FabricWorkspaceName = '',

  [Parameter(Mandatory = $false)]
  [string] $PostgresServerFqdn = '',

  [Parameter(Mandatory = $false)]
  [string] $PostgresDatabaseName = '',

  [Parameter(Mandatory = $false)]
  [string] $KeyVaultName = '',

  [Parameter(Mandatory = $false)]
  [pscredential] $PostgresCredential,

  [Parameter(Mandatory = $false)]
  [string] $MirrorName = '',

  [Parameter(Mandatory = $false)]
  [switch] $DryRun
)

# This script must run AFTER:
# 1) PostgreSQL is provisioned
# 2) Fabric workspace is created
# 3) Workspace is connected to Purview
# 4) If isolated, Fabric workspace private endpoint is connected

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-mirror] $m" }
function Warn([string]$m){ Write-Warning "[fabric-mirror] $m" }
function Fail([string]$m){ Write-Error "[fabric-mirror] $m"; exit 1 }

# Resolve feature flag
$fabricMirrorEnabled = $env:fabricMirrorEnabled
if (-not $fabricMirrorEnabled) { $fabricMirrorEnabled = $env:fabricMirrorEnabledOut }
if (-not $fabricMirrorEnabled) {
  try {
    $azdMirror = & azd env get-value fabricMirrorEnabledOut 2>$null
    if ($azdMirror) { $fabricMirrorEnabled = $azdMirror.ToString().Trim() }
  } catch {}
}
if (($null -eq $fabricMirrorEnabled -or '' -eq $fabricMirrorEnabled) -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $outMirror = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($null -ne $outMirror.fabricMirrorEnabledOut -and $null -ne $outMirror.fabricMirrorEnabledOut.value) { $fabricMirrorEnabled = $outMirror.fabricMirrorEnabledOut.value }
  } catch {}
}

if ($fabricMirrorEnabled -and $fabricMirrorEnabled.ToString().Trim().ToLowerInvariant() -eq 'false') {
  Warn "Fabric mirror disabled; skipping."
  exit 0
}

$postgresMode = $env:postgresMode
if (-not $postgresMode) { $postgresMode = $env:postgresModeOut }
if (-not $postgresMode -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $outPg = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($outPg.postgresModeOut -and $outPg.postgresModeOut.value) { $postgresMode = $outPg.postgresModeOut.value }
  } catch {}
}
if ($postgresMode -and $postgresMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Warn "PostgreSQL mode is 'none'; skipping mirror."
  exit 0
}

# Resolve workspace id/name
if (-not $FabricWorkspaceId) { $FabricWorkspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $FabricWorkspaceName) { $FabricWorkspaceName = $env:FABRIC_WORKSPACE_NAME }
if (-not $FabricWorkspaceId -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.fabricWorkspaceIdOut -and $out.fabricWorkspaceIdOut.value) { $FabricWorkspaceId = $out.fabricWorkspaceIdOut.value }
  } catch {}
}
if (-not $FabricWorkspaceName -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.fabricWorkspaceNameOut -and $out.fabricWorkspaceNameOut.value) { $FabricWorkspaceName = $out.fabricWorkspaceNameOut.value }
    elseif ($out.desiredFabricWorkspaceName -and $out.desiredFabricWorkspaceName.value) { $FabricWorkspaceName = $out.desiredFabricWorkspaceName.value }
  } catch {}
}

# Resolve Postgres outputs
if (-not $PostgresServerFqdn) { $PostgresServerFqdn = $env:postgresFqdnOut }
if (-not $PostgresDatabaseName) { $PostgresDatabaseName = $env:postgresDatabaseNameOut }
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $outPg = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if (-not $PostgresServerFqdn -and $outPg.postgresFqdnOut -and $outPg.postgresFqdnOut.value) { $PostgresServerFqdn = $outPg.postgresFqdnOut.value }
    if (-not $PostgresDatabaseName -and $outPg.postgresDatabaseNameOut -and $outPg.postgresDatabaseNameOut.value) { $PostgresDatabaseName = $outPg.postgresDatabaseNameOut.value }
  } catch {}
}

# Resolve mirror name
if (-not $MirrorName) { $MirrorName = $env:fabricMirrorName }
if (-not $MirrorName) { $MirrorName = $env:fabricMirrorNameOut }
if (-not $MirrorName -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $outMirror = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($outMirror.fabricMirrorNameOut -and $outMirror.fabricMirrorNameOut.value) { $MirrorName = $outMirror.fabricMirrorNameOut.value }
  } catch {}
}

# Resolve secret names from outputs (defaults if not provided)
$SecretNameUser = 'postgres-admin-username'
$SecretNameAuth = 'postgres-admin-password'
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $outMirror = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($outMirror.fabricMirrorSecretReferences -and $outMirror.fabricMirrorSecretReferences.value) {
      if ($outMirror.fabricMirrorSecretReferences.value.usernameSecretName) { $SecretNameUser = $outMirror.fabricMirrorSecretReferences.value.usernameSecretName }
      if ($outMirror.fabricMirrorSecretReferences.value.passwordSecretName) { $SecretNameAuth = $outMirror.fabricMirrorSecretReferences.value.passwordSecretName }
    }
  } catch {}
}

# Resolve Key Vault name from output if not provided
if (-not $KeyVaultName) {
  $keyVaultResourceId = $env:keyVaultResourceId
  if (-not $keyVaultResourceId) { $keyVaultResourceId = $env:keyVaultResourceIdOut }
  if (-not $keyVaultResourceId -and $env:AZURE_OUTPUTS_JSON) {
    try {
      $outKv = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
      if ($outKv.keyVaultResourceId -and $outKv.keyVaultResourceId.value) { $keyVaultResourceId = $outKv.keyVaultResourceId.value }
    } catch {}
  }
  if ($keyVaultResourceId) {
    $KeyVaultName = ($keyVaultResourceId -split '/')[ -1 ]
  }
}

if (-not $FabricWorkspaceId) { Fail "Fabric workspace ID unresolved. Ensure workspace is created or BYO is configured." }
if (-not $FabricWorkspaceName) { Fail "Fabric workspace name unresolved." }
if (-not $PostgresServerFqdn) { Fail "PostgreSQL FQDN unresolved. Ensure postgres outputs are present." }
if (-not $PostgresDatabaseName) { Fail "PostgreSQL database name unresolved. Set postgresDatabaseNameOut." }

Log "Creating Fabric mirror for PostgreSQL..."
Log "Workspace: $FabricWorkspaceName ($FabricWorkspaceId)"
Log "PostgreSQL: $PostgresServerFqdn / $PostgresDatabaseName"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Fail "Azure CLI not found. Please install Azure CLI."
}

if ($PostgresCredential) {
  $PostgresUser = $PostgresCredential.UserName
  $PostgresPasswordPlain = $PostgresCredential.GetNetworkCredential().Password
}

if ([string]::IsNullOrWhiteSpace($PostgresUser) -or [string]::IsNullOrWhiteSpace($PostgresPasswordPlain)) {
  if (-not [string]::IsNullOrWhiteSpace($KeyVaultName)) {
    Write-Host "Fetching PostgreSQL credentials from Key Vault '$KeyVaultName'..."

    if ([string]::IsNullOrWhiteSpace($PostgresUser)) {
      $PostgresUser = az keyvault secret show --vault-name $KeyVaultName --name $SecretNameUser --query value -o tsv
    }

    if ([string]::IsNullOrWhiteSpace($PostgresPasswordPlain)) {
      $PostgresPasswordPlain = az keyvault secret show --vault-name $KeyVaultName --name $SecretNameAuth --query value -o tsv
    }
  }
}

if ([string]::IsNullOrWhiteSpace($PostgresUser) -or [string]::IsNullOrWhiteSpace($PostgresPasswordPlain)) {
  throw "PostgreSQL credentials not provided. Supply -PostgresCredential or Key Vault name + secret names."
}

$mirrorDisplayName = if ([string]::IsNullOrWhiteSpace($MirrorName)) { "postgres-mirror-$PostgresDatabaseName" } else { $MirrorName }

$payloadJson = @{
  name = $mirrorDisplayName
  type = "PostgreSQL"
  server = $PostgresServerFqdn
  database = $PostgresDatabaseName
  auth = @{
    username = $PostgresUser
    password = $PostgresPasswordPlain
  }
} | ConvertTo-Json -Depth 6

Log "Mirror payload prepared (length=$($payloadJson.Length))."

if ($DryRun) {
  Log "Dry run enabled. Skipping mirror creation."
  return
}

# TODO: Replace with Fabric API when available for mirror creation.
# Example (placeholder, not currently functional):
# az rest --method post --uri "https://api.fabric.microsoft.com/v1/workspaces/$FabricWorkspaceId/mirrors" \
#   --headers "Content-Type=application/json" \
#   --body $payloadJson

Warn "Fabric mirror API not available yet. Payload prepared but request not sent."
