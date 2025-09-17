// ================================================
// MINIMAL INFRASTRUCTURE FOR LOCAL DEVELOPMENT
// ================================================
// This creates only the essential Azure resources needed for local development:
// - AI Hub and Project (for the agent)
// - Storage Account (for images)
// - Key Vault (required by AI Hub)
// - Application Insights (for telemetry)

targetScope = 'subscription'

// Parameters
@description('Name of the resource group')
param resourceGroupName string = 'rg-aifoundry-local'

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

// Variables
var uniqueSuffix = uniqueString(subscription().id, environmentName, location)
var aiHubName = 'hub-local-${uniqueSuffix}'
var aiProjectName = 'proj-tutor-local-${uniqueSuffix}'
var storageAccountName = 'stlocal${replace(uniqueSuffix, '-', '')}' // Storage names can't have dashes
var keyVaultName = 'kv-local-${uniqueSuffix}'
var appInsightsName = 'appi-local-${uniqueSuffix}'
var logAnalyticsName = 'log-local-${uniqueSuffix}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Log Analytics Workspace (required for Application Insights)
module logAnalytics 'modules-local/log-analytics.bicep' = {
  scope: rg
  name: 'logAnalyticsDeploy'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
}

// Application Insights (required for AI Hub)
module appInsights 'modules-local/app-insights.bicep' = {
  scope: rg
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
  scope: rg
  name: 'keyVaultDeploy'
  params: {
    name: keyVaultName
    location: location
    tags: tags
  }
}

// Storage Account
module storage 'modules-local/storage.bicep' = {
  scope: rg
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
  scope: rg
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
  scope: rg
  name: 'aiProjectDeploy'
  params: {
    name: aiProjectName
    location: location
    tags: tags
    hubId: aiHub.outputs.id
  }
}

// Outputs - These will be used by azd to populate environment variables
output PROJECT_ENDPOINT string = aiProject.outputs.endpoint
output STORAGE_ACCOUNT_NAME string = storage.outputs.name
output STORAGE_ACCOUNT_KEY string = storage.outputs.key
output STORAGE_CONNECTION_STRING string = storage.outputs.connectionString
output KEY_VAULT_NAME string = keyVault.outputs.name
output KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AI_HUB_NAME string = aiHub.outputs.name
output AI_PROJECT_NAME string = aiProject.outputs.name
output APPLICATION_INSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output RESOURCE_GROUP_NAME string = rg.name

// Display important information
output IMPORTANT_INFO object = {
  message: 'Local development resources created successfully!'
  next_steps: [
    '1. Run: python setup-and-verify.py'
    '2. Start backend: cd backend && python main.py'
    '3. Start frontend: cd frontend && python app.py'
    '4. Open browser: http://localhost:7860'
  ]
  resource_group: rg.name
  ai_project: aiProjectName
  storage_account: storageAccountName
}
