# ================================================
# AUTOMATED LOCAL DEVELOPMENT SETUP FOR WINDOWS
# ================================================

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
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-Host "OK: Azure CLI installed (version $($azVersion.'azure-cli'))" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Azure CLI not installed" -ForegroundColor Red
        Write-Host "Install from: https://docs.microsoft.com/cli/azure/install" -ForegroundColor Yellow
        $allOk = $false
    }
    
    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        Write-Host "OK: Python installed ($pythonVersion)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Python not installed" -ForegroundColor Red
        $allOk = $false
    }
    
    # Install/update Bicep
    Write-Host "Checking Bicep..." -ForegroundColor Yellow
    az bicep upgrade 2>&1 | Out-Null
    Write-Host "OK: Bicep ready" -ForegroundColor Green
    
    return $allOk
}

# Register Resource Providers
function Register-ResourceProviders {
    Write-Host "`nRegistering Azure Resource Providers..." -ForegroundColor Cyan
    
    $providers = @(
        "Microsoft.MachineLearningServices",
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.Insights",
        "Microsoft.OperationalInsights"
    )
    
    foreach ($provider in $providers) {
        Write-Host "  Checking $provider..." -ForegroundColor Gray
        $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
        
        if ($state -ne "Registered") {
            Write-Host "    Registering $provider..." -ForegroundColor Yellow
            az provider register --namespace $provider --wait
        } else {
            Write-Host "    ✅ $provider already registered" -ForegroundColor Green
        }
    }
}

# Function to get deployment outputs and create .env
function Create-EnvFile {
    param(
        [string]$ResourceGroup,
        [string]$Location,
        [string]$DeploymentName
    )
    
    Write-Host "`nRetrieving resource information..." -ForegroundColor Yellow
    
    # Inicializar variables
    $STORAGE_ACCOUNT_NAME = ""
    $STORAGE_ACCOUNT_KEY = ""
    $KEY_VAULT_NAME = ""
    $AI_HUB_NAME = ""
    $AI_PROJECT_NAME = ""
    $PROJECT_ENDPOINT = ""
    
    # Get Storage Account
    $storageAccounts = az storage account list `
        --resource-group $ResourceGroup `
        --output json 2>$null | ConvertFrom-Json
    
    if ($storageAccounts -and $storageAccounts.Count -gt 0) {
        $STORAGE_ACCOUNT_NAME = $storageAccounts[0].name
        Write-Host "  Found Storage: $STORAGE_ACCOUNT_NAME" -ForegroundColor Green
        
        # Get Storage Key
        $STORAGE_ACCOUNT_KEY = az storage account keys list `
            --account-name $STORAGE_ACCOUNT_NAME `
            --resource-group $ResourceGroup `
            --query "[0].value" `
            -o tsv 2>$null
    } else {
        Write-Host "  Storage Account not found - critical resource missing" -ForegroundColor Red
        $STORAGE_ACCOUNT_NAME = "PENDING_MANUAL_CREATION"
        $STORAGE_ACCOUNT_KEY = "PENDING_MANUAL_CREATION"
    }
    
    # Get Key Vault
    $keyVaults = az keyvault list `
        --resource-group $ResourceGroup `
        --output json 2>$null | ConvertFrom-Json
    
    if ($keyVaults -and $keyVaults.Count -gt 0) {
        $KEY_VAULT_NAME = $keyVaults[0].name
        Write-Host "  Found Key Vault: $KEY_VAULT_NAME" -ForegroundColor Green
    } else {
        Write-Host "  Key Vault not found - will need manual creation" -ForegroundColor Yellow
        $KEY_VAULT_NAME = "PENDING_MANUAL_CREATION"
    }
    
    # Get AI Hub and Project
    Write-Host "  Checking for ML workspaces..." -ForegroundColor Gray
    $mlWorkspaces = az ml workspace list `
        --resource-group $ResourceGroup `
        --output json 2>$null | ConvertFrom-Json
    
    if ($mlWorkspaces -and $mlWorkspaces.Count -gt 0) {
        foreach ($workspace in $mlWorkspaces) {
            if ($workspace.kind -eq "Hub") {
                $AI_HUB_NAME = $workspace.name
                Write-Host "  Found AI Hub: $AI_HUB_NAME" -ForegroundColor Green
            } elseif ($workspace.kind -eq "Project") {
                $AI_PROJECT_NAME = $workspace.name
                Write-Host "  Found AI Project: $AI_PROJECT_NAME" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  No ML workspaces found" -ForegroundColor Yellow
    }
    
    if (-not $AI_HUB_NAME -or $AI_HUB_NAME -eq "") {
        Write-Host "  AI Hub not found - will need manual creation" -ForegroundColor Yellow
        $AI_HUB_NAME = "PENDING_MANUAL_CREATION"
    }
    
    if (-not $AI_PROJECT_NAME -or $AI_PROJECT_NAME -eq "") {
        Write-Host "  AI Project not found - will need manual creation" -ForegroundColor Yellow
        $AI_PROJECT_NAME = "PENDING_MANUAL_CREATION"
        $PROJECT_ENDPOINT = "PENDING_MANUAL_CONFIGURATION"
    } else {
        # Construct project endpoint
        $PROJECT_ENDPOINT = "https://${Location}.api.azureml.ms/discovery/workspaces/${AI_PROJECT_NAME}"
        Write-Host "  Project endpoint constructed: $PROJECT_ENDPOINT" -ForegroundColor Gray
    }
    
    Write-Host "`nCreating .env file..." -ForegroundColor Yellow
    
    # Create .env content
    $envContent = @"
# ================================================
# AUTO-GENERATED CONFIGURATION FOR LOCAL DEVELOPMENT
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Resource Group: $ResourceGroup
# Location: $Location
# ================================================

# Azure AI Foundry
PROJECT_ENDPOINT=$PROJECT_ENDPOINT
MODEL_DEPLOYMENT_NAME=gpt-4o
AGENT_NAME=math-tutor-agent

# Azure Storage
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
STORAGE_ACCOUNT_KEY=$STORAGE_ACCOUNT_KEY
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
AZURE_LOCATION=$Location
RESOURCE_GROUP=$ResourceGroup
KEY_VAULT_NAME=$KEY_VAULT_NAME
AI_HUB_NAME=$AI_HUB_NAME
AI_PROJECT_NAME=$AI_PROJECT_NAME
"@
    
    # Save .env file
    $envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
    Write-Host "✅ .env created in root directory" -ForegroundColor Green
    
    # Copy only to backend (frontend doesn't need it)
    if (Test-Path "backend") {
        Copy-Item ".env" "backend\.env" -Force
        Write-Host "✅ .env copied to backend\" -ForegroundColor Green
    }
    
    Write-Host "✅ Configuration files created successfully!" -ForegroundColor Green
    Write-Host "  Note: Frontend uses default localhost:8000 for backend connection" -ForegroundColor Gray
    
    # Verify container exists only if we have valid storage
    if ($STORAGE_ACCOUNT_NAME -and $STORAGE_ACCOUNT_KEY -and 
        $STORAGE_ACCOUNT_NAME -ne "PENDING_MANUAL_CREATION" -and 
        $STORAGE_ACCOUNT_KEY -ne "PENDING_MANUAL_CREATION") {
        
        Write-Host "`nVerifying images container..." -ForegroundColor Yellow
        $containerExists = az storage container exists `
            --name images `
            --account-name $STORAGE_ACCOUNT_NAME `
            --account-key $STORAGE_ACCOUNT_KEY `
            --query "exists" `
            -o tsv 2>$null
        
        if ($containerExists -ne "true") {
            Write-Host "Creating 'images' container..." -ForegroundColor Yellow
            az storage container create `
                --name images `
                --account-name $STORAGE_ACCOUNT_NAME `
                --account-key $STORAGE_ACCOUNT_KEY `
                --public-access blob `
                --output none 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Container 'images' created" -ForegroundColor Green
            } else {
                Write-Host "⚠️ Could not create container" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✅ Container 'images' already exists" -ForegroundColor Green
        }
    }
    
    # Show summary of what needs manual creation
    Write-Host ""
    Write-Host "RESOURCE STATUS SUMMARY:" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan
    
    $needsManualAction = $false
    
    if ($STORAGE_ACCOUNT_NAME -eq "PENDING_MANUAL_CREATION") {
        Write-Host "❌ Storage Account: Missing (critical)" -ForegroundColor Red
        $needsManualAction = $true
    } else {
        Write-Host "✅ Storage Account: $STORAGE_ACCOUNT_NAME" -ForegroundColor Green
    }
    
    if ($KEY_VAULT_NAME -eq "PENDING_MANUAL_CREATION") {
        Write-Host "⚠️  Key Vault: Missing (required by AI Hub)" -ForegroundColor Yellow
        $needsManualAction = $true
    } else {
        Write-Host "✅ Key Vault: $KEY_VAULT_NAME" -ForegroundColor Green
    }
    
    if ($AI_HUB_NAME -eq "PENDING_MANUAL_CREATION") {
        Write-Host "⚠️  AI Hub: Missing (required for agent)" -ForegroundColor Yellow
        $needsManualAction = $true
    } else {
        Write-Host "✅ AI Hub: $AI_HUB_NAME" -ForegroundColor Green
    }
    
    if ($AI_PROJECT_NAME -eq "PENDING_MANUAL_CREATION") {
        Write-Host "⚠️  AI Project: Missing (required for agent)" -ForegroundColor Yellow
        $needsManualAction = $true
    } else {
        Write-Host "✅ AI Project: $AI_PROJECT_NAME" -ForegroundColor Green
    }
    
    # Provide manual action instructions if needed
    if ($needsManualAction) {
        Write-Host ""
        Write-Host "⚠️ MANUAL ACTION REQUIRED:" -ForegroundColor Yellow
        Write-Host "===========================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Option 1: Create missing resources manually in Azure Portal" -ForegroundColor Cyan
        Write-Host "  1. Go to: https://portal.azure.com" -ForegroundColor White
        Write-Host "  2. Navigate to Resource Group: $ResourceGroup" -ForegroundColor White
        
        if ($KEY_VAULT_NAME -eq "PENDING_MANUAL_CREATION") {
            Write-Host "  3. Create a Key Vault" -ForegroundColor White
        }
        
        if ($AI_HUB_NAME -eq "PENDING_MANUAL_CREATION") {
            Write-Host "  4. Go to Azure AI Studio: https://ai.azure.com" -ForegroundColor White
            Write-Host "  5. Create an AI Hub in the resource group" -ForegroundColor White
        }
        
        if ($AI_PROJECT_NAME -eq "PENDING_MANUAL_CREATION") {
            Write-Host "  6. Create an AI Project inside the Hub" -ForegroundColor White
            Write-Host "  7. Update PROJECT_ENDPOINT in .env file" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "Option 2: Delete the resource group and retry" -ForegroundColor Cyan
        Write-Host "  az group delete --name $ResourceGroup --yes" -ForegroundColor White
        Write-Host "  Then run this script again" -ForegroundColor White
    }
    
    return $true
}


# Main execution
function Main {
    Write-Host "This script will:" -ForegroundColor Blue
    Write-Host "   1. Check prerequisites"
    Write-Host "   2. Authenticate with Azure"
    Write-Host "   3. Provision minimal Azure resources for local dev"
    Write-Host "   4. Create all necessary .env files"
    Write-Host ""
    
    $ready = Read-Host "Ready to start? (y/n)"
    if ($ready -ne 'y') {
        Write-Host "Setup cancelled" -ForegroundColor Yellow
        exit 0
    }
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Host "`nPlease install missing prerequisites and try again" -ForegroundColor Red
        exit 1
    }
    
    # Azure authentication
    Write-Host "`nAzure Authentication" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
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
    
    # Register providers
    Register-ResourceProviders
    
    # Get deployment parameters
    Write-Host "`nConfiguration Parameters" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    $envName = Read-Host "Environment name (default: $DEFAULT_ENV_NAME)"
    if (-not $envName) { $envName = $DEFAULT_ENV_NAME }
    
    Write-Host "Available regions: eastus, westus2, westeurope, swedencentral, northeurope, uksouth" -ForegroundColor Blue
    $location = Read-Host "Azure location (default: $DEFAULT_LOCATION)"
    if (-not $location) { $location = $DEFAULT_LOCATION }
    
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
        exit 0
    }
    
    # Create resource group
    Write-Host "`nCreating resource group..." -ForegroundColor Yellow
    
    $rgExists = az group exists --name $rgName 2>$null
    
    if ($rgExists -eq "false") {
        az group create `
            --name $rgName `
            --location $location `
            --tags "Environment=LocalDev" "Project=MathTutor" `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Resource group created: $rgName" -ForegroundColor Green
        } else {
            Write-Host "Failed to create resource group" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Resource group already exists: $rgName" -ForegroundColor Green
    }
    
    # Deploy using Bicep
    Write-Host "`nDeploying resources with Bicep..." -ForegroundColor Yellow
    Write-Host "This will take 5-10 minutes, please be patient..." -ForegroundColor Gray
    
    $deploymentName = "local-dev-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Host "Deployment name: $deploymentName" -ForegroundColor Gray
    
    # Execute deployment - capturando warnings pero sin detener el script
    $originalErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    az deployment group create `
        --name $deploymentName `
        --resource-group $rgName `
        --template-file "infra/main-local.bicep" `
        --parameters location=$location environmentName=$envName `
        --output none 2>&1 | Out-Null
    
    $ErrorActionPreference = $originalErrorActionPreference
    
    # Check deployment status
    Write-Host "`nChecking deployment status..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    
    $deployment = az deployment group show `
        --name $deploymentName `
        --resource-group $rgName `
        --output json 2>$null | ConvertFrom-Json
    
    if ($deployment -and $deployment.properties.provisioningState -eq "Succeeded") {
        Write-Host "✅ Azure resources provisioned successfully!" -ForegroundColor Green
        
        # List resources created
        Write-Host "`nResources created:" -ForegroundColor Cyan
        $resources = az resource list --resource-group $rgName --query "[].{Name:name, Type:type}" --output table
        Write-Host $resources
        
        # Create .env file with deployment outputs
        $envCreated = Create-EnvFile -ResourceGroup $rgName -Location $location -DeploymentName $deploymentName
        
        if ($envCreated) {
            # Setup Python environment
            Write-Host "`nSetting up Python environment..." -ForegroundColor Cyan
            Write-Host ("=" * 50) -ForegroundColor Cyan
            
            if (Test-Path "setup-and-verify.py") {
                Write-Host "Running Python setup script..." -ForegroundColor Yellow
                python setup-and-verify.py
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Python environment configured!" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ Python setup had some issues. Check the output above." -ForegroundColor Yellow
                }
            }
            
            # Show summary
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "   LOCAL DEVELOPMENT SETUP COMPLETE!    " -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "RESOURCES CREATED IN AZURE:" -ForegroundColor Cyan
            Write-Host "  Resource Group: $rgName" -ForegroundColor White
            Write-Host "  Location: $location" -ForegroundColor White
            
            # Show what's in the .env
            Write-Host ""
            Write-Host "CONFIGURATION (.env created):" -ForegroundColor Cyan
            if (Test-Path ".env") {
                $envVars = Get-Content ".env" | Where-Object { $_ -match "^[^#].*=" }
                foreach ($line in $envVars) {
                    if ($line -match "KEY|SECRET|PASSWORD") {
                        $parts = $line.Split('=')
                        Write-Host "  $($parts[0])=***" -ForegroundColor Gray
                    } else {
                        Write-Host "  $line" -ForegroundColor Gray
                    }
                }
            }
            
            Write-Host ""
            Write-Host "NEXT STEPS:" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "1. Start the services:" -ForegroundColor Yellow
            Write-Host "   .\run-local.bat" -ForegroundColor Cyan
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
            Write-Host "  Check resources: az resource list --resource-group $rgName --output table" -ForegroundColor Gray
            Write-Host "  Check deployment: .\check-deployment.ps1" -ForegroundColor Gray
            Write-Host "  Delete resources: az group delete --name $rgName --yes" -ForegroundColor Gray
            Write-Host ""
        } else {
            Write-Host "⚠️ .env file creation had issues" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️ Deployment had issues" -ForegroundColor Yellow
        
        if ($deployment) {
            Write-Host "Status: $($deployment.properties.provisioningState)" -ForegroundColor Yellow
            
            if ($deployment.properties.error) {
                Write-Host "Error: $($deployment.properties.error.message)" -ForegroundColor Red
            }
        }
        
        # Intentar crear .env con los recursos que se hayan creado
        Write-Host "`nAttempting to create .env with existing resources..." -ForegroundColor Yellow
        
        # Verificar qué recursos existen
        $existingResources = az resource list --resource-group $rgName --output json 2>$null | ConvertFrom-Json
        
        if ($existingResources -and $existingResources.Count -gt 0) {
            Write-Host "Found $($existingResources.Count) resources in the resource group" -ForegroundColor Cyan
            
            foreach ($resource in $existingResources) {
                Write-Host "  - $($resource.name) ($($resource.type))" -ForegroundColor Gray
            }
            
            $envCreated = Create-EnvFile -ResourceGroup $rgName -Location $location -DeploymentName $deploymentName
            
            if ($envCreated) {
                Write-Host "`n✅ .env created with available resources" -ForegroundColor Green
                
                # Continuar con el setup de Python
                if (Test-Path "setup-and-verify.py") {
                    Write-Host "`nRunning Python setup..." -ForegroundColor Yellow
                    python setup-and-verify.py
                }
                
                Write-Host ""
                Write-Host "NEXT STEPS:" -ForegroundColor Cyan
                Write-Host "1. Complete any manual resource creation if needed" -ForegroundColor White
                Write-Host "2. Update .env file if PROJECT_ENDPOINT shows PENDING" -ForegroundColor White
                Write-Host "3. Run: .\run-local.bat" -ForegroundColor White
            }
        } else {
            Write-Host "❌ No resources found in resource group" -ForegroundColor Red
        }
        
        Write-Host "`nYou can check the deployment in Azure Portal" -ForegroundColor Yellow
        Write-Host "Or run: .\check-deployment.ps1" -ForegroundColor Cyan
    }
}

# Run main function
Main