# ================================================
# CHECK DEPLOYMENT STATUS
# ================================================
# Script para verificar el estado del despliegue y crear .env si es necesario

param(
    [string]$ResourceGroup = "rg-aifoundry-local-dev"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "VERIFICANDO ESTADO DEL DESPLIEGUE" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si el resource group existe
$rgExists = az group exists --name $ResourceGroup 2>$null

if ($rgExists -eq "true") {
    Write-Host "Resource Group encontrado: $ResourceGroup" -ForegroundColor Green
    
    # Obtener el último despliegue
    Write-Host "Buscando despliegues..." -ForegroundColor Yellow
    
    $deployments = az deployment group list `
        --resource-group $ResourceGroup `
        --output json | ConvertFrom-Json
    
    if ($deployments -and $deployments.Count -gt 0) {
        # Ordenar por fecha y tomar el más reciente
        $latestDeployment = $deployments | Sort-Object -Property @{Expression={[DateTime]$_.properties.timestamp}} -Descending | Select-Object -First 1
        
        Write-Host "Último despliegue: $($latestDeployment.name)" -ForegroundColor Cyan
        Write-Host "Estado: $($latestDeployment.properties.provisioningState)" -ForegroundColor Cyan
        Write-Host "Fecha: $($latestDeployment.properties.timestamp)" -ForegroundColor Cyan
        
        if ($latestDeployment.properties.provisioningState -eq "Succeeded") {
            Write-Host "`nDespliegue exitoso! Obteniendo outputs..." -ForegroundColor Green
            
            # Obtener los outputs
            $deployment = az deployment group show `
                --name $latestDeployment.name `
                --resource-group $ResourceGroup `
                --output json | ConvertFrom-Json
            
            $outputs = $deployment.properties.outputs
            
            # Verificar si .env existe
            if (-not (Test-Path ".env")) {
                Write-Host "Creando archivo .env..." -ForegroundColor Yellow
                
                # Crear .env file
                $envContent = @"
# ================================================
# AUTO-GENERATED CONFIGURATION FOR LOCAL DEVELOPMENT
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ================================================

# Azure AI Foundry
PROJECT_ENDPOINT=$($outputs.PROJECT_ENDPOINT.value)
MODEL_DEPLOYMENT_NAME=gpt-4o
AGENT_NAME=math-tutor-agent

# Azure Storage
STORAGE_ACCOUNT_NAME=$($outputs.STORAGE_ACCOUNT_NAME.value)
STORAGE_ACCOUNT_KEY=$($outputs.STORAGE_ACCOUNT_KEY.value)
IMAGES_CONTAINER_NAME=images

# Local Development Settings
ENVIRONMENT=local
DEBUG=false
LOG_LEVEL=INFO

# Local Service URLs
BACKEND_URI=http://localhost:8000
FRONTEND_URI=http://localhost:7860
PORT=8000
FRONTEND_PORT=7860

# Azure Settings
AZURE_LOCATION=swedencentral
RESOURCE_GROUP=$ResourceGroup
KEY_VAULT_NAME=$($outputs.KEY_VAULT_NAME.value)
AI_HUB_NAME=$($outputs.AI_HUB_NAME.value)
AI_PROJECT_NAME=$($outputs.AI_PROJECT_NAME.value)
"@
                
                $envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
                
                # Copy to subdirectories
                if (Test-Path "backend") {
                    Copy-Item ".env" "backend\.env" -Force
                    Write-Host ".env copied to backend\" -ForegroundColor Green
                }
                
                if (Test-Path "frontend") {
                    Copy-Item ".env" "frontend\.env" -Force
                    Write-Host ".env copied to frontend\" -ForegroundColor Green
                }
                
                Write-Host "`n.env files created successfully!" -ForegroundColor Green
            } else {
                Write-Host ".env ya existe" -ForegroundColor Green
            }
            
            Write-Host "`nRecursos desplegados:" -ForegroundColor Cyan
            Write-Host "  - AI Hub: $($outputs.AI_HUB_NAME.value)" -ForegroundColor White
            Write-Host "  - AI Project: $($outputs.AI_PROJECT_NAME.value)" -ForegroundColor White
            Write-Host "  - Storage: $($outputs.STORAGE_ACCOUNT_NAME.value)" -ForegroundColor White
            Write-Host "  - Key Vault: $($outputs.KEY_VAULT_NAME.value)" -ForegroundColor White
            
            Write-Host "`nPróximo paso:" -ForegroundColor Yellow
            Write-Host "  1. Ejecuta: python setup-and-verify.py" -ForegroundColor Cyan
            Write-Host "  2. Ejecuta: .\run-local.bat" -ForegroundColor Cyan
            
        } else {
            Write-Host "El despliegue no se completó exitosamente" -ForegroundColor Red
            Write-Host "Estado: $($latestDeployment.properties.provisioningState)" -ForegroundColor Red
            
            # Mostrar errores si existen
            if ($latestDeployment.properties.error) {
                Write-Host "`nError: $($latestDeployment.properties.error.message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No se encontraron despliegues en el resource group" -ForegroundColor Yellow
        Write-Host "Ejecuta: .\deploy-local-dev.ps1" -ForegroundColor Cyan
    }
} else {
    Write-Host "Resource Group NO existe: $ResourceGroup" -ForegroundColor Red
    Write-Host "Ejecuta primero: .\deploy-local-dev.ps1" -ForegroundColor Yellow
}