param name string
param location string
param tags object = {}
param storageAccountId string
param keyVaultId string
param applicationInsightsId string

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: name
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
    friendlyName: 'Math Tutor Local Dev Hub'
    description: 'AI Hub for local development of Math Tutor'
    
    // Associated services
    keyVault: keyVaultId
    storageAccount: storageAccountId
    applicationInsights: applicationInsightsId
    
    // No container registry needed for local dev
    containerRegistry: null
    
    // Network settings
    publicNetworkAccess: 'Enabled'
    
    // Hub configuration
    managedNetwork: {
      isolationMode: 'Disabled'
    }
  }
}

output id string = aiHub.id
output name string = aiHub.name
output principalId string = aiHub.identity.principalId
