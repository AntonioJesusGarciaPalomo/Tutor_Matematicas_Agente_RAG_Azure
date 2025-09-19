# ================================================
# AUTOMATED LOCAL DEVELOPMENT SETUP FOR WINDOWS - FIXED VERSION
# ================================================
# This script provisions minimal Azure resources for local development
# and sets up the complete local environment automatically

$ErrorActionPreference = "Stop"

# Configuration
$DEFAULT_LOCATION = "swedencentral"
$DEFAULT_ENV_NAME = "dev"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "MATH TUTOR - LOCAL DEVELOPMENT SETUP" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Function to check prerequisites
function Test-Prerequisites {
    Write-Host "`nChecking Prerequisites" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    $allOk = $true
    
    # Check Azure CLI
    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Host "OK: Azure CLI installed" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Azure CLI not installed" -ForegroundColor Red
        Write-Host "Install from: https://docs.microsoft.com/cli/azure/install" -ForegroundColor Yellow
        $allOk = $false
    }
    
    # Check Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "OK: Python installed" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Python not installed" -ForegroundColor Red
        Write-Host "Install from: https://www.python.org/downloads/" -ForegroundColor Yellow
        $allOk = $false
    }
    
    # Check if bicep is installed (part of Azure CLI)
    try {
        az bicep version | Out-Null
        Write-Host "OK: Bicep installed" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Installing Bicep..." -ForegroundColor Yellow
        az bicep install
    }
    
    if (-not $allOk) {
        Write-Host "`nPlease install missing prerequisites and try again" -ForegroundColor Red
        exit 1
    }
}

# Azure authentication
function Connect-AzureAccount {
    Write-Host "`nAzure Authentication" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Check if already logged in
    $account = az account show 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Host "Already logged in as: $($account.user.name)" -ForegroundColor Green
        Write-Host "Subscription: $($account.name)" -ForegroundColor Blue
        
        $continue = Read-Host "Do you want to continue with this account? (y/n)"
        if ($continue -ne 'y') {
            az logout
            az login
        }
    } else {
        Write-Host "Not logged in to Azure" -ForegroundColor Yellow
        az login
    }
}

# Get deployment parameters
function Get-DeploymentParameters {
    Write-Host "`nConfiguration Parameters" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Environment name
    $envName = Read-Host "Environment name (default: $DEFAULT_ENV_NAME)"
    if (-not $envName) { $envName = $DEFAULT_ENV_NAME }
    
    # Azure location
    Write-Host "Available regions: eastus, westus2, westeurope, swedencentral, northeurope, uksouth" -ForegroundColor Blue
    $location = Read-Host "Azure location (default: $DEFAULT_LOCATION)"
    if (-not $location) { $location = $DEFAULT_LOCATION }
    
    # Resource group name
    $rgName = "rg-aifoundry-local-$envName"
    $customRg = Read-Host "Resource group name (default: $rgName)"
    if ($customRg) { $rgName = $customRg }
    
    Write-Host "`nConfiguration summary:" -ForegroundColor Blue
    Write-Host "   Environment: $envName"
    Write-Host "   Location: $location"
    Write-Host "   Resource Group: $rgName"
    
    $proceed = Read-Host "`nProceed with these settings? (y/n)"
    if ($proceed -ne 'y') {
        Write-Host "Setup cancelled" -ForegroundColor Yellow
        exit 1
    }
    
    return @{
        EnvName = $envName
        Location = $location
        ResourceGroup = $rgName
    }
}

# Create resources using Bicep directly
function Deploy-AzureResources {
    param($Config)
    
    Write-Host "`nProvisioning Azure Resources" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    Write-Host "This will create:" -ForegroundColor Blue
    Write-Host "   - AI Hub and Project"
    Write-Host "   - Storage Account"
    Write-Host "   - Key Vault"
    Write-Host "   - Application Insights"
    Write-Host ""
    Write-Host "This may take 5-10 minutes..." -ForegroundColor Yellow
    
    # Create resource group
    Write-Host "`nCreating resource group..." -ForegroundColor Yellow
    
    # Check if resource group exists
    $rgExists = az group exists --name $Config.ResourceGroup 2>$null
    
    if ($rgExists -eq "false") {
        az group create --name $Config.ResourceGroup --location $Config.Location --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Resource group created: $($Config.ResourceGroup)" -ForegroundColor Green
        } else {
            Write-Host "Failed to create resource group" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Resource group already exists: $($Config.ResourceGroup)" -ForegroundColor Green
    }
    
    # Deploy using Bicep
    Write-Host "`nDeploying resources with Bicep..." -ForegroundColor Yellow
    Write-Host "This will take several minutes, please be patient..." -ForegroundColor Gray
    
    $deploymentName = "local-dev-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Crear archivo temporal de parametros
    $parametersContent = @{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
        "contentVersion" = "1.0.0.0"
        "parameters" = @{
            "location" = @{ "value" = $Config.Location }
            "environmentName" = @{ "value" = $Config.EnvName }
        }
    } | ConvertTo-Json -Depth 10
    
    $parametersFile = "$env:TEMP\deployment-params.json"
    $parametersContent | Out-File -FilePath $parametersFile -Encoding UTF8
    
    Write-Host "Deployment name: $deploymentName" -ForegroundColor Gray
    
    # Ejecutar el despliegue con manejo especial de warnings
    $originalErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    # Ejecutar despliegue y capturar toda la salida
    $deploymentOutput = & az deployment group create `
        --name $deploymentName `
        --resource-group $Config.ResourceGroup `
        --template-file "infra/main-local.bicep" `
        --parameters "@$parametersFile" `
        --output json 2>&1
    
    # Restaurar configuración original
    $ErrorActionPreference = $originalErrorActionPreference
    
    # Limpiar archivo temporal
    Remove-Item $parametersFile -Force -ErrorAction SilentlyContinue
    
    # Filtrar la salida para obtener solo el JSON
    $jsonLines = @()
    $inJson = $false
    
    foreach ($line in $deploymentOutput) {
        $lineStr = $line.ToString()
        
        # Ignorar warnings
        if ($lineStr -like "*WARNING*" -or $lineStr -like "*Warning*") {
            continue
        }
        
        # Detectar inicio del JSON
        if ($lineStr.StartsWith("{")) {
            $inJson = $true
        }
        
        if ($inJson) {
            $jsonLines += $lineStr
        }
        
        # Detectar fin del JSON
        if ($lineStr.EndsWith("}") -and $inJson) {
            break
        }
    }
    
    $jsonResult = $jsonLines -join "`n"
    
    # Intentar parsear el resultado
    $deploymentSuccess = $false
    $deployment = $null
    
    try {
        if ($jsonResult -and $jsonResult.Trim() -ne "") {
            $deployment = $jsonResult | ConvertFrom-Json
            if ($deployment -and $deployment.properties -and $deployment.properties.provisioningState -eq "Succeeded") {
                $deploymentSuccess = $true
            }
        }
    } catch {
        Write-Host "Could not parse deployment output directly, checking status..." -ForegroundColor Yellow
    }
    
    # Si no pudimos obtener el resultado directamente, verificar el estado
    if (-not $deploymentSuccess) {
        Write-Host "Verifying deployment status..." -ForegroundColor Yellow
        
        # Esperar un momento para que Azure registre el despliegue
        Start-Sleep -Seconds 5
        
        $checkResult = az deployment group show `
            --name $deploymentName `
            --resource-group $Config.ResourceGroup `
            --output json 2>$null
        
        if ($checkResult) {
            try {
                $deployment = $checkResult | ConvertFrom-Json
                if ($deployment.properties.provisioningState -eq "Succeeded") {
                    $deploymentSuccess = $true
                }
            } catch {
                Write-Host "Error parsing deployment status" -ForegroundColor Red
            }
        }
    }
    
    if ($deploymentSuccess) {
        Write-Host "Azure resources provisioned successfully!" -ForegroundColor Green
        
        # Obtener outputs si no los tenemos
        if (-not $deployment.properties.outputs) {
            Write-Host "Retrieving deployment outputs..." -ForegroundColor Yellow
            $deployment = az deployment group show `
                --name $deploymentName `
                --resource-group $Config.ResourceGroup `
                --output json | ConvertFrom-Json
        }
        
        $outputs = $deployment.properties.outputs
        
        # Create .env file with proper formatting
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
AZURE_LOCATION=$($Config.Location)
RESOURCE_GROUP=$($Config.ResourceGroup)
KEY_VAULT_NAME=$($outputs.KEY_VAULT_NAME.value)
AI_HUB_NAME=$($outputs.AI_HUB_NAME.value)
AI_PROJECT_NAME=$($outputs.AI_PROJECT_NAME.value)
"@
        
        # Save .env files
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
        
        Write-Host ".env files created successfully!" -ForegroundColor Green
        
    } else {
        Write-Host "Deployment appears to have failed or is still in progress." -ForegroundColor Yellow
        Write-Host "Please check the Azure portal for details:" -ForegroundColor Yellow
        Write-Host "  Resource Group: $($Config.ResourceGroup)" -ForegroundColor White
        Write-Host ""
        Write-Host "You can also run check-deployment.ps1 to verify the status later." -ForegroundColor Cyan
        
        if ($deployment -and $deployment.properties) {
            Write-Host "Current status: $($deployment.properties.provisioningState)" -ForegroundColor Yellow
            
            if ($deployment.properties.error) {
                Write-Host "Error: $($deployment.properties.error.message)" -ForegroundColor Red
            }
        }
    }
}

# Setup Python environment
function Setup-PythonEnvironment {
    param($Config)
    
    Write-Host "`nSetting up Python environment..." -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Check if setup-and-verify.py exists
    if (Test-Path "setup-and-verify.py") {
        Write-Host "Running Python setup script..." -ForegroundColor Yellow
        python setup-and-verify.py
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Python environment configured!" -ForegroundColor Green
        } else {
            Write-Host "Python setup had some issues. Check the output above." -ForegroundColor Yellow
        }
    } else {
        Write-Host "setup-and-verify.py not found. Manual setup may be required." -ForegroundColor Yellow
    }
}

# Display next steps
function Show-NextSteps {
    param($Config)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   LOCAL DEVELOPMENT SETUP COMPLETE!    " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "RESOURCES CREATED IN AZURE:" -ForegroundColor Cyan
    Write-Host "  Resource Group: $($Config.ResourceGroup)" -ForegroundColor White
    Write-Host "  Location: $($Config.Location)" -ForegroundColor White
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Start the services:" -ForegroundColor Yellow
    Write-Host "   run-local.bat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Or run services separately:" -ForegroundColor Yellow
    Write-Host "   Terminal 1: cd backend; .venv\Scripts\activate; python main.py" -ForegroundColor Cyan
    Write-Host "   Terminal 2: cd frontend; .venv\Scripts\activate; python app.py" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Access the application:" -ForegroundColor Yellow
    Write-Host "   Frontend: http://localhost:7860" -ForegroundColor Cyan
    Write-Host "   Backend API: http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USEFUL COMMANDS:" -ForegroundColor Cyan
    Write-Host "  Check resources: az resource list --resource-group $($Config.ResourceGroup) --output table" -ForegroundColor Gray
    Write-Host "  Check deployment: .\check-deployment.ps1" -ForegroundColor Gray
    Write-Host "  Delete resources: az group delete --name $($Config.ResourceGroup) --yes" -ForegroundColor Gray
    Write-Host ""
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "This script will:" -ForegroundColor Blue
    Write-Host "   1. Check prerequisites"
    Write-Host "   2. Authenticate with Azure"
    Write-Host "   3. Provision minimal Azure resources for local dev"
    Write-Host "   4. Create all necessary .env files"
    Write-Host "   5. Setup Python environment"
    Write-Host ""
    
    $ready = Read-Host "Ready to start? (y/n)"
    if ($ready -ne 'y') {
        Write-Host "Setup cancelled" -ForegroundColor Yellow
        exit 1
    }
    
    # Execute setup steps
    Test-Prerequisites
    Connect-AzureAccount
    $config = Get-DeploymentParameters
    Deploy-AzureResources -Config $config
    Setup-PythonEnvironment -Config $config
    Show-NextSteps -Config $config
}

# Run main function
Main