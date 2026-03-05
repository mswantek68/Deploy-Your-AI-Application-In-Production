using './main.bicep'

// ========================================
// AI LANDING ZONE PARAMETERS
// ========================================

// Per-service deployment toggles.
param deployToggles = {
  aiFoundry: true
  acaEnvironmentNsg: true
  agentNsg: true
  apiManagement: false
  apiManagementNsg: false
  appConfig: true
  appInsights: true
  applicationGateway: true
  applicationGatewayNsg: true
  applicationGatewayPublicIp: true
  bastionHost: true
  bastionNsg: true
  buildVm: true
  containerApps: true
  containerEnv: true
  containerRegistry: true
  cosmosDb: true
  devopsBuildAgentsNsg: true
  firewall: false
  groundingWithBingSearch: true
  jumpVm: true
  jumpboxNsg: true
  keyVault: true
  logAnalytics: true
  peNsg: true
  searchService: true
  storageAccount: true
  userDefinedRoutes: true
  virtualNetwork: true
  wafPolicy: true
}

// Existing resource IDs (empty means create new) Add any resource ID separated by a comma to utilize existing items like Keyvault, Storage, etc..
param resourceIds = {}

// Enable platform landing zone integration. When true, private DNS zones and private endpoints are managed by the platform landing zone.
param flagPlatformLandingZone = false

// Zero-trust switch: use `azd env set NETWORK_ISOLATION true|false` to control landing zone network isolation.
param networkIsolation = bool(readEnvironmentVariable('NETWORK_ISOLATION', 'true'))

// Template Spec version resource ID for the AI Landing Zone base deployment.
param aiLandingZoneTemplateSpecResourceId = readEnvironmentVariable('AI_LZ_TEMPLATE_SPEC_RESOURCE_ID', '')

// Environment name for resource naming (uses AZURE_ENV_NAME from azd).
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', '')

// Principal object ID used for RBAC assignments in the new landing zone template.
param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '')

// Principal type for RBAC assignments.
param principalType = 'User'

// Optional VM admin password used only if VM deployment toggles are enabled.
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')

// Collapse the environment name into an Azure-safe token.
var foundryEnvName = empty(environmentName)
  ? 'default'
  : toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))

param aiFoundryDefinition = {
  aiFoundryConfiguration: {
    accountName: 'ai-${foundryEnvName}'
    allowProjectManagement: true
    createCapabilityHosts: false
    disableLocalAuth: false
    project: {
      name: 'project-${foundryEnvName}'
      displayName: 'AI Foundry project (${environmentName})'
      description: 'Environment-scoped project created by the AI Landing Zone deployment.'
    }
  }
}



// AI Search settings for the default deployment.
param aiSearchDefinition = {
  name: toLower('search-${empty(environmentName) ? 'default' : replace(replace(environmentName, '_', '-'), ' ', '-')}')
  sku: 'standard'
  semanticSearch: 'free'
  managedIdentities: {
    systemAssigned: true
  }
  disableLocalAuth: true
}

param aiSearchAdditionalAccessObjectIds = []

// ========================================
// FABRIC CAPACITY PARAMETERS
// ========================================

// Preferred configuration: pick presets instead of uncommenting multiple params.
//
// fabricCapacityPreset:
// - 'create' => provision Fabric capacity in infra
// - 'byo'    => reuse existing Fabric capacity (provide fabricCapacityResourceId)
// - 'none'   => no Fabric capacity
//
// fabricWorkspacePreset:
// - 'create' => postprovision creates/configures workspace
// - 'byo'    => reuse existing workspace (provide fabricWorkspaceId and optionally fabricWorkspaceName)
// - 'none'   => no Fabric workspace automation, and OneLake indexing will be skipped
//
// Common setups:
// - Full setup: fabricCapacityPreset='create', fabricWorkspacePreset='create'
// - No Fabric:  fabricCapacityPreset='none',   fabricWorkspacePreset='none'
// - BYO both:   fabricCapacityPreset='byo',    fabricWorkspacePreset='byo'
var fabricCapacityPreset = 'create'
var fabricWorkspacePreset = fabricCapacityPreset

// Legacy toggle retained for back-compat with older docs/scripts
// Mode params below are the authoritative settings.
param deployFabricCapacity = fabricCapacityPreset != 'none'

param fabricCapacityMode = fabricCapacityPreset
param fabricCapacityResourceId = '' // required when fabricCapacityPreset='byo'

param fabricWorkspaceMode = fabricWorkspacePreset
param fabricWorkspaceId = '' // required when fabricWorkspacePreset='byo'
param fabricWorkspaceName = '' // optional (helpful for naming/UX)

// Fabric capacity SKU.

param fabricCapacitySku = 'F8'

// Fabric capacity admin members (email addresses or object IDs).
param fabricCapacityAdmins = []

// ========================================
// POSTGRESQL PARAMETERS (Post-ALZ Extension)
// ========================================

// Enable PostgreSQL provisioning after ALZ
param deployPostgres = false

// Modes: 'create' | 'byo' | 'none'
param postgresMode = deployPostgres ? 'create' : 'none'

// Required when postgresMode = 'byo'
param postgresResourceId = ''

// Optional: server name override (auto-generated if empty)
param postgresServerName = 'pg-${foundryEnvName}'

// Required when postgresMode = 'create'
param postgresSkuName = 'Standard_D2s_v3'
param postgresTier = 'GeneralPurpose'
param postgresAvailabilityZone = -1
param postgresVersion = '16'
param postgresHighAvailability = 'Disabled'
param postgresHighAvailabilityZone = -1

// Admin credentials (set via environment variables)
param postgresAdminLogin = readEnvironmentVariable('POSTGRES_ADMIN_LOGIN', '')
param postgresAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD', '')

// Optional database to create (used by post-provision mirror)
param postgresDatabaseName = ''

// Network isolation settings
param postgresEnableNetworkIsolation = true
param postgresPrivateEndpointSubnetResourceId = '' // defaults to ALZ pe-subnet
param postgresPrivateDnsZoneResourceId = '' // defaults to new privatelink zone

// ========================================
// FABRIC MIRROR PARAMETERS (Post-Provision)
// ========================================

// Enable mirror only when Fabric workspace automation is enabled
param fabricMirrorEnabled = fabricWorkspaceMode != 'none'

// Optional: mirror name override
param fabricMirrorName = ''

// Key Vault secret names for PostgreSQL credentials (preferred)
param fabricMirrorPostgresUsernameSecretName = 'postgres-admin-username'
param fabricMirrorPostgresPasswordSecretName = 'postgres-admin-password'

// ========================================
// PURVIEW PARAMETERS (Optional)
// ========================================

// Existing Purview account resource ID (in different subscription if needed).
param purviewAccountResourceId = ''

// Purview collection name (leave empty to auto-generate from environment name).
param purviewCollectionName = ''
