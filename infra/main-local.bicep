// ================================================
// MINIMAL INFRASTRUCTURE FOR LOCAL DEVELOPMENT
// ================================================
// This creates only the essential Azure resources needed for local development:
// - AI Hub and Project (for the agent)
// - Storage Account (for images)
// - Key Vault (required by AI Hub)
// - Application Insights (for telemetry)

// IMPORTANTE: Cambiado de 'subscription' a 'resourceGroup'
targetScope = 'resourceGroup'

// Parameters
@description('Azure region for resources')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
  'centralus'
  'northeurope'
  'westeurope'
  'swedencentral'
  'uksouth'
  'australiaeast'
  'southeastasia'
  'japaneast'
])
param location string = 'swedencentral'

@description('Environment name for resource naming')
param environmentName string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'LocalDevelopment'
  Project: 'MathTutor'
  ManagedBy: 'azd'
}

// Variables - usando resourceGroup().name para obtener el nombre
var uniqueSuffix = uniqueString(resourceGroup().id, environmentName, location)
var aiHubName = 'hub-local-${uniqueSuffix}'
var aiProjectName = 'proj-tutor-local-${uniqueSuffix}'
var storageAccountName = toLower('stlocal${replace(uniqueSuffix, '-', '')}')
var keyVaultName = 'kv-local-${uniqueSuffix}'
var appInsightsName = 'appi-local-${uniqueSuffix}'
var logAnalyticsName = 'log-local-${uniqueSuffix}'

// Log Analytics Workspace (required for Application Insights)
module logAnalytics 'modules-local/log-analytics.bicep' = {
  name: 'logAnalyticsDeploy'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
}

// Application Insights (required for AI Hub)
module appInsights 'modules-local/app-insights.bicep' = {
  name: 'appInsightsDeploy'
  params: {
    name: appInsightsName
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    tags: tags
  }
}

// Key Vault (required for AI Hub)
module keyVault 'modules-local/key-vault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    name: keyVaultName
    location: location
    tags: tags
  }
}

// Storage Account
module storage 'modules-local/storage.bicep' = {
  name: 'storageDeploy'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    containerName: 'images'
  }
}

// AI Hub
module aiHub 'modules-local/ai-hub.bicep' = {
  name: 'aiHubDeploy'
  params: {
    name: aiHubName
    location: location
    tags: tags
    storageAccountId: storage.outputs.id
    keyVaultId: keyVault.outputs.id
    applicationInsightsId: appInsights.outputs.id
  }
}

// AI Project
module aiProject 'modules-local/ai-project.bicep' = {
  name: 'aiProjectDeploy'
  params: {
    name: aiProjectName
    location: location
    tags: tags
    hubId: aiHub.outputs.id
  }
}

// Outputs principales para el proyecto
output PROJECT_ENDPOINT string = aiProject.outputs.endpoint
output STORAGE_ACCOUNT_NAME string = storage.outputs.name
output STORAGE_ACCOUNT_KEY string = storage.outputs.key
output KEY_VAULT_NAME string = keyVault.outputs.name
output AI_HUB_NAME string = aiHub.outputs.name
output AI_PROJECT_NAME string = aiProject.outputs.name

// Información adicional
output DEPLOYMENT_INFO object = {
  message: 'Local development resources created successfully!'
  resource_group: resourceGroup().name
  ai_project: aiProjectName
  storage_account: storageAccountName
  next_steps: [
    '1. The .env file has been created automatically'
    '2. Run: python setup-and-verify.py'
    '3. Start services: ./run-local.sh or run-local.bat'
    '4. Open browser: http://localhost:7860'
  ]
}
