// ================================================
// MINIMAL INFRASTRUCTURE FOR LOCAL DEVELOPMENT
// ================================================
targetScope = 'resourceGroup'

// Parameters
@description('Azure region for resources')
param location string = 'swedencentral'

@description('Environment name for resource naming')
param environmentName string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'LocalDevelopment'
  Project: 'MathTutor'
  ManagedBy: 'azd'
}

// Variables - nombres más largos y únicos
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var aiHubName = 'aihub${uniqueSuffix}'
var aiProjectName = 'aiproj${uniqueSuffix}'
var storageAccountName = 'st${uniqueSuffix}${environmentName}'
var keyVaultName = 'kv${uniqueSuffix}${environmentName}'
var appInsightsName = 'appi${uniqueSuffix}'
var logAnalyticsName = 'log${uniqueSuffix}'

// Asegurar nombres válidos
var validStorageName = toLower(take(replace(storageAccountName, '-', ''), 24))
var validKeyVaultName = take(keyVaultName, 24)

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: validStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'PUT', 'POST', 'DELETE', 'HEAD', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

resource imageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'images'
  properties: {
    publicAccess: 'Blob'
  }
}

// Key Vault con configuración simplificada
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: validKeyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    publicNetworkAccess: 'Enabled'
  }
}

// AI Hub con dependencias explícitas
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiHubName
  location: location
  tags: tags
  kind: 'Hub'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: 'Math Tutor Dev Hub'
    description: 'AI Hub for Math Tutor local development'
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    applicationInsights: appInsights.id
    publicNetworkAccess: 'Enabled'
    v1LegacyMode: false
    managedNetwork: {
      isolationMode: 'Disabled'
    }
  }
  dependsOn: [
    keyVault
    storageAccount
    appInsights
  ]
}

// AI Project
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiProjectName
  location: location
  tags: tags
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: 'Math Tutor Dev Project'
    description: 'AI Project for Math Tutor development'
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    aiHub
  ]
}

// Outputs
output STORAGE_ACCOUNT_NAME string = storageAccount.name
output STORAGE_ACCOUNT_KEY string = listKeys(storageAccount.id, '2023-01-01').keys[0].value
output KEY_VAULT_NAME string = keyVault.name
output AI_HUB_NAME string = aiHub.name
output AI_PROJECT_NAME string = aiProject.name
output PROJECT_ENDPOINT string = 'https://${aiProject.name}.${location}.inference.ml.azure.com'
output APP_INSIGHTS_NAME string = appInsights.name
output LOG_ANALYTICS_NAME string = logAnalytics.name
