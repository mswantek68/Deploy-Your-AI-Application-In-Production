// ================================================
// Main Deployment Wrapper
// ================================================
// Orchestrates:
// 1. AI Landing Zone (base infrastructure) - ALL parameters passed through
// 2. Fabric Capacity (extension) - deployed in same template
// ================================================

targetScope = 'resourceGroup'
metadata description = 'Deploys AI Landing Zone with Fabric capacity extension'
import * as types from '../submodules/ai-landing-zone/bicep/infra/common/types.bicep'

// ========================================
// PARAMETERS - AI LANDING ZONE (Required)
// ========================================

@description('Per-service deployment toggles for the AI Landing Zone submodule.')
param deployToggles object = {}

@description('Optional. Enable platform landing zone integration.')
param flagPlatformLandingZone bool = false

@description('Optional. Existing resource IDs to reuse.')
param resourceIds types.resourceIdsType = {}

@description('Optional. Azure region for resources.')
param location string = resourceGroup().location

@description('Optional. Environment name for resource naming.')
param environmentName string = ''

@description('Optional. Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name for resources.')
param baseName string = substring(resourceToken, 0, 12)

@description('Optional. AI Search settings.')
param aiSearchDefinition types.kSAISearchDefinitionType?

@description('Optional. Additional Entra object IDs (users or groups) granted AI Search contributor roles.')
param aiSearchAdditionalAccessObjectIds array = []

@description('Optional. Enable telemetry.')
param enableTelemetry bool = true

@description('Optional. Tags for all resources.')
param tags object = {}

// All other optional parameters from AI Landing Zone - pass as needed
@description('Optional. Private DNS Zone configuration.')
param privateDnsZonesDefinition types.privateDnsZonesDefinitionType = {}

@description('Optional. Enable Defender for AI.')
param enableDefenderForAI bool = true

@description('Optional. NSG definitions per subnet.')
param nsgDefinitions types.nsgPerSubnetDefinitionsType?

@description('Optional. Virtual Network configuration.')
param vNetDefinition types.vNetDefinitionType?

@description('Optional. AI Foundry configuration.')
param aiFoundryDefinition types.aiFoundryDefinitionType = {}

@description('Optional. API Management configuration.')
param apimDefinition types.apimDefinitionType?

// Add more parameters as needed from AI Landing Zone...

// ========================================
// PARAMETERS - FABRIC EXTENSION
// ========================================

@description('Deploy Fabric capacity')
param deployFabricCapacity bool = true

@description('Fabric capacity mode. Use create to provision a capacity, byo to reuse an existing capacity, or none to disable Fabric capacity.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricCapacityMode string = (deployFabricCapacity ? 'create' : 'none')

@description('Optional. Existing Fabric capacity resource ID (required when fabricCapacityMode=byo).')
param fabricCapacityResourceId string = ''

@description('Fabric workspace mode. Use create to create a workspace in postprovision, byo to reuse an existing workspace, or none to disable Fabric workspace automation.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricWorkspaceMode string = (fabricCapacityMode == 'none' ? 'none' : 'create')

@description('Optional. Existing Fabric workspace ID (GUID) (required when fabricWorkspaceMode=byo).')
param fabricWorkspaceId string = ''

@description('Optional. Existing Fabric workspace name (used when fabricWorkspaceMode=byo).')
param fabricWorkspaceName string = ''

@description('Fabric capacity SKU')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param fabricCapacitySku string = 'F8'

@description('Fabric capacity admin members')
param fabricCapacityAdmins array = []

// ========================================
// PARAMETERS - POSTGRESQL EXTENSION (Post-ALZ)
// ========================================

@description('Deploy PostgreSQL')
param deployPostgres bool = false

@description('PostgreSQL mode. Use create to provision, byo to reuse, or none to disable.')
@allowed([
  'create'
  'byo'
  'none'
])
param postgresMode string = (deployPostgres ? 'create' : 'none')

@description('Optional. Existing PostgreSQL resource ID (required when postgresMode=byo).')
param postgresResourceId string = ''

@description('Optional. Server name override (auto-generated if empty).')
param postgresServerName string = ''

@description('PostgreSQL SKU name. Example: Standard_D2s_v3')
param postgresSkuName string = 'Standard_D2s_v3'

@description('PostgreSQL tier for the chosen SKU.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgresTier string = 'GeneralPurpose'

@description('PostgreSQL availability zone. Use -1 for no preference.')
@allowed([
  -1
  1
  2
  3
])
param postgresAvailabilityZone int = -1

@description('PostgreSQL server version.')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
  '17'
  '18'
])
param postgresVersion string = '16'

@description('PostgreSQL high availability mode.')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param postgresHighAvailability string = 'Disabled'

@description('PostgreSQL standby availability zone for HA. Use -1 for no preference.')
@allowed([
  -1
  1
  2
  3
])
param postgresHighAvailabilityZone int = -1

@description('PostgreSQL administrator login name (required for create).')
param postgresAdminLogin string = ''

@description('PostgreSQL administrator login password (required for create).')
@secure()
param postgresAdminPassword string = ''

@description('Optional database name to create.')
param postgresDatabaseName string = ''

@description('Enable network isolation for PostgreSQL (private endpoint + private DNS).')
param postgresEnableNetworkIsolation bool = true

@description('Optional. Private endpoint subnet resource ID. Defaults to ALZ pe-subnet.')
param postgresPrivateEndpointSubnetResourceId string = ''

@description('Optional. Private DNS zone resource ID. If empty, a new zone is created.')
param postgresPrivateDnsZoneResourceId string = ''

@description('PostgreSQL public network access setting.')
@allowed([
  'Enabled'
  'Disabled'
])
param postgresPublicNetworkAccess string = (postgresEnableNetworkIsolation ? 'Disabled' : 'Enabled')

// ========================================
// PARAMETERS - FABRIC MIRROR (Post-Provision)
// ========================================

@description('Enable Fabric mirror creation (post-provision).')
param fabricMirrorEnabled bool = (fabricWorkspaceMode != 'none')

@description('Optional. Fabric mirror name override.')
param fabricMirrorName string = ''

@description('Key Vault secret name for PostgreSQL username (mirror).')
param fabricMirrorPostgresUsernameSecretName string = 'postgres-admin-username'

@description('Key Vault secret name for PostgreSQL password (mirror).')
param fabricMirrorPostgresPasswordSecretName string = 'postgres-admin-password'

@description('Optional. Existing Purview account resource ID')
param purviewAccountResourceId string = ''

@description('Optional. Existing Purview collection name')
param purviewCollectionName string = ''

// ========================================
// AI LANDING ZONE DEPLOYMENT
// ========================================

module aiLandingZone '../submodules/ai-landing-zone/bicep/infra/main.bicep' = {
  name: 'ai-landing-zone'
  params: {
    deployToggles: deployToggles
    flagPlatformLandingZone: flagPlatformLandingZone
    resourceIds: resourceIds
    location: location
    resourceToken: resourceToken
    baseName: baseName
    enableTelemetry: enableTelemetry
    tags: tags
    privateDnsZonesDefinition: privateDnsZonesDefinition
    enableDefenderForAI: enableDefenderForAI
    nsgDefinitions: nsgDefinitions
    vNetDefinition: vNetDefinition
    aiFoundryDefinition: aiFoundryDefinition
    apimDefinition: apimDefinition
    aiSearchDefinition: aiSearchDefinition
    // Add more parameters as needed...
  }
}

// ========================================
// FABRIC CAPACITY DEPLOYMENT
// ========================================

var effectiveFabricCapacityMode = fabricCapacityMode
var effectiveFabricWorkspaceMode = fabricWorkspaceMode

var envSlugSanitized = replace(replace(replace(replace(replace(replace(replace(replace(toLower(environmentName), ' ', ''), '-', ''), '_', ''), '.', ''), '/', ''), '\\', ''), ':', ''), ',', '')

var envSlugTrimmed = substring(envSlugSanitized, 0, min(40, length(envSlugSanitized)))
var capacityNameBase = !empty(envSlugTrimmed) ? 'fabric${envSlugTrimmed}' : 'fabric${baseName}'
var capacityName = substring(capacityNameBase, 0, min(50, length(capacityNameBase)))

module fabricCapacity 'modules/fabric-capacity.bicep' = if (effectiveFabricCapacityMode == 'create') {
  name: 'fabric-capacity'
  params: {
    capacityName: capacityName
    location: location
    sku: fabricCapacitySku
    adminMembers: fabricCapacityAdmins
    tags: tags
  }
  dependsOn: [
    aiLandingZone
  ]
}

// ========================================
// POSTGRESQL DEPLOYMENT (POST-ALZ)
// ========================================

var effectivePostgresMode = postgresMode
var postgresNameBase = !empty(envSlugTrimmed) ? 'pg${envSlugTrimmed}' : 'pg${baseName}'
var effectivePostgresServerName = !empty(postgresServerName)
  ? toLower(postgresServerName)
  : toLower(substring(postgresNameBase, 0, min(63, length(postgresNameBase))))

var postgresPrivateDnsZoneName = 'privatelink.postgres.database.azure.com'
var defaultPostgresPeSubnetResourceId = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/pe-subnet'
var effectivePostgresPeSubnetResourceId = !empty(postgresPrivateEndpointSubnetResourceId)
  ? postgresPrivateEndpointSubnetResourceId
  : defaultPostgresPeSubnetResourceId

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (postgresEnableNetworkIsolation && !flagPlatformLandingZone && empty(postgresPrivateDnsZoneResourceId)) {
  name: postgresPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource postgresPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (postgresEnableNetworkIsolation && !flagPlatformLandingZone && empty(postgresPrivateDnsZoneResourceId)) {
  name: '${effectivePostgresServerName}-vnet-link'
  parent: postgresPrivateDnsZone
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: aiLandingZone.outputs.virtualNetworkResourceId
    }
  }
}

var effectivePostgresPrivateDnsZoneId = postgresEnableNetworkIsolation
  ? (!empty(postgresPrivateDnsZoneResourceId) ? postgresPrivateDnsZoneResourceId : postgresPrivateDnsZone.id)
  : ''

module postgresFlexibleServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.1' = if (effectivePostgresMode == 'create') {
  name: 'postgres-flexible-server'
  params: {
    name: effectivePostgresServerName
    availabilityZone: postgresAvailabilityZone
    skuName: postgresSkuName
    tier: postgresTier
    location: location
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    version: postgresVersion
    highAvailability: postgresHighAvailability
    highAvailabilityZone: postgresHighAvailabilityZone
    publicNetworkAccess: postgresPublicNetworkAccess
    databases: !empty(postgresDatabaseName)
      ? [
          {
            name: postgresDatabaseName
          }
        ]
      : []
    privateEndpoints: postgresEnableNetworkIsolation
      ? [
          {
            name: 'pep-${effectivePostgresServerName}'
            subnetResourceId: effectivePostgresPeSubnetResourceId
            service: 'postgresqlServer'
            privateDnsZoneGroup: {
              name: 'default'
              privateDnsZoneGroupConfigs: [
                {
                  name: 'postgresql'
                  privateDnsZoneResourceId: effectivePostgresPrivateDnsZoneId
                }
              ]
            }
          }
        ]
      : []
    tags: tags
  }
}

// ========================================
// OUTPUTS - Pass through from AI Landing Zone
// ========================================

output virtualNetworkResourceId string = aiLandingZone.outputs.virtualNetworkResourceId
output keyVaultResourceId string = aiLandingZone.outputs.keyVaultResourceId
output storageAccountResourceId string = aiLandingZone.outputs.storageAccountResourceId
output aiFoundryProjectName string = aiLandingZone.outputs.aiFoundryProjectName
output logAnalyticsWorkspaceResourceId string = aiLandingZone.outputs.logAnalyticsWorkspaceResourceId
output aiSearchResourceId string = aiLandingZone.outputs.aiSearchResourceId
output aiSearchName string = aiLandingZone.outputs.aiSearchName
output aiSearchAdditionalAccessObjectIds array = aiSearchAdditionalAccessObjectIds

// Subnet IDs (constructed from VNet ID using AI Landing Zone naming convention)
output peSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/pe-subnet'
output jumpboxSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/jumpbox-subnet'
output agentSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/agent-subnet'

// Fabric outputs
output fabricCapacityModeOut string = effectiveFabricCapacityMode
output fabricWorkspaceModeOut string = effectiveFabricWorkspaceMode

var effectiveFabricCapacityResourceId = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.resourceId
  : (effectiveFabricCapacityMode == 'byo' ? fabricCapacityResourceId : '')

var effectiveFabricCapacityName = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.name
  : (!empty(effectiveFabricCapacityResourceId) ? last(split(effectiveFabricCapacityResourceId, '/')) : '')

output fabricCapacityResourceIdOut string = effectiveFabricCapacityResourceId
output fabricCapacityName string = effectiveFabricCapacityName
output fabricCapacityId string = effectiveFabricCapacityResourceId

// PostgreSQL outputs
output postgresModeOut string = effectivePostgresMode

var effectivePostgresResourceId = effectivePostgresMode == 'create'
  ? resourceId('Microsoft.DBforPostgreSQL/flexibleServers', effectivePostgresServerName)
  : (effectivePostgresMode == 'byo' ? postgresResourceId : '')

var effectivePostgresName = effectivePostgresMode == 'create'
  ? effectivePostgresServerName
  : (!empty(effectivePostgresResourceId) ? last(split(effectivePostgresResourceId, '/')) : '')

var effectivePostgresFqdn = effectivePostgresMode == 'create'
  ? '${effectivePostgresServerName}.postgres.database.azure.com'
  : ''

output postgresResourceIdOut string = effectivePostgresResourceId
output postgresNameOut string = effectivePostgresName
output postgresFqdnOut string = effectivePostgresFqdn
output postgresDatabaseNameOut string = postgresDatabaseName

// Fabric mirror outputs (post-provision)
output fabricMirrorEnabledOut bool = fabricMirrorEnabled
output fabricMirrorNameOut string = fabricMirrorName
output fabricMirrorSecretReferences object = {
  usernameSecretName: fabricMirrorPostgresUsernameSecretName
  passwordSecretName: fabricMirrorPostgresPasswordSecretName
}

var effectiveFabricWorkspaceName = effectiveFabricWorkspaceMode == 'byo'
  ? (!empty(fabricWorkspaceName) ? fabricWorkspaceName : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}'))
  : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}')

var effectiveFabricWorkspaceId = effectiveFabricWorkspaceMode == 'byo' ? fabricWorkspaceId : ''

output fabricWorkspaceNameOut string = effectiveFabricWorkspaceName
output fabricWorkspaceIdOut string = effectiveFabricWorkspaceId

output desiredFabricDomainName string = !empty(environmentName) ? 'domain-${environmentName}' : 'domain-${baseName}'
output desiredFabricWorkspaceName string = effectiveFabricWorkspaceName

// Purview outputs (for post-provision scripts)
output purviewAccountResourceId string = purviewAccountResourceId
output purviewCollectionName string = !empty(purviewCollectionName) ? purviewCollectionName : (!empty(environmentName) ? 'collection-${environmentName}' : 'collection-${baseName}')
