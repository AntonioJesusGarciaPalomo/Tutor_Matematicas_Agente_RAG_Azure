#!/bin/bash

echo "🚀 Configurando entorno de desarrollo local para Math Tutor"
echo "=========================================================="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para verificar comandos
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 no está instalado${NC}"
        return 1
    else
        echo -e "${GREEN}✅ $1 está instalado${NC}"
        return 0
    fi
}

# 1. Verificar prerrequisitos
echo -e "\n${YELLOW}1. Verificando prerrequisitos...${NC}"
check_command python3
check_command pip
check_command az

# 2. Verificar autenticación de Azure
echo -e "\n${YELLOW}2. Verificando autenticación de Azure...${NC}"
if az account show &> /dev/null; then
    echo -e "${GREEN}✅ Autenticado en Azure${NC}"
else
    echo -e "${YELLOW}⚠️ No autenticado en Azure. Ejecutando 'az login'...${NC}"
    az login
fi

# 3. Crear entornos virtuales
echo -e "\n${YELLOW}3. Creando entornos virtuales...${NC}"

# Backend
if [ ! -d "backend/.venv" ]; then
    echo "Creando entorno virtual para backend..."
    python3 -m venv backend/.venv
    echo -e "${GREEN}✅ Entorno virtual del backend creado${NC}"
else
    echo -e "${GREEN}✅ Entorno virtual del backend ya existe${NC}"
fi

# Frontend
if [ ! -d "frontend/.venv" ]; then
    echo "Creando entorno virtual para frontend..."
    python3 -m venv frontend/.venv
    echo -e "${GREEN}✅ Entorno virtual del frontend creado${NC}"
else
    echo -e "${GREEN}✅ Entorno virtual del frontend ya existe${NC}"
fi

# 4. Instalar dependencias
echo -e "\n${YELLOW}4. Instalando dependencias...${NC}"

# Backend
echo "Instalando dependencias del backend..."
source backend/.venv/bin/activate
pip install -q --upgrade pip
pip install -q -r backend/requirements.txt
deactivate
echo -e "${GREEN}✅ Dependencias del backend instaladas${NC}"

# Frontend
echo "Instalando dependencias del frontend..."
source frontend/.venv/bin/activate
pip install -q --upgrade pip
pip install -q -r frontend/requirements.txt
deactivate
echo -e "${GREEN}✅ Dependencias del frontend instaladas${NC}"

# 5. Verificar archivo .env
echo -e "\n${YELLOW}5. Configurando variables de entorno...${NC}"
if [ ! -f ".env" ]; then
    if [ -f ".env.template" ]; then
        cp .env.template .env
        echo -e "${YELLOW}⚠️ Archivo .env creado desde template. Por favor, configura las variables:${NC}"
        echo "   - PROJECT_ENDPOINT"
        echo "   - STORAGE_ACCOUNT_NAME"
        echo "   - MODEL_DEPLOYMENT_NAME"
        echo ""
        echo -e "${YELLOW}Edita el archivo .env y ejecuta este script de nuevo.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Archivo .env encontrado${NC}"
fi

# Configurar Azure Location en azd si está disponible
if [ -f ".env" ]; then
    AZURE_LOCATION=$(grep "^AZURE_LOCATION=" .env | cut -d '=' -f2)
    if [ -n "$AZURE_LOCATION" ]; then
        # Solo configurar si azd está instalado
        if command -v azd &> /dev/null; then
            azd env set AZURE_LOCATION $AZURE_LOCATION 2>/dev/null
            echo -e "${GREEN}✅ Región de Azure configurada: $AZURE_LOCATION${NC}"
        fi
    fi
fi

# 6. Copiar .env a los directorios
cp .env backend/.env
cp .env frontend/.env
echo -e "${GREEN}✅ Variables de entorno configuradas${NC}"

# 7. Crear scripts de ejecución
echo -e "\n${YELLOW}6. Creando scripts de ejecución...${NC}"

# Script para ejecutar backend
cat > run-backend.sh << 'EOF'
#!/bin/bash
echo "🚀 Iniciando Backend..."
cd backend
source .venv/bin/activate
python main.py
EOF
chmod +x run-backend.sh

# Script para ejecutar frontend
cat > run-frontend.sh << 'EOF'
#!/bin/bash
echo "🚀 Iniciando Frontend..."
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py
EOF
chmod +x run-frontend.sh

# Script para ejecutar ambos
cat > run-local.sh << 'EOF'
#!/bin/bash
echo "🚀 Iniciando Math Tutor en modo local..."
echo "========================================="

# Función para matar procesos al salir
cleanup() {
    echo -e "\n🛑 Deteniendo servicios..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    exit
}

trap cleanup EXIT INT TERM

# Iniciar backend
echo "▶️ Iniciando Backend en http://localhost:8000"
cd backend
source .venv/bin/activate
python main.py &
BACKEND_PID=$!
cd ..

# Esperar a que el backend esté listo
echo "⏳ Esperando a que el backend esté listo..."
sleep 5

# Verificar que el backend está respondiendo
if curl -s http://localhost:8000/health > /dev/null; then
    echo "✅ Backend está listo"
else
    echo "❌ El backend no responde. Verifica los logs."
fi

# Iniciar frontend
echo "▶️ Iniciando Frontend en http://localhost:7860"
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py &
FRONTEND_PID=$!
cd ..

echo ""
echo "========================================="
echo "✅ Servicios iniciados:"
echo "   - Backend:  http://localhost:8000"
echo "   - Frontend: http://localhost:7860"
echo ""
echo "📝 Logs:"
echo "   - Presiona Ctrl+C para detener ambos servicios"
echo "========================================="

# Mantener el script ejecutándose
wait
EOF
chmod +x run-local.sh

echo -e "${GREEN}✅ Scripts de ejecución creados${NC}"

# 8. Resumen final
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ ¡Configuración completada con éxito!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "📋 Próximos pasos:"
echo ""
echo "1. Verifica que el archivo .env tiene las variables configuradas:"
echo "   cat .env"
echo ""
echo "2. Para ejecutar los servicios por separado:"
echo "   ./run-backend.sh   # En una terminal"
echo "   ./run-frontend.sh  # En otra terminal"
echo ""
echo "3. Para ejecutar ambos servicios juntos:"
echo "   ./run-local.sh"
echo ""
echo "4. Abre el navegador en http://localhost:7860"
echo ""
echo "💡 Tips para desarrollo:"
echo "   - El backend tiene hot-reload activado"
echo "   - Puedes ver los logs en tiempo real"
echo "   - Usa /health para verificar el estado del backend"
echo "   - Usa /cleanup_agent para limpiar el agente (solo en local)"