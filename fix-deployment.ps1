#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Script para corregir el despliegue del AI Foundry Agent Tutor
.DESCRIPTION
    Este script configura las variables de entorno necesarias y redespliega
    tanto el backend como el frontend con la configuración correcta.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-aifoundry-tutor",
    
    [Parameter(Mandatory=$false)]
    [string]$ModelDeployment = "gpt-4o"
)

Write-Host "🔧 AI Foundry Agent Tutor - Deployment Fix" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Función para verificar comandos
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Verificar prerrequisitos
Write-Host "`n📋 Verificando prerrequisitos..." -ForegroundColor Yellow

if (-not (Test-Command "az")) {
    Write-Error "Azure CLI no está instalado. Por favor, instálalo primero."
    exit 1
}

if (-not (Test-Command "azd")) {
    Write-Error "Azure Developer CLI no está instalado. Por favor, instálalo primero."
    exit 1
}

# Verificar login de Azure
Write-Host "🔐 Verificando autenticación de Azure..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "No estás autenticado. Iniciando login..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error al autenticarse en Azure"
        exit 1
    }
}
Write-Host "✅ Autenticado como: $($account.user.name)" -ForegroundColor Green

# Obtener información de los recursos desplegados
Write-Host "`n🔍 Obteniendo información de recursos desplegados..." -ForegroundColor Yellow

try {
    # Obtener información del backend (Container App)
    $containerApp = az containerapp list --resource-group $ResourceGroup --query "[?contains(name, 'ca-backend')].{name:name, fqdn:properties.configuration.ingress.fqdn}" -o json | ConvertFrom-Json | Select-Object -First 1
    
    if (-not $containerApp) {
        Write-Error "No se encontró la Container App del backend"
        exit 1
    }
    
    $BACKEND_URI = "https://$($containerApp.fqdn)"
    Write-Host "✅ Backend URI: $BACKEND_URI" -ForegroundColor Green
    
    # Obtener información del frontend (App Service)
    $webApp = az webapp list --resource-group $ResourceGroup --query "[?contains(name, 'app-tutor-frontend')].{name:name, hostname:defaultHostName}" -o json | ConvertFrom-Json | Select-Object -First 1
    
    if (-not $webApp) {
        Write-Error "No se encontró el App Service del frontend"
        exit 1
    }
    
    $FRONTEND_URI = "https://$($webApp.hostname)"
    $FRONTEND_NAME = $webApp.name
    Write-Host "✅ Frontend URI: $FRONTEND_URI" -ForegroundColor Green
    Write-Host "✅ Frontend Name: $FRONTEND_NAME" -ForegroundColor Green
    
    # Obtener información del AI Project
    $aiProject = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.MachineLearningServices/workspaces" --query "[?kind=='Project'].{name:name}" -o json | ConvertFrom-Json | Select-Object -First 1
    
    if (-not $aiProject) {
        Write-Error "No se encontró el AI Project"
        exit 1
    }
    
    $PROJECT_ENDPOINT = "https://$($aiProject.name).services.ai.azure.com/api/projects/$($aiProject.name)"
    Write-Host "✅ Project Endpoint: $PROJECT_ENDPOINT" -ForegroundColor Green
    
    # Obtener información del Storage Account
    $storageAccount = az storage account list --resource-group $ResourceGroup --query "[0].{name:name}" -o json | ConvertFrom-Json
    
    if (-not $storageAccount) {
        Write-Error "No se encontró el Storage Account"
        exit 1
    }
    
    $STORAGE_ACCOUNT_NAME = $storageAccount.name
    Write-Host "✅ Storage Account: $STORAGE_ACCOUNT_NAME" -ForegroundColor Green
    
    # Obtener información del Container Registry
    $acr = az acr list --resource-group $ResourceGroup --query "[0].{name:name, loginServer:loginServer}" -o json | ConvertFrom-Json
    
    if (-not $acr) {
        Write-Error "No se encontró el Container Registry"
        exit 1
    }
    
    $ACR_NAME = $acr.name
    $ACR_LOGIN_SERVER = $acr.loginServer
    Write-Host "✅ Container Registry: $ACR_LOGIN_SERVER" -ForegroundColor Green
    
} catch {
    Write-Error "Error obteniendo información de recursos: $_"
    exit 1
}

# Configurar variables de entorno en AZD
Write-Host "`n⚙️ Configurando variables de entorno en AZD..." -ForegroundColor Yellow

$envVars = @{
    "PROJECT_ENDPOINT" = $PROJECT_ENDPOINT
    "MODEL_DEPLOYMENT_NAME" = $ModelDeployment
    "STORAGE_ACCOUNT_NAME" = $STORAGE_ACCOUNT_NAME
    "IMAGES_CONTAINER_NAME" = "images"
    "BACKEND_URI" = $BACKEND_URI
    "FRONTEND_URI" = $FRONTEND_URI
    "AZURE_CONTAINER_REGISTRY_ENDPOINT" = $ACR_LOGIN_SERVER
}

foreach ($key in $envVars.Keys) {
    Write-Host "  Setting $key = $($envVars[$key])" -ForegroundColor Gray
    azd env set $key $envVars[$key]
}

Write-Host "✅ Variables de entorno configuradas" -ForegroundColor Green

# Actualizar configuración de App Service
Write-Host "`n🔧 Actualizando configuración del Frontend (App Service)..." -ForegroundColor Yellow

# Configurar las variables de entorno en el App Service
$appSettings = @(
    "BACKEND_URI=$BACKEND_URI"
    "WEBSITES_PORT=7860"
    "PORT=7860"
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
)

Write-Host "  Aplicando configuración al App Service..." -ForegroundColor Gray
az webapp config appsettings set `
    --name $FRONTEND_NAME `
    --resource-group $ResourceGroup `
    --settings $appSettings `
    --output none

Write-Host "✅ Configuración del App Service actualizada" -ForegroundColor Green

# Actualizar configuración de Container App
Write-Host "`n🔧 Actualizando configuración del Backend (Container App)..." -ForegroundColor Yellow

$containerAppEnvVars = @(
    @{name="PROJECT_ENDPOINT"; value=$PROJECT_ENDPOINT},
    @{name="MODEL_DEPLOYMENT_NAME"; value=$ModelDeployment},
    @{name="STORAGE_ACCOUNT_NAME"; value=$STORAGE_ACCOUNT_NAME},
    @{name="IMAGES_CONTAINER_NAME"; value="images"}
)

# Convertir a JSON para el comando
$envVarsJson = $containerAppEnvVars | ConvertTo-Json -Compress

Write-Host "  Aplicando variables de entorno a Container App..." -ForegroundColor Gray
az containerapp update `
    --name $containerApp.name `
    --resource-group $ResourceGroup `
    --set-env-vars $envVarsJson.Replace('"', '\"') `
    --output none

Write-Host "✅ Configuración de Container App actualizada" -ForegroundColor Green

# Crear archivo .env local
Write-Host "`n📝 Creando archivo .env local..." -ForegroundColor Yellow

$envContent = @"
# Variables de Azure AI Foundry
PROJECT_ENDPOINT=$PROJECT_ENDPOINT
MODEL_DEPLOYMENT_NAME=$ModelDeployment

# Variables de Storage
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
IMAGES_CONTAINER_NAME=images

# URLs de los servicios
BACKEND_URI=$BACKEND_URI
FRONTEND_URI=$FRONTEND_URI

# Container Registry
AZURE_CONTAINER_REGISTRY_ENDPOINT=$ACR_LOGIN_SERVER
"@

$envContent | Out-File -FilePath ".env" -Encoding UTF8
Write-Host "✅ Archivo .env creado" -ForegroundColor Green

# Preguntar si desea redesplegar
Write-Host "`n❓ ¿Deseas redesplegar las aplicaciones ahora? (Esto tomará ~15-20 minutos)" -ForegroundColor Yellow
$redeploy = Read-Host "Escribe 'si' para redesplegar o cualquier otra cosa para saltar este paso"

if ($redeploy -eq "si") {
    Write-Host "`n🚀 Iniciando redespliegue..." -ForegroundColor Cyan
    
    # Redesplegar con AZD
    azd deploy
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ ¡Redespliegue completado exitosamente!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ Hubo un problema con el redespliegue. Revisa los logs para más detalles." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n📌 Puedes redesplegar manualmente más tarde ejecutando: azd deploy" -ForegroundColor Yellow
}

# Reiniciar el App Service para aplicar cambios
Write-Host "`n🔄 Reiniciando el Frontend para aplicar cambios..." -ForegroundColor Yellow
az webapp restart --name $FRONTEND_NAME --resource-group $ResourceGroup --output none
Write-Host "✅ Frontend reiniciado" -ForegroundColor Green

# Mostrar resumen final
Write-Host "`n" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       🎉 CORRECCIÓN COMPLETADA 🎉      " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`n📊 Resumen de la configuración:" -ForegroundColor Yellow
Write-Host "  • Backend URL: $BACKEND_URI" -ForegroundColor White
Write-Host "  • Frontend URL: $FRONTEND_URI" -ForegroundColor White
Write-Host "  • AI Model: $ModelDeployment" -ForegroundColor White
Write-Host "  • Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "`n🌐 Tu aplicación debería estar disponible en:" -ForegroundColor Yellow
Write-Host "  $FRONTEND_URI" -ForegroundColor Cyan
Write-Host "`n⏳ Nota: El frontend puede tardar 2-3 minutos en estar completamente disponible." -ForegroundColor Yellow
Write-Host "`n💡 Consejo: Si aún ves errores, espera unos minutos y recarga la página." -ForegroundColor Yellow

# Verificar el estado del frontend
Write-Host "`n🔍 Verificando el estado del frontend..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

try {
    $response = Invoke-WebRequest -Uri $FRONTEND_URI -Method Head -TimeoutSec 10 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ ¡El frontend está respondiendo correctamente!" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️ El frontend aún no responde. Esto es normal, espera unos minutos." -ForegroundColor Yellow
}

Write-Host "`n✨ ¡Script completado!" -ForegroundColor Green