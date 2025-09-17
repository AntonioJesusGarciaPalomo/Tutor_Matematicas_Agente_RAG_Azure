# Guarda esto como deploy-local-dev-fixed.ps1
# ================================================
# AUTOMATED LOCAL DEVELOPMENT SETUP FOR WINDOWS
# ================================================

$ErrorActionPreference = "Stop"

# Configuration
$DEFAULT_LOCATION = "westeurope"
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
        $allOk = $false
    }
    
    # Check Azure Developer CLI
    if (Get-Command azd -ErrorAction SilentlyContinue) {
        Write-Host "OK: Azure Developer CLI installed" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Azure Developer CLI not installed" -ForegroundColor Red
        Write-Host "Install from: https://aka.ms/azd-install" -ForegroundColor Gray
        $allOk = $false
    }
    
    # Check Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "OK: Python installed" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Python not installed" -ForegroundColor Red
        $allOk = $false
    }
    
    if (-not $allOk) {
        Write-Host "Please install missing prerequisites and try again" -ForegroundColor Red
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
    Write-Host "Available regions: eastus, westus2, westeurope, northeurope, uksouth" -ForegroundColor Blue
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
    Write-Host "Creating resource group..." -ForegroundColor Yellow
    az group create --name $Config.ResourceGroup --location $Config.Location
    
    # Deploy using Bicep
    Write-Host "Deploying resources..." -ForegroundColor Yellow
    
    $deploymentName = "local-dev-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    $result = az deployment group create `
        --name $deploymentName `
        --resource-group $Config.ResourceGroup `
        --template-file "infra/main-local.bicep" `
        --parameters location=$($Config.Location) `
                     environmentName=$($Config.EnvName) `
        --output json | ConvertFrom-Json
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Azure resources provisioned successfully!" -ForegroundColor Green
        
        # Extract outputs and create .env file
        $outputs = $result.properties.outputs
        
        $envContent = @"
# Auto-generated configuration for local development
PROJECT_ENDPOINT=$($outputs.PROJECT_ENDPOINT.value)
MODEL_DEPLOYMENT_NAME=gpt-4o
AGENT_NAME=math-tutor-agent
STORAGE_ACCOUNT_NAME=$($outputs.STORAGE_ACCOUNT_NAME.value)
STORAGE_ACCOUNT_KEY=$($outputs.STORAGE_ACCOUNT_KEY.value)
IMAGES_CONTAINER_NAME=images
ENVIRONMENT=local
DEBUG=false
BACKEND_URI=http://localhost:8000
FRONTEND_URI=http://localhost:7860
PORT=8000
FRONTEND_PORT=7860
RESOURCE_GROUP=$($Config.ResourceGroup)
"@
        
        $envContent | Out-File -FilePath ".env" -Encoding UTF8
        Copy-Item ".env" "backend\.env" -Force
        Copy-Item ".env" "frontend\.env" -Force
        
        Write-Host ".env files created successfully!" -ForegroundColor Green
        
    } else {
        Write-Host "Provisioning failed. Check the error messages above." -ForegroundColor Red
        exit 1
    }
}

# Display next steps
function Show-NextSteps {
    param($Config)
    
    Write-Host ""
    Write-Host "LOCAL DEVELOPMENT ENVIRONMENT READY!" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Start the services:"
    Write-Host "   run-local.bat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Or run services separately:"
    Write-Host "   Terminal 1: cd backend; .venv\Scripts\activate; python main.py" -ForegroundColor Cyan
    Write-Host "   Terminal 2: cd frontend; .venv\Scripts\activate; python app.py" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Access the application:"
    Write-Host "   Frontend: http://localhost:7860" -ForegroundColor Cyan
    Write-Host "   Backend API: http://localhost:8000/docs" -ForegroundColor Cyan
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
    Show-NextSteps -Config $config
}

# Run main function
Main
