param name string
param location string = resourceGroup().location
param tags object = {}

param keyVaultId string
param storageAccountId string
param applicationInsightsId string
param containerRegistryId string

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'Hub' // <-- Esto lo define como un AI Hub
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic' // Nivel Básico para empezar
    tier: 'Basic'
  }
  properties: {
    // Asocia los servicios dependientes clave al Hub
    keyVault: keyVaultId
    storageAccount: storageAccountId
    applicationInsights: applicationInsightsId
    containerRegistry: containerRegistryId
    publicNetworkAccess: 'Enabled'
  }
}

output id string = aiHub.id
output name string = aiHub.name
