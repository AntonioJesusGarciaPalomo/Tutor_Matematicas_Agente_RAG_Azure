targetScope = 'subscription'

// Parameters
param backendImage string = 'python:3.12-slim'
param resourceGroupName string = 'rg-aifoundry-tutor'
param location string = 'swedencentral'

// Variables
var uniqueSuffix = uniqueString(deployment().name)
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
}

// --- MODULOS DE DEPENDENCIAS PARA EL HUB ---
module kv 'modules/key_vault.bicep' = {
  scope: rg
  name: 'keyVaultDeploy'
  params: {
    name: 'kv-${uniqueSuffix}'
    location: location
    tags: {}
  }
}

module acr 'modules/container_registry.bicep' = {
  scope: rg
  name: 'containerRegistryDeploy'
  params: {
    name: 'acr${replace(uniqueSuffix, '-', '')}' // ACR no admite guiones
    location: location
  }
}

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storageDeploy'
  params: {
    location: location
  }
}

// App Insights se crea dentro del módulo de containerApp
module containerApp 'modules/container_app.bicep' = {
  scope: rg
  name: 'containerAppDeploy'
  params: {
    location: location
    containerImage: backendImage
  }
}

// --- MÓDULO DEL AI HUB ---
// Se crea después de sus dependencias
module hub 'modules/ai_hub.bicep' = {
  scope: rg
  name: 'aiHubDeploy'
  params: {
    name: 'hub-${uniqueSuffix}'
    location: location
    storageAccountId: storage.outputs.storageAccountId // Salida del módulo storage
    applicationInsightsId: containerApp.outputs.applicationInsightsId // Salida de containerApp
    keyVaultId: kv.outputs.id // Salida de key_vault
    containerRegistryId: acr.outputs.id // Salida de container_registry
  }
}

// --- MÓDULO DEL AI PROJECT ---
// Se crea al final, usando el ID del Hub recién creado
module aiProject 'modules/ai_project.bicep' = {
  scope: rg
  name: 'aiProjectDeploy'
  params: {
    hubId: hub.outputs.id // <-- El ID ahora viene del módulo del Hub
    name: 'proj-tutor-${uniqueSuffix}'
    location: location
  }
}

// --- RESTO DE MÓDULOS DE LA APLICACIÓN ---
module webApp 'modules/web_app.bicep' = {
  scope: rg
  name: 'webAppDeploy'
  params: {
    location: location
    backendUri: containerApp.outputs.backendUri
  }
}

module roleAssignment 'modules/role_assignment.bicep' = {
  scope: rg
  name: 'roleAssignmentDeploy'
  params: {
    principalId: containerApp.outputs.principalId
    storageBlobDataContributorRoleId: storageBlobDataContributorRoleId
    storageAccountName: storage.outputs.storageAccountName
  }
}

module acrRoleAssignment 'modules/acr_role_assignment.bicep' = {
  scope: rg
  name: 'acrRoleAssignmentDeploy'
  params: {
    acrName: acr.outputs.name // Pasamos el nombre del ACR
    principalId: containerApp.outputs.principalId // Pasamos el Principal ID de la App
  }
}

// Outputs
output AI_PROJECT_ENDPOINT string = aiProject.outputs.projectEndpoint
output BACKEND_URI string = containerApp.outputs.backendUri
output FRONTEND_URI string = webApp.outputs.frontendUri
output STORAGE_ACCOUNT_NAME string = storage.outputs.storageAccountName
output IMAGES_CONTAINER_NAME string = storage.outputs.imageContainerName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
