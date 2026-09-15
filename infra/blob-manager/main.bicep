@description('Name of the App Service app.')
param appName string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('App Service plan name.')
param appServicePlanName string = '${appName}-plan'

@description('App Service plan SKU.')
param appServiceSku string = 'P1v3'

@description('Existing delegated subnet resource ID for App Service VNet integration.')
param appServiceSubnetResourceId string

@description('Storage account name used by the blob manager.')
param storageAccountName string

@description('Blob container name managed by the app.')
param blobContainerName string

@secure()
@description('Admin key required to access blob management routes.')
param adminAccessKey string

@description('Runtime stack for Linux web app.')
param linuxFxVersion string = 'NODE|20-lts'

@description('Session cookie name used by the app.')
param sessionCookieName string = 'blob-manager-admin'

@description('Whether secure session cookies are required (recommended true for HTTPS).')
param sessionCookieSecure bool = true

@description('Allowed CORS origins for App Service. Use empty array to disable explicit CORS settings.')
param corsAllowedOrigins array = []

resource serverFarm 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServiceSku
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverFarm.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '3000'
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'BLOB_CONTAINER_NAME'
          value: blobContainerName
        }
        {
          name: 'ADMIN_ACCESS_KEY'
          value: adminAccessKey
        }
        {
          name: 'SESSION_COOKIE_NAME'
          value: sessionCookieName
        }
        {
          name: 'SESSION_COOKIE_SECURE'
          value: string(sessionCookieSecure)
        }
      ]
    }
    virtualNetworkSubnetId: appServiceSubnetResourceId
  }
}

resource webAppCors 'Microsoft.Web/sites/config@2023-01-01' = if (length(corsAllowedOrigins) > 0) {
  name: 'web'
  parent: webApp
  properties: {
    cors: {
      allowedOrigins: corsAllowedOrigins
      supportCredentials: true
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource blobContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, 'storage-blob-data-contributor')
  scope: storageAccount
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

output webAppName string = webApp.name
output webAppPrincipalId string = webApp.identity.principalId
