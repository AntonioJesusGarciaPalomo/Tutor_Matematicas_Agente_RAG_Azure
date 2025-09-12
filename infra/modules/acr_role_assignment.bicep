param acrName string
param principalId string

// ID del rol 'AcrPull'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// Obtiene una referencia al ACR que ya existe en el grupo de recursos
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Asigna el rol 'AcrPull' a la identidad de la Container App en el ámbito del ACR
resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr // El ámbito es el propio Container Registry
  name: guid(acr.id, principalId, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
