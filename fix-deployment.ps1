#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Script para corregir el despliegue del AI Foundry Agent Tutor
.DESCRIPTION
    Este script configura las variables de entorno necesarias y redespliega
    tanto el backend como el frontend con la configuración correcta.
.PARAMETER ResourceGroup
    Nombre del grupo de recursos (default: rg-aifoundry-tutor)
.PARAMETER ModelDeployment
    Nombre del modelo a usar (default: gpt-4o)
.PARAMETER SkipDeploy
    Si se especifica, no ejecuta el redespliegue
.EXAMPLE
    .\fix-deployment.ps1
    .\fix-deployment.ps1 -ResourceGroup "mi-rg" -ModelDeployment "gpt-4o"
    .\fix-deployment.ps1 -SkipDeploy
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-aifoundry-tutor",
    
    [Parameter(Mandatory=$false)]
    [string]$ModelDeployment = "gpt-4o",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDeploy
)

# Configuración de colores y símbolos
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "🔧 AI Foundry Agent Tutor - Deployment Fix" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Función mejorada para verificar comandos
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Función para manejar errores
function Handle-Error {
    param([string]$Message, [bool]$Exit = $true)
    Write-Host "❌ ERROR: $Message" -ForegroundColor Red
    if ($Exit) { exit 1 }
}

# Función para mostrar progreso
function Show-Progress {
    param([string]$Message, [string]$Status = "Working")
    Write-Host "⏳ $Message..." -ForegroundColor Yellow -NoNewline
    if ($Status -eq "Done") {
        Write-Host " ✅" -ForegroundColor Green
    }
}

# Verificar prerrequisitos
Write-Host "📋 Verificando prerrequisitos..." -ForegroundColor Yellow
Write-Host ""

$prerequisites = @(
    @{Name="az"; DisplayName="Azure CLI"},
    @{Name="azd"; DisplayName="Azure Developer CLI"}
)

$allPrerequisitesMet = $true
foreach ($prereq in $prerequisites) {
    if (Test-Command $prereq.Name) {
        Write-Host "  ✅ $($prereq.DisplayName) instalado" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $($prereq.DisplayName) NO instalado" -ForegroundColor Red
        $allPrerequisitesMet = $false
    }
}

if (-not $allPrerequisitesMet) {
    Handle-Error "Faltan prerrequisitos. Por favor, instala las herramientas faltantes."
}

# Verificar login de Azure
Write-Host "`n🔐 Verificando autenticación de Azure..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  ⚠️ No autenticado. Iniciando login..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Error al autenticarse en Azure"
    }
    $account = az account show 2>$null | ConvertFrom-Json
}
Write-Host "  ✅ Autenticado como: $($account.user.name)" -ForegroundColor Green
Write-Host "  📍 Suscripción: $($account.name)" -ForegroundColor Cyan

# Configurar Azure Location desde .env si existe
Write-Host "`n📍 Configurando región de Azure..." -ForegroundColor Yellow
if (Test-Path ".env") {
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match "AZURE_LOCATION=(.+)") {
        $location = $matches[1].Trim()
        if (Get-Command azd -ErrorAction SilentlyContinue) {
            azd env set AZURE_LOCATION $location 2>$null
            Write-Host "  ✅ Región configurada: $location" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠️ AZURE_LOCATION no encontrada en .env, usando default" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ℹ️ Archivo .env no encontrado aún" -ForegroundColor Gray
}

# Verificar que el resource group existe
Write-Host "`n🔍 Verificando Resource Group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroup 2>$null
if ($rgExists -eq "false") {
    Handle-Error "El Resource Group '$ResourceGroup' no existe. ¿Has ejecutado 'azd provision' primero?"
}
Write-Host "  ✅ Resource Group '$ResourceGroup' encontrado" -ForegroundColor Green

# Obtener información de los recursos desplegados
Write-Host "`n🔍 Obteniendo información de recursos desplegados..." -ForegroundColor Yellow
Write-Host ""

try {
    # Backend (Container App)
    Show-Progress "Buscando Container App del backend"
    $containerApps = az containerapp list --resource-group $ResourceGroup --query "[?contains(name, 'ca-backend')]" -o json | ConvertFrom-Json
    
    if ($containerApps.Count -eq 0) {
        Handle-Error "No se encontró la Container App del backend"
    }
    
    $containerApp = $containerApps[0]
    $BACKEND_URI = "https://$($containerApp.properties.configuration.ingress.fqdn)"
    $CONTAINER_APP_NAME = $containerApp.name
    Show-Progress "Container App encontrada" "Done"
    Write-Host "     • Nombre: $CONTAINER_APP_NAME" -ForegroundColor Gray
    Write-Host "     • URL: $BACKEND_URI" -ForegroundColor Gray
    
    # Frontend (App Service)
    Show-Progress "Buscando App Service del frontend"
    $webApps = az webapp list --resource-group $ResourceGroup --query "[?contains(name, 'app-tutor-frontend')]" -o json | ConvertFrom-Json
    
    if ($webApps.Count -eq 0) {
        Handle-Error "No se encontró el App Service del frontend"
    }
    
    $webApp = $webApps[0]
    $FRONTEND_URI = "https://$($webApp.defaultHostName)"
    $FRONTEND_NAME = $webApp.name
    Show-Progress "App Service encontrado" "Done"
    Write-Host "     • Nombre: $FRONTEND_NAME" -ForegroundColor Gray
    Write-Host "     • URL: $FRONTEND_URI" -ForegroundColor Gray
    
    # AI Project
    Show-Progress "Buscando AI Project"
    $aiProjects = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.MachineLearningServices/workspaces" --query "[?kind=='Project']" -o json | ConvertFrom-Json
    
    if ($aiProjects.Count -eq 0) {
        Handle-Error "No se encontró el AI Project"
    }
    
    $aiProject = $aiProjects[0]
    $PROJECT_NAME = $aiProject.name
    
    # Obtener el endpoint completo del proyecto
    $projectDetails = az ml workspace show --name $PROJECT_NAME --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
    if ($projectDetails) {
        $PROJECT_ENDPOINT = $projectDetails.properties.discoveryUrl
    } else {
        # Fallback al formato estándar
        $PROJECT_ENDPOINT = "https://$PROJECT_NAME.api.azureml.ms"
    }
    
    Show-Progress "AI Project encontrado" "Done"
    Write-Host "     • Nombre: $PROJECT_NAME" -ForegroundColor Gray
    Write-Host "     • Endpoint: $PROJECT_ENDPOINT" -ForegroundColor Gray
    
    # Storage Account
    Show-Progress "Buscando Storage Account"
    $storageAccounts = az storage account list --resource-group $ResourceGroup -o json | ConvertFrom-Json
    
    if ($storageAccounts.Count -eq 0) {
        Handle-Error "No se encontró el Storage Account"
    }
    
    $storageAccount = $storageAccounts[0]
    $STORAGE_ACCOUNT_NAME = $storageAccount.name
    Show-Progress "Storage Account encontrado" "Done"
    Write-Host "     • Nombre: $STORAGE_ACCOUNT_NAME" -ForegroundColor Gray
    
    # Container Registry
    Show-Progress "Buscando Container Registry"
    $acrs = az acr list --resource-group $ResourceGroup -o json | ConvertFrom-Json
    
    if ($acrs.Count -eq 0) {
        Handle-Error "No se encontró el Container Registry"
    }
    
    $acr = $acrs[0]
    $ACR_NAME = $acr.name
    $ACR_LOGIN_SERVER = $acr.loginServer
    Show-Progress "Container Registry encontrado" "Done"
    Write-Host "     • Nombre: $ACR_NAME" -ForegroundColor Gray
    Write-Host "     • Server: $ACR_LOGIN_SERVER" -ForegroundColor Gray
    
} catch {
    Handle-Error "Error obteniendo información de recursos: $_"
}

# Configurar Managed Identity para Container App
Write-Host "`n🔑 Configurando Managed Identity para Container App..." -ForegroundColor Yellow

# Asegurar que la Container App tiene una identidad administrada
Show-Progress "Asignando System Assigned Identity"
$identity = az containerapp identity assign `
    --name $CONTAINER_APP_NAME `
    --resource-group $ResourceGroup `
    --system-assigned `
    -o json | ConvertFrom-Json

$PRINCIPAL_ID = $identity.principalId
Show-Progress "Identity asignada" "Done"
Write-Host "     • Principal ID: $PRINCIPAL_ID" -ForegroundColor Gray

# Asignar permisos necesarios
Write-Host "`n🔐 Configurando permisos..." -ForegroundColor Yellow

# Permiso para Storage Account
Show-Progress "Configurando permisos en Storage Account"
az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/$($account.id)/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" `
    --output none 2>$null
Show-Progress "Permisos de Storage configurados" "Done"

# Permiso para AI Project
Show-Progress "Configurando permisos en AI Project"
az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Contributor" `
    --scope "/subscriptions/$($account.id)/resourceGroups/$ResourceGroup/providers/Microsoft.MachineLearningServices/workspaces/$PROJECT_NAME" `
    --output none 2>$null
Show-Progress "Permisos de AI Project configurados" "Done"

# Configurar variables de entorno
Write-Host "`n⚙️ Configurando variables de entorno..." -ForegroundColor Yellow

# Variables para AZD
if (Get-Command azd -ErrorAction SilentlyContinue) {
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
        azd env set $key $envVars[$key] 2>$null
    }
    Write-Host "  ✅ Variables de AZD configuradas" -ForegroundColor Green
}

# Actualizar App Service
Show-Progress "Actualizando configuración del Frontend"
$appSettings = @(
    "BACKEND_URI=$BACKEND_URI",
    "WEBSITES_PORT=7860",
    "PORT=7860",
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "WEBSITE_RUN_FROM_PACKAGE=0"
)

az webapp config appsettings set `
    --name $FRONTEND_NAME `
    --resource-group $ResourceGroup `
    --settings $appSettings `
    --output none

Show-Progress "Frontend configurado" "Done"

# Actualizar Container App
Show-Progress "Actualizando configuración del Backend"

# Preparar variables de entorno para Container App
$envVarsString = @(
    "PROJECT_ENDPOINT=$PROJECT_ENDPOINT",
    "MODEL_DEPLOYMENT_NAME=$ModelDeployment",
    "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME",
    "IMAGES_CONTAINER_NAME=images",
    "AZURE_CLIENT_ID=$PRINCIPAL_ID"
) -join " "

az containerapp update `
    --name $CONTAINER_APP_NAME `
    --resource-group $ResourceGroup `
    --set-env-vars $envVarsString `
    --output none

Show-Progress "Backend configurado" "Done"

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

# Resource Group
RESOURCE_GROUP=$ResourceGroup
"@

$envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
Write-Host "  ✅ Archivo .env creado" -ForegroundColor Green

# Copiar .env a subdirectorios si existen
if (Test-Path "backend") {
    Copy-Item ".env" "backend/.env" -Force
    Write-Host "  ✅ .env copiado a backend/" -ForegroundColor Green
}
if (Test-Path "frontend") {
    Copy-Item ".env" "frontend/.env" -Force
    Write-Host "  ✅ .env copiado a frontend/" -ForegroundColor Green
}

# Redesplegar si no se especificó -SkipDeploy
if (-not $SkipDeploy) {
    Write-Host "`n❓ ¿Deseas redesplegar las aplicaciones ahora?" -ForegroundColor Yellow
    Write-Host "   (Esto tomará ~15-20 minutos)" -ForegroundColor Gray
    $redeploy = Read-Host "Escribe 'si' para redesplegar o Enter para omitir"
    
    if ($redeploy -eq "si") {
        Write-Host "`n🚀 Iniciando redespliegue..." -ForegroundColor Cyan
        
        # Verificar si existe azd.yaml o azure.yaml
        if (Test-Path "azure.yaml" -or Test-Path "azd.yaml") {
            azd deploy
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n✅ ¡Redespliegue completado exitosamente!" -ForegroundColor Green
            } else {
                Write-Host "`n⚠️ Hubo un problema con el redespliegue." -ForegroundColor Yellow
                Write-Host "   Revisa los logs para más detalles." -ForegroundColor Gray
            }
        } else {
            Write-Host "⚠️ No se encontró azure.yaml. Desplegando manualmente..." -ForegroundColor Yellow
            
            # Desplegar backend si hay cambios
            if (Test-Path "backend/Dockerfile") {
                Write-Host "  📦 Construyendo imagen del backend..." -ForegroundColor Gray
                docker build -t "$($ACR_LOGIN_SERVER)/backend:latest" ./backend
                
                Write-Host "  📤 Subiendo imagen al ACR..." -ForegroundColor Gray
                az acr login --name $ACR_NAME
                docker push "$($ACR_LOGIN_SERVER)/backend:latest"
                
                Write-Host "  🔄 Actualizando Container App..." -ForegroundColor Gray
                az containerapp update `
                    --name $CONTAINER_APP_NAME `
                    --resource-group $ResourceGroup `
                    --image "$($ACR_LOGIN_SERVER)/backend:latest" `
                    --output none
            }
        }
    }
} else {
    Write-Host "`n📌 Redespliegue omitido (flag -SkipDeploy)" -ForegroundColor Yellow
}

# Reiniciar servicios
Write-Host "`n🔄 Reiniciando servicios..." -ForegroundColor Yellow

Show-Progress "Reiniciando Frontend"
az webapp restart --name $FRONTEND_NAME --resource-group $ResourceGroup --output none
Show-Progress "Frontend reiniciado" "Done"

Show-Progress "Reiniciando Backend"
az containerapp revision restart `
    --name $CONTAINER_APP_NAME `
    --resource-group $ResourceGroup `
    --revision latest `
    --output none 2>$null
Show-Progress "Backend reiniciado" "Done"

# Verificar el estado
Write-Host "`n🔍 Verificando estado de los servicios..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Verificar Frontend
try {
    $response = Invoke-WebRequest -Uri $FRONTEND_URI -Method Head -TimeoutSec 10 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Host "  ✅ Frontend respondiendo correctamente" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠️ Frontend aún iniciándose (esto es normal)" -ForegroundColor Yellow
}

# Verificar Backend
try {
    $healthUrl = "$BACKEND_URI/health"
    $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Host "  ✅ Backend respondiendo correctamente" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠️ Backend aún iniciándose (esto es normal)" -ForegroundColor Yellow
}

# Mostrar resumen final
Write-Host "`n" -NoNewline
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         🎉 CONFIGURACIÓN COMPLETADA 🎉         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n📊 RESUMEN DE CONFIGURACIÓN:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

Write-Host "`n🔗 URLs de Acceso:" -ForegroundColor Cyan
Write-Host "  • Frontend:  $FRONTEND_URI" -ForegroundColor White
Write-Host "  • Backend:   $BACKEND_URI" -ForegroundColor White
Write-Host "  • Health:    $BACKEND_URI/health" -ForegroundColor Gray

Write-Host "`n⚙️ Configuración:" -ForegroundColor Cyan
Write-Host "  • Modelo IA:      $ModelDeployment" -ForegroundColor White
Write-Host "  • Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  • Storage:        $STORAGE_ACCOUNT_NAME" -ForegroundColor White

Write-Host "`n📝 Archivos Creados:" -ForegroundColor Cyan
Write-Host "  • .env (configuración local)" -ForegroundColor White
if (Test-Path "backend/.env") {
    Write-Host "  • backend/.env" -ForegroundColor Gray
}
if (Test-Path "frontend/.env") {
    Write-Host "  • frontend/.env" -ForegroundColor Gray
}

Write-Host "`n💡 PRÓXIMOS PASOS:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  1. Espera 2-3 minutos para que los servicios inicien" -ForegroundColor White
Write-Host "  2. Abre el frontend en: $FRONTEND_URI" -ForegroundColor White
Write-Host "  3. Para desarrollo local, ejecuta:" -ForegroundColor White
Write-Host "     • Windows: .\setup-local-dev.sh" -ForegroundColor Gray
Write-Host "     • Linux/Mac: ./setup-local-dev.sh" -ForegroundColor Gray

Write-Host "`n✨ ¡Script completado exitosamente!" -ForegroundColor Green
Write-Host ""