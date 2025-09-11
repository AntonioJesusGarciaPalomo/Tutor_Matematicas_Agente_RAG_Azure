param location string
param appServicePlanName string = 'plan-tutor-frontend-${uniqueString(resourceGroup().id)}'
param webAppName string = 'app-tutor-frontend-${uniqueString(resourceGroup().id)}'

// App Service Plan (la infraestructura subyacente de la Web App)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1' // Plan Básico, bueno para desarrollo/pruebas
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true // Requerido para Linux
  }
}

// La Web App donde se ejecutará Gradio
resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: { 'azd-service-name': 'frontend' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12' // Especifica la versión de Python
      ftpsState: 'FtpsOnly'
    }
  }
}

// Salida con la URL del frontend
output frontendUri string = 'https://${webApp.properties.defaultHostName}'
