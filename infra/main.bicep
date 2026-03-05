// ================================================
// Main Deployment Wrapper
// ================================================
// Orchestrates:
// 1. AI Landing Zone (base infrastructure) - ALL parameters passed through
// 2. Fabric Capacity (extension) - deployed in same template
// ================================================

targetScope = 'resourceGroup'
metadata description = 'Deploys AI Landing Zone with Fabric capacity extension'

// ========================================
// PARAMETERS - AI LANDING ZONE (Required)
// ========================================

@description('Per-service deployment toggles for the AI Landing Zone submodule.')
param deployToggles object = {}

@description('Optional. Enable platform landing zone integration.')
param flagPlatformLandingZone bool = false

@description('Optional. Existing resource IDs to reuse.')
param resourceIds object = {}

@description('Enable zero-trust network isolation in the landing zone deployment.')
param networkIsolation bool = true

@description('Resource ID of the AI Landing Zone Template Spec version to deploy (for example: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Resources/templateSpecs/<name>/versions/<version>).')
param aiLandingZoneTemplateSpecResourceId string = ''

@description('Optional. Azure region for resources.')
param location string = resourceGroup().location

@description('Optional. Environment name for resource naming.')
param environmentName string = ''

@description('Optional. Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name for resources.')
param baseName string = substring(resourceToken, 0, 12)

@description('Optional. AI Search settings.')
param aiSearchDefinition object = {}

@description('Optional. Additional Entra object IDs (users or groups) granted AI Search contributor roles.')
param aiSearchAdditionalAccessObjectIds array = []

@description('Optional. Enable telemetry.')
param enableTelemetry bool = true

@description('Optional. Tags for all resources.')
param tags object = {}

// All other optional parameters from AI Landing Zone - pass as needed
@description('Optional. Private DNS Zone configuration.')
param privateDnsZonesDefinition object = {}

@description('Optional. Enable Defender for AI.')
param enableDefenderForAI bool = true

@description('Optional. NSG definitions per subnet.')
param nsgDefinitions object = {}

@description('Optional. Virtual Network configuration.')
param vNetDefinition object = {}

@description('Optional. AI Foundry configuration.')
param aiFoundryDefinition object = {}

@description('Object ID of the deployment principal for role assignments in the landing zone module.')
param principalId string = ''

@description('Principal type for role assignments.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param principalType string = 'User'

@description('Optional override for model deployments consumed by the new landing zone template.')
param modelDeploymentList array = []

@description('Optional container apps configuration list consumed by the new landing zone template.')
param containerAppsList array = []

@description('Optional Cosmos DB container list consumed by the new landing zone template.')
param databaseContainersList array = []

@secure()
@description('Optional VM admin password consumed by the new landing zone template when VM deployment is enabled.')
param vmAdminPassword string = ''

@description('Optional Storage Account container list consumed by the new landing zone template.')
param storageAccountContainersList array = []

@description('Optional VM user name consumed by the new landing zone template when VM deployment is enabled.')
param vmUserName string = ''

@description('Optional VM name consumed by the new landing zone template when VM deployment is enabled.')
param vmName string = ''

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

var effectiveEnvironmentName = !empty(environmentName) ? environmentName : deployment().name
var existingAiSearchResourceId = string(resourceIds.?searchServiceResourceId ?? '')
var existingKeyVaultResourceId = string(resourceIds.?keyVaultResourceId ?? '')
var existingStorageAccountResourceId = string(resourceIds.?storageAccountResourceId ?? '')
var existingCosmosDbResourceId = string(resourceIds.?cosmosDbResourceId ?? '')

var effectiveAiFoundryAccountName = string(aiFoundryDefinition.?aiFoundryConfiguration.?accountName ?? 'aif-${resourceToken}')
var effectiveAiFoundryProjectName = string(aiFoundryDefinition.?aiFoundryConfiguration.?project.?name ?? 'aifp-${resourceToken}')
var effectiveAiSearchName = !empty(existingAiSearchResourceId)
  ? last(split(existingAiSearchResourceId, '/'))
  : string(aiSearchDefinition.?name ?? 'srch-${resourceToken}')
var effectiveStorageAccountName = !empty(existingStorageAccountResourceId)
  ? last(split(existingStorageAccountResourceId, '/'))
  : 'st${resourceToken}'
var effectiveKeyVaultName = !empty(existingKeyVaultResourceId)
  ? last(split(existingKeyVaultResourceId, '/'))
  : 'kv-${resourceToken}'
var effectiveLogAnalyticsWorkspaceName = 'log-${resourceToken}'
var effectiveVnetName = string(vNetDefinition.?name ?? 'vnet-${resourceToken}')

var effectiveDeployAiFoundry = bool(deployToggles.?aiFoundry ?? true)
var effectiveDeployAifAgentService = bool(aiFoundryDefinition.?aiFoundryConfiguration.?createCapabilityHosts ?? false)
var effectiveDeployVm = bool((deployToggles.?buildVm ?? false) || (deployToggles.?jumpVm ?? false))
var effectiveModelDeploymentList = !empty(aiFoundryDefinition.?aiModelDeployments ?? [])
  ? aiFoundryDefinition.aiModelDeployments
  : modelDeploymentList

resource aiLandingZoneDeployment 'Microsoft.Resources/deployments@2024-03-01' = {
  name: 'ai-landing-zone'
  properties: {
    mode: 'Incremental'
    templateLink: {
      id: aiLandingZoneTemplateSpecResourceId
    }
    parameters: {
      environmentName: {
        value: effectiveEnvironmentName
      }
      location: {
        value: location
      }
      resourceToken: {
        value: resourceToken
      }
      principalId: {
        value: principalId
      }
      principalType: {
        value: principalType
      }
      deploymentTags: {
        value: tags
      }
      networkIsolation: {
        value: networkIsolation
      }
      deployAiFoundry: {
        value: effectiveDeployAiFoundry
      }
      deployAfProject: {
        value: effectiveDeployAiFoundry
      }
      deployAAfAgentSvc: {
        value: effectiveDeployAifAgentService
      }
      deploySearchService: {
        value: bool(deployToggles.?searchService ?? true)
      }
      deployStorageAccount: {
        value: bool(deployToggles.?storageAccount ?? true)
      }
      deployKeyVault: {
        value: bool(deployToggles.?keyVault ?? true)
      }
      deployLogAnalytics: {
        value: bool(deployToggles.?logAnalytics ?? true)
      }
      deployAppInsights: {
        value: bool(deployToggles.?appInsights ?? true)
      }
      deployContainerRegistry: {
        value: bool(deployToggles.?containerRegistry ?? true)
      }
      deployContainerEnv: {
        value: bool(deployToggles.?containerEnv ?? true)
      }
      deployContainerApps: {
        value: bool(deployToggles.?containerApps ?? true)
      }
      deployCosmosDb: {
        value: bool(deployToggles.?cosmosDb ?? true)
      }
      deployGroundingWithBing: {
        value: bool(deployToggles.?groundingWithBingSearch ?? false)
      }
      deployApim: {
        value: bool(deployToggles.?apiManagement ?? false)
      }
      deployNsgs: {
        value: bool(deployToggles.?virtualNetwork ?? true)
      }
      deploySubnets: {
        value: bool(deployToggles.?virtualNetwork ?? true)
      }
      deployVM: {
        value: effectiveDeployVm
      }
      deployVmKeyVault: {
        value: bool(deployToggles.?keyVault ?? true)
      }
      keyVaultResourceId: {
        value: existingKeyVaultResourceId
      }
      aiSearchResourceId: {
        value: existingAiSearchResourceId
      }
      aiFoundryStorageAccountResourceId: {
        value: existingStorageAccountResourceId
      }
      aiFoundryCosmosDBAccountResourceId: {
        value: existingCosmosDbResourceId
      }
      aiFoundryAccountName: {
        value: effectiveAiFoundryAccountName
      }
      aiFoundryProjectName: {
        value: effectiveAiFoundryProjectName
      }
      searchServiceName: {
        value: effectiveAiSearchName
      }
      storageAccountName: {
        value: effectiveStorageAccountName
      }
      keyVaultName: {
        value: effectiveKeyVaultName
      }
      logAnalyticsWorkspaceName: {
        value: effectiveLogAnalyticsWorkspaceName
      }
      vnetName: {
        value: effectiveVnetName
      }
      modelDeploymentList: {
        value: effectiveModelDeploymentList
      }
      containerAppsList: {
        value: containerAppsList
      }
      databaseContainersList: {
        value: databaseContainersList
      }
      storageAccountContainersList: {
        value: storageAccountContainersList
      }
      vmAdminPassword: {
        value: vmAdminPassword
      }
      vmUserName: {
        value: vmUserName
      }
      vmName: {
        value: vmName
      }
    }
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
    aiLandingZoneDeployment
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
var virtualNetworkResourceIdComputed = resourceId('Microsoft.Network/virtualNetworks', effectiveVnetName)
var defaultPostgresPeSubnetResourceId = '${virtualNetworkResourceIdComputed}/subnets/pe-subnet'
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
      id: virtualNetworkResourceIdComputed
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

output virtualNetworkResourceId string = virtualNetworkResourceIdComputed
output keyVaultResourceId string = !empty(existingKeyVaultResourceId) ? existingKeyVaultResourceId : resourceId('Microsoft.KeyVault/vaults', effectiveKeyVaultName)
output storageAccountResourceId string = !empty(existingStorageAccountResourceId) ? existingStorageAccountResourceId : resourceId('Microsoft.Storage/storageAccounts', effectiveStorageAccountName)
output aiFoundryProjectName string = effectiveAiFoundryProjectName
output logAnalyticsWorkspaceResourceId string = resourceId('Microsoft.OperationalInsights/workspaces', effectiveLogAnalyticsWorkspaceName)
output aiSearchResourceId string = !empty(existingAiSearchResourceId) ? existingAiSearchResourceId : resourceId('Microsoft.Search/searchServices', effectiveAiSearchName)
output aiSearchName string = effectiveAiSearchName
output aiSearchAdditionalAccessObjectIds array = aiSearchAdditionalAccessObjectIds

// Subnet IDs (constructed from VNet ID using AI Landing Zone naming convention)
output peSubnetResourceId string = '${virtualNetworkResourceIdComputed}/subnets/pe-subnet'
output jumpboxSubnetResourceId string = '${virtualNetworkResourceIdComputed}/subnets/jumpbox-subnet'
output agentSubnetResourceId string = '${virtualNetworkResourceIdComputed}/subnets/agent-subnet'

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
