param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $false)]
  [string]$TemplateFile = "infra/blob-manager/main.bicep",

  [Parameter(Mandatory = $false)]
  [string]$ParameterFile = "infra/blob-manager/main.parameters.sample.json"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) is required to run this script."
}

Write-Host "Deploying blob manager infrastructure to resource group '$ResourceGroupName'..."

az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file $TemplateFile `
  --parameters @$ParameterFile

if ($LASTEXITCODE -ne 0) {
  throw "Blob manager deployment failed."
}

Write-Host "Blob manager deployment completed successfully."
