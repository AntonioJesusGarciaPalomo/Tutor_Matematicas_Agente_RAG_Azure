#!/bin/bash
# ================================================
# SETUP LOCAL DEVELOPMENT ENVIRONMENT
# ================================================
# Este script configura el entorno de desarrollo local
# SIN provisionar recursos en Azure

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}🚀 MATH TUTOR - LOCAL DEVELOPMENT SETUP${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Función para imprimir mensajes con color
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

# Verificar prerrequisitos
check_prerequisites() {
    print_step "Verificando Prerrequisitos"
    
    local all_ok=true
    
    # Check Python
    if command -v python3 &> /dev/null; then
        print_success "Python instalado"
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        print_success "Python instalado"
        PYTHON_CMD="python"
    else
        print_error "Python NO instalado"
        all_ok=false
    fi
    
    # Check pip
    if $PYTHON_CMD -m pip --version &> /dev/null; then
        print_success "pip instalado"
    else
        print_error "pip NO instalado"
        all_ok=false
    fi
    
    # Check Azure CLI (opcional para desarrollo local)
    if command -v az &> /dev/null; then
        print_success "Azure CLI instalado"
    else
        print_warning "Azure CLI no instalado (opcional para desarrollo local)"
    fi
    
    # Check Docker (opcional)
    if command -v docker &> /dev/null; then
        print_success "Docker instalado (opcional)"
    else
        print_info "Docker no instalado (opcional)"
    fi
    
    if [ "$all_ok" = false ]; then
        print_error "Faltan prerrequisitos obligatorios"
        exit 1
    fi
}

# Crear archivo .env si no existe
setup_env_file() {
    print_step "Configurando archivo .env"
    
    if [ -f ".env" ]; then
        print_success ".env ya existe"
        read -p "¿Deseas sobrescribirlo con el template? (s/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            return
        fi
    fi
    
    if [ -f ".env.template" ]; then
        cp .env.template .env
        print_success ".env creado desde template"
        print_warning "IMPORTANTE: Edita .env con tus valores de Azure antes de ejecutar la aplicación"
        
        # Copiar a subdirectorios
        if [ -d "backend" ]; then
            cp .env backend/.env
            print_success ".env copiado a backend/"
        fi
        
        if [ -d "frontend" ]; then
            cp .env frontend/.env
            print_success ".env copiado a frontend/"
        fi
    else
        print_error ".env.template no encontrado"
        exit 1
    fi
}

# Crear entornos virtuales
setup_virtual_environments() {
    print_step "Creando Entornos Virtuales"
    
    # Backend venv
    if [ ! -d "backend/.venv" ]; then
        print_info "Creando venv para Backend..."
        $PYTHON_CMD -m venv backend/.venv
        print_success "Backend venv creado"
    else
        print_success "Backend venv ya existe"
    fi
    
    # Frontend venv
    if [ ! -d "frontend/.venv" ]; then
        print_info "Creando venv para Frontend..."
        $PYTHON_CMD -m venv frontend/.venv
        print_success "Frontend venv creado"
    else
        print_success "Frontend venv ya existe"
    fi
}

# Instalar dependencias
install_dependencies() {
    print_step "Instalando Dependencias"
    
    # Backend dependencies
    if [ -f "backend/requirements.txt" ]; then
        print_info "Instalando dependencias del Backend..."
        source backend/.venv/bin/activate
        pip install --upgrade pip --quiet
        pip install -r backend/requirements.txt --quiet
        deactivate
        print_success "Dependencias del Backend instaladas"
    else
        print_error "backend/requirements.txt no encontrado"
    fi
    
    # Frontend dependencies
    if [ -f "frontend/requirements.txt" ]; then
        print_info "Instalando dependencias del Frontend..."
        source frontend/.venv/bin/activate
        pip install --upgrade pip --quiet
        pip install -r frontend/requirements.txt --quiet
        deactivate
        print_success "Dependencias del Frontend instaladas"
    else
        print_error "frontend/requirements.txt no encontrado"
    fi
}

# Hacer ejecutables los scripts
make_scripts_executable() {
    print_step "Configurando permisos de scripts"
    
    local scripts=(
        "run-local.sh"
        "run-backend.sh"
        "run-frontend.sh"
        "deploy-local-dev.sh"
        "make-scripts-executable.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script"
            print_success "$script ahora es ejecutable"
        fi
    done
}

# Verificar la configuración
verify_setup() {
    print_step "Verificando Configuración"
    
    # Verificar que los directorios existen
    local all_ok=true
    
    if [ -d "backend" ]; then
        print_success "Directorio backend existe"
    else
        print_error "Directorio backend NO existe"
        all_ok=false
    fi
    
    if [ -d "frontend" ]; then
        print_success "Directorio frontend existe"
    else
        print_error "Directorio frontend NO existe"
        all_ok=false
    fi
    
    if [ -f ".env" ]; then
        print_success "Archivo .env existe"
        
        # Verificar variables críticas
        if grep -q "PROJECT_ENDPOINT=" .env && ! grep -q "PROJECT_ENDPOINT=$" .env; then
            print_success "PROJECT_ENDPOINT configurado"
        else
            print_warning "PROJECT_ENDPOINT no configurado en .env"
        fi
        
        if grep -q "STORAGE_ACCOUNT_NAME=" .env && ! grep -q "STORAGE_ACCOUNT_NAME=$" .env; then
            print_success "STORAGE_ACCOUNT_NAME configurado"
        else
            print_warning "STORAGE_ACCOUNT_NAME no configurado en .env"
        fi
    else
        print_error "Archivo .env NO existe"
        all_ok=false
    fi
    
    if [ "$all_ok" = false ]; then
        print_error "La configuración no está completa"
        return 1
    else
        print_success "Configuración verificada correctamente"
        return 0
    fi
}

# Mostrar siguiente pasos
show_next_steps() {
    echo ""
    echo -e "${GREEN}🎉 CONFIGURACIÓN COMPLETADA${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}📋 PRÓXIMOS PASOS:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""
    
    # Verificar si .env necesita configuración
    if [ -f ".env" ]; then
        if grep -q "YOUR_\|REPLACE_" .env; then
            echo -e "${YELLOW}1. IMPORTANTE: Configura las variables en .env:${NC}"
            echo "   - PROJECT_ENDPOINT"
            echo "   - STORAGE_ACCOUNT_NAME"
            echo "   - MODEL_DEPLOYMENT_NAME"
            echo ""
        fi
    fi
    
    echo "2. Ejecutar la aplicación:"
    echo -e "   ${CYAN}./run-local.sh${NC}         # Backend + Frontend"
    echo -e "   ${CYAN}make run-local${NC}         # Con Make"
    echo -e "   ${CYAN}docker-compose up${NC}      # Con Docker"
    echo ""
    echo "3. Abrir en el navegador:"
    echo -e "   Frontend: ${CYAN}http://localhost:7860${NC}"
    echo -e "   Backend API: ${CYAN}http://localhost:8000/docs${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}💡 COMANDOS ÚTILES:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "• Verificar estado: ${CYAN}python setup-and-verify.py${NC}"
    echo -e "• Ver logs: ${CYAN}tail -f backend/backend.log${NC}"
    echo -e "• Ejecutar tests: ${CYAN}make test${NC}"
    echo -e "• Ver ayuda: ${CYAN}make help${NC}"
    echo ""
}

# Main execution
main() {
    echo ""
    print_info "Este script configurará tu entorno de desarrollo local"
    print_info "NO provisionará recursos en Azure"
    echo ""
    
    read -p "¿Continuar? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_warning "Setup cancelado"
        exit 1
    fi
    
    # Ejecutar pasos
    check_prerequisites
    setup_env_file
    setup_virtual_environments
    install_dependencies
    make_scripts_executable
    
    # Verificar
    if verify_setup; then
        show_next_steps
    else
        print_error "Setup incompleto. Revisa los errores anteriores."
        exit 1
    fi
}

# Ejecutar main
main
