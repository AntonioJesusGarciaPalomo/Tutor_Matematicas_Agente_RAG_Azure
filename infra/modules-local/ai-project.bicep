param name string
param location string
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
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: 'Math Tutor Local Dev Project'
    description: 'AI Project for local development of Math Tutor agent'
    hubResourceId: hubId
    publicNetworkAccess: 'Enabled'
  }
}

// Compute endpoint for the project
var projectEndpoint = 'https://${aiProject.name}.api.azureml.ms'

output id string = aiProject.id
output name string = aiProject.name
output principalId string = aiProject.identity.principalId
output endpoint string = projectEndpoint
