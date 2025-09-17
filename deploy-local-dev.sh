#!/bin/bash
# ================================================
# AUTOMATED LOCAL DEVELOPMENT SETUP
# ================================================
# This script provisions minimal Azure resources for local development
# and sets up the complete local environment automatically

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# Configuration
DEFAULT_LOCATION="swedencentral"
DEFAULT_ENV_NAME="dev"

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}🚀 MATH TUTOR - LOCAL DEVELOPMENT SETUP${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "\n${CYAN}▶ $1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..50})${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    local all_ok=true
    
    # Check Azure CLI
    if command -v az &> /dev/null; then
        print_success "Azure CLI installed"
    else
        print_error "Azure CLI not installed"
        echo "   Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        all_ok=false
    fi
    
    # Check Azure Developer CLI
    if command -v azd &> /dev/null; then
        print_success "Azure Developer CLI installed"
    else
        print_error "Azure Developer CLI not installed"
        echo "   Install from: https://aka.ms/azd-install"
        all_ok=false
    fi
    
    # Check Python
    if command -v python3 &> /dev/null; then
        print_success "Python installed"
    else
        print_error "Python not installed"
        all_ok=false
    fi
    
    if [ "$all_ok" = false ]; then
        print_error "Please install missing prerequisites and try again"
        exit 1
    fi
}

# Azure authentication
azure_login() {
    print_step "Azure Authentication"
    
    # Check if already logged in
    if az account show &> /dev/null; then
        CURRENT_USER=$(az account show --query user.name -o tsv)
        CURRENT_SUB=$(az account show --query name -o tsv)
        print_success "Already logged in as: $CURRENT_USER"
        print_info "Subscription: $CURRENT_SUB"
        
        read -p "Do you want to continue with this account? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            az logout
            az login
        fi
    else
        print_warning "Not logged in to Azure"
        az login
    fi
    
    # Let user select subscription if multiple
    print_info "Available subscriptions:"
    az account list --output table
    
    read -p "Enter subscription ID (or press Enter to use current): " SUB_ID
    if [ ! -z "$SUB_ID" ]; then
        az account set --subscription "$SUB_ID"
        print_success "Subscription set to: $SUB_ID"
    fi
}

# Get deployment parameters
get_parameters() {
    print_step "Configuration Parameters"
    
    # Environment name
    read -p "Environment name (default: $DEFAULT_ENV_NAME): " ENV_NAME
    ENV_NAME=${ENV_NAME:-$DEFAULT_ENV_NAME}
    
    # Azure location
    print_info "Available regions: eastus, westus2, westeurope, swedencentral, uksouth"
    read -p "Azure location (default: $DEFAULT_LOCATION): " LOCATION
    LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    
    # Resource group name
    RG_NAME="rg-aifoundry-local-${ENV_NAME}"
    read -p "Resource group name (default: $RG_NAME): " CUSTOM_RG
    RG_NAME=${CUSTOM_RG:-$RG_NAME}
    
    echo ""
    print_info "Configuration summary:"
    echo "   Environment: $ENV_NAME"
    echo "   Location: $LOCATION"
    echo "   Resource Group: $RG_NAME"
    
    read -p "Proceed with these settings? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled"
        exit 1
    fi
}

# Initialize azd environment
init_azd() {
    print_step "Initializing Azure Developer CLI"
    
    # Check if azure-local.yaml exists
    if [ ! -f "azure-local.yaml" ]; then
        print_error "azure-local.yaml not found!"
        print_info "Creating azure-local.yaml..."
        
        # Here you would create the file or copy from template
        print_error "Please ensure azure-local.yaml exists in the project root"
        exit 1
    fi
    
    # Initialize azd with the local config
    azd init --environment "$ENV_NAME" --from-code --cwd . --subscription "$(az account show --query id -o tsv)"
    
    # Set environment variables
    azd env set AZURE_LOCATION "$LOCATION"
    azd env set AZURE_ENV_NAME "$ENV_NAME"
    
    print_success "Azure Developer CLI initialized"
}

# Provision Azure resources
provision_resources() {
    print_step "Provisioning Azure Resources"
    
    print_info "This will create:"
    echo "   • AI Hub and Project"
    echo "   • Storage Account"
    echo "   • Key Vault"
    echo "   • Application Insights"
    echo ""
    print_warning "This may take 5-10 minutes..."
    
    # Use the local bicep file
    azd provision --environment "$ENV_NAME" --no-prompt \
        --alpha-features deployment-stacks \
        --subscription "$(az account show --query id -o tsv)"
    
    if [ $? -eq 0 ]; then
        print_success "Azure resources provisioned successfully!"
    else
        print_error "Provisioning failed. Check the error messages above."
        exit 1
    fi
}

# Setup local environment
setup_local_env() {
    print_step "Setting Up Local Environment"
    
    # Check if .env was created by azd
    if [ ! -f ".env" ]; then
        print_error ".env file not created. Check azd output."
        exit 1
    fi
    
    # Run the Python setup script
    if [ -f "setup-and-verify.py" ]; then
        print_info "Running local setup script..."
        python3 setup-and-verify.py
        
        if [ $? -eq 0 ]; then
            print_success "Local environment configured!"
        else
            print_warning "Setup script reported issues. Check the output above."
        fi
    else
        print_warning "setup-and-verify.py not found. Manual setup required."
    fi
    
    # Make run scripts executable
    chmod +x run-local.sh 2>/dev/null || true
    chmod +x run-backend.sh 2>/dev/null || true
    chmod +x run-frontend.sh 2>/dev/null || true
}

# Display next steps
show_next_steps() {
    echo ""
    print_success "🎉 LOCAL DEVELOPMENT ENVIRONMENT READY!"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}📋 NEXT STEPS:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""
    echo "1. Start the services:"
    echo "   ${CYAN}./run-local.sh${NC}"
    echo ""
    echo "2. Or run services separately:"
    echo "   Terminal 1: ${CYAN}cd backend && source .venv/bin/activate && python main.py${NC}"
    echo "   Terminal 2: ${CYAN}cd frontend && source .venv/bin/activate && python app.py${NC}"
    echo ""
    echo "3. Access the application:"
    echo "   Frontend: ${CYAN}http://localhost:7860${NC}"
    echo "   Backend API: ${CYAN}http://localhost:8000/docs${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📝 USEFUL COMMANDS:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""
    echo "• View resources: ${CYAN}az resource list --resource-group $RG_NAME --output table${NC}"
    echo "• Check costs: ${CYAN}az consumption usage list --resource-group $RG_NAME${NC}"
    echo "• Delete resources: ${CYAN}azd down --environment $ENV_NAME${NC}"
    echo "• View logs: ${CYAN}tail -f backend/backend.log${NC}"
    echo ""
}

# Main execution
main() {
    echo ""
    print_info "This script will:"
    echo "   1. Check prerequisites"
    echo "   2. Authenticate with Azure"
    echo "   3. Provision minimal Azure resources for local dev"
    echo "   4. Configure your local environment"
    echo "   5. Create all necessary .env files"
    echo ""
    
    read -p "Ready to start? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled"
        exit 1
    fi
    
    # Execute setup steps
    check_prerequisites
    azure_login
    get_parameters
    init_azd
    provision_resources
    setup_local_env
    show_next_steps
}

# Run main function
main
