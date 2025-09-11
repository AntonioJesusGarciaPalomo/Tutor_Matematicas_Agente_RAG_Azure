param name string
param location string = resourceGroup().location
param tags object = {}
param hubId string 

resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Default'
    tier: 'Basic'
  }
  properties: {
    // Vincula este proyecto al Hub principal
    hubResourceId: hubId
    publicNetworkAccess: 'Enabled'
  }
}

// Salida del endpoint del proyecto para usar en las variables de entorno
output projectEndpoint string = 'https://${aiProject.name}.services.ai.azure.com/api/projects/${aiProject.name}'
output projectId string = aiProject.id
output projectName string = aiProject.name
