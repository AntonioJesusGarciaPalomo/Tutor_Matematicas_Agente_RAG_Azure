# ================================================
# AUTOMATED LOCAL DEVELOPMENT SETUP FOR WINDOWS
# ================================================
# This script provisions minimal Azure resources for local development
# and sets up the complete local environment automatically

$ErrorActionPreference = "Stop"

# Configuration
$DEFAULT_LOCATION = "swedencentral"
$DEFAULT_ENV_NAME = "dev"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "🚀 MATH TUTOR - LOCAL DEVELOPMENT SETUP" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Function to check prerequisites
function Test-Prerequisites {
    Write-Host "`n▶ Checking Prerequisites" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    $allOk = $true
    
    # Check Azure CLI
    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Host "✅ Azure CLI installed" -ForegroundColor Green
    } else {
        Write-Host "❌ Azure CLI not installed" -ForegroundColor Red
        Write-Host "   Install from: https://docs.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Gray
        $allOk = $false
    }
    
    # Check Azure Developer CLI
    if (Get-Command azd -ErrorAction SilentlyContinue) {
        Write-Host "✅ Azure Developer CLI installed" -ForegroundColor Green
    } else {
        Write-Host "❌ Azure Developer CLI not installed" -ForegroundColor Red
        Write-Host "   Install from: https://aka.ms/azd-install" -ForegroundColor Gray
        $allOk = $false
    }
    
    # Check Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "✅ Python installed" -ForegroundColor Green
    } else {
        Write-Host "❌ Python not installed" -ForegroundColor Red
        $allOk = $false
    }
    
    if (-not $allOk) {
        Write-Host "❌ Please install missing prerequisites and try again" -ForegroundColor Red
        exit 1
    }
}

# Azure authentication
function Connect-AzureAccount {
    Write-Host "`n▶ Azure Authentication" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Check if already logged in
    $account = az account show 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Host "✅ Already logged in as: $($account.user.name)" -ForegroundColor Green
        Write-Host "ℹ️  Subscription: $($account.name)" -ForegroundColor Blue
        
        $continue = Read-Host "Do you want to continue with this account? (y/n)"
        if ($continue -ne 'y') {
            az logout
            az login
        }
    } else {
        Write-Host "⚠️  Not logged in to Azure" -ForegroundColor Yellow
        az login
    }
    
    # Let user select subscription
    Write-Host "`nℹ️  Available subscriptions:" -ForegroundColor Blue
    az account list --output table
    
    $subId = Read-Host "`nEnter subscription ID (or press Enter to use current)"
    if ($subId) {
        az account set --subscription $subId
        Write-Host "✅ Subscription set to: $subId" -ForegroundColor Green
    }
}

# Get deployment parameters
function Get-DeploymentParameters {
    Write-Host "`n▶ Configuration Parameters" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Environment name
    $envName = Read-Host "Environment name (default: $DEFAULT_ENV_NAME)"
    if (-not $envName) { $envName = $DEFAULT_ENV_NAME }
    
    # Azure location
    Write-Host "ℹ️  Available regions: eastus, westus2, westeurope, swedencentral, uksouth" -ForegroundColor Blue
    $location = Read-Host "Azure location (default: $DEFAULT_LOCATION)"
    if (-not $location) { $location = $DEFAULT_LOCATION }
    
    # Resource group name
    $rgName = "rg-aifoundry-local-$envName"
    $customRg = Read-Host "Resource group name (default: $rgName)"
    if ($customRg) { $rgName = $customRg }
    
    Write-Host "`nℹ️  Configuration summary:" -ForegroundColor Blue
    Write-Host "   Environment: $envName"
    Write-Host "   Location: $location"
    Write-Host "   Resource Group: $rgName"
    
    $proceed = Read-Host "`nProceed with these settings? (y/n)"
    if ($proceed -ne 'y') {
        Write-Host "⚠️  Setup cancelled" -ForegroundColor Yellow
        exit 1
    }
    
    return @{
        EnvName = $envName
        Location = $location
        ResourceGroup = $rgName
    }
}

# Initialize azd environment
function Initialize-Azd {
    param($Config)
    
    Write-Host "`n▶ Initializing Azure Developer CLI" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Check if azure-local.yaml exists
    if (-not (Test-Path "azure-local.yaml")) {
        Write-Host "❌ azure-local.yaml not found!" -ForegroundColor Red
        Write-Host "Please ensure azure-local.yaml exists in the project root" -ForegroundColor Red
        exit 1
    }
    
    # Initialize azd
    $subId = (az account show --query id -o tsv)
    azd init --environment $Config.EnvName --from-code --cwd . --subscription $subId
    
    # Set environment variables
    azd env set AZURE_LOCATION $Config.Location
    azd env set AZURE_ENV_NAME $Config.EnvName
    
    Write-Host "✅ Azure Developer CLI initialized" -ForegroundColor Green
}

# Provision Azure resources
function Deploy-AzureResources {
    param($Config)
    
    Write-Host "`n▶ Provisioning Azure Resources" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    Write-Host "ℹ️  This will create:" -ForegroundColor Blue
    Write-Host "   • AI Hub and Project"
    Write-Host "   • Storage Account"
    Write-Host "   • Key Vault"
    Write-Host "   • Application Insights"
    Write-Host ""
    Write-Host "⚠️  This may take 5-10 minutes..." -ForegroundColor Yellow
    
    $subId = (az account show --query id -o tsv)
    azd provision --environment $Config.EnvName --no-prompt `
        --subscription $subId
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Azure resources provisioned successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Provisioning failed. Check the error messages above." -ForegroundColor Red
        exit 1
    }
}

# Setup local environment
function Initialize-LocalEnvironment {
    Write-Host "`n▶ Setting Up Local Environment" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Check if .env was created
    if (-not (Test-Path ".env")) {
        Write-Host "❌ .env file not created. Check azd output." -ForegroundColor Red
        exit 1
    }
    
    # Run the Python setup script
    if (Test-Path "setup-and-verify.py") {
        Write-Host "ℹ️  Running local setup script..." -ForegroundColor Blue
        python setup-and-verify.py
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Local environment configured!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Setup script reported issues. Check the output above." -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  setup-and-verify.py not found. Manual setup required." -ForegroundColor Yellow
    }
}

# Display next steps
function Show-NextSteps {
    param($Config)
    
    Write-Host ""
    Write-Host "🎉 LOCAL DEVELOPMENT ENVIRONMENT READY!" -ForegroundColor Green
    Write-Host ""
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "📋 NEXT STEPS:" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Start the services:"
    Write-Host "   " -NoNewline
    Write-Host ".\run-local.bat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Or run services separately:"
    Write-Host "   Terminal 1: " -NoNewline
    Write-Host "cd backend && .venv\Scripts\activate && python main.py" -ForegroundColor Cyan
    Write-Host "   Terminal 2: " -NoNewline
    Write-Host "cd frontend && .venv\Scripts\activate && python app.py" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Access the application:"
    Write-Host "   Frontend: " -NoNewline
    Write-Host "http://localhost:7860" -ForegroundColor Cyan
    Write-Host "   Backend API: " -NoNewline
    Write-Host "http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "📝 USEFUL COMMANDS:" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "• View resources: " -NoNewline
    Write-Host "az resource list --resource-group $($Config.ResourceGroup) --output table" -ForegroundColor Cyan
    Write-Host "• Check costs: " -NoNewline
    Write-Host "az consumption usage list --resource-group $($Config.ResourceGroup)" -ForegroundColor Cyan
    Write-Host "• Delete resources: " -NoNewline
    Write-Host "azd down --environment $($Config.EnvName)" -ForegroundColor Cyan
    Write-Host "• View logs: " -NoNewline
    Write-Host "Get-Content backend\backend.log -Tail 50 -Wait" -ForegroundColor Cyan
    Write-Host ""
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "ℹ️  This script will:" -ForegroundColor Blue
    Write-Host "   1. Check prerequisites"
    Write-Host "   2. Authenticate with Azure"
    Write-Host "   3. Provision minimal Azure resources for local dev"
    Write-Host "   4. Configure your local environment"
    Write-Host "   5. Create all necessary .env files"
    Write-Host ""
    
    $ready = Read-Host "Ready to start? (y/n)"
    if ($ready -ne 'y') {
        Write-Host "⚠️  Setup cancelled" -ForegroundColor Yellow
        exit 1
    }
    
    # Execute setup steps
    Test-Prerequisites
    Connect-AzureAccount
    $config = Get-DeploymentParameters
    Initialize-Azd -Config $config
    Deploy-AzureResources -Config $config
    Initialize-LocalEnvironment
    Show-NextSteps -Config $config
}

# Run main function
Main
