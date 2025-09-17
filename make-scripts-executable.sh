#!/bin/bash
# make-scripts-executable.sh - Hace todos los scripts de shell ejecutables

echo "🔧 Configurando permisos de ejecución para scripts"
echo "=================================================="

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Lista de scripts que necesitan permisos de ejecución
scripts=(
    "setup-local-dev.sh"
    "run-local.sh"
    "run-backend.sh"
    "run-frontend.sh"
    "sync-env.sh"
    "verify-setup.sh"
    "apply-fixes.sh"
    "make-scripts-executable.sh"  # Este mismo script
)

# Hacer ejecutables todos los scripts
echo -e "\n${YELLOW}Aplicando permisos de ejecución...${NC}"

for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        echo -e "${GREEN}✅ $script - permisos aplicados${NC}"
    else
        echo -e "${YELLOW}⚠️  $script - no encontrado (se creará más tarde)${NC}"
    fi
done

# Buscar otros archivos .sh en el proyecto
echo -e "\n${YELLOW}Buscando otros archivos .sh...${NC}"

# Encontrar todos los archivos .sh y hacerlos ejecutables
find . -type f -name "*.sh" -not -path "./.git/*" -not -path "./.venv/*" -not -path "./backend/.venv/*" -not -path "./frontend/.venv/*" | while read -r file; do
    chmod +x "$file"
    echo -e "${GREEN}✅ $file - permisos aplicados${NC}"
done

echo -e "\n${GREEN}✅ Todos los scripts tienen permisos de ejecución${NC}"

# Verificar que los scripts principales son ejecutables
echo -e "\n${YELLOW}Verificando scripts principales...${NC}"

critical_scripts=(
    "setup-local-dev.sh"
    "run-local.sh"
)

all_good=true
for script in "${critical_scripts[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo -e "${GREEN}✅ $script es ejecutable${NC}"
    else
        echo -e "${YELLOW}⚠️  $script no está listo${NC}"
        all_good=false
    fi
done

if [ "$all_good" = true ]; then
    echo -e "\n${GREEN}🎉 ¡Todo listo! Puedes ejecutar:${NC}"
    echo "  ./setup-local-dev.sh  # Para configurar el entorno"
    echo "  ./run-local.sh        # Para ejecutar la aplicación"
else
    echo -e "\n${YELLOW}⚠️ Algunos scripts críticos faltan. Asegúrate de crearlos primero.${NC}"
fi
