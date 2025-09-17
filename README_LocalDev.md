# 🚀 Guía de Desarrollo Local - Math Tutor AI

Esta guía te ayudará a configurar y ejecutar el proyecto en tu máquina local para desarrollo y debugging.

## 📋 Prerrequisitos

- **Python 3.12+**
- **Azure CLI** (`az`)
- **Docker** y **Docker Compose** (opcional)
- **Make** (opcional, pero recomendado)
- Una suscripción de **Azure** con los recursos ya desplegados

## 🛠️ Configuración Inicial

### 1. Clonar el Repositorio

```bash
git clone <URL_DEL_REPOSITORIO>
cd math-tutor-aifoundry
```

### 2. Configurar Variables de Entorno

Copia el template y configura tus variables:

```bash
cp .env.template .env
```

Edita `.env` con tus valores de Azure:

```env
# Variables de Azure AI Foundry
PROJECT_ENDPOINT=https://tu-proyecto.services.ai.azure.com/api/projects/tu-proyecto
MODEL_DEPLOYMENT_NAME=gpt-4o

# Variables de Storage
STORAGE_ACCOUNT_NAME=tu-storage-account
IMAGES_CONTAINER_NAME=images

# URLs de los servicios (para desarrollo local)
BACKEND_URI=http://localhost:8000
FRONTEND_URI=http://localhost:7860

# Container Registry (si usas Docker)
AZURE_CONTAINER_REGISTRY_ENDPOINT=tu-registry.azurecr.io
```

### 3. Autenticación con Azure

```bash
# Login en Azure CLI
az login

# Verificar la suscripción activa
az account show

# Si necesitas cambiar de suscripción
az account set --subscription "Tu-Suscripcion"
```

## 🏃‍♂️ Métodos de Ejecución

### Método 1: Usando Make (Recomendado)

```bash
# Setup completo (crea venvs e instala dependencias)
make setup

# Ejecutar backend y frontend juntos
make run-local

# O ejecutar por separado
make run-backend  # En una terminal
make run-frontend # En otra terminal
```

### Método 2: Usando Scripts Bash

```bash
# Configuración inicial
chmod +x setup-local-dev.sh
./setup-local-dev.sh

# Ejecutar servicios
./run-local.sh  # Ambos servicios juntos

# O por separado
./run-backend.sh   # En una terminal
./run-frontend.sh  # En otra terminal
```

### Método 3: Usando Docker Compose

```bash
# Construir y ejecutar
docker-compose up --build

# O en segundo plano
docker-compose up -d --build

# Ver logs
docker-compose logs -f backend
docker-compose logs -f frontend

# Detener
docker-compose down
```

### Método 4: Manualmente

```bash
# Backend
cd backend
python -m venv .venv
source .venv/bin/activate  # En Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py

# Frontend (en otra terminal)
cd frontend
python -m venv .venv
source .venv/bin/activate  # En Windows: .venv\Scripts\activate
pip install -r requirements.txt
export BACKEND_URI=http://localhost:8000
python app.py
```

## 🧪 Testing

### Ejecutar Tests

```bash
# Todos los tests
make test

# Solo backend
make test-backend

# Tests de integración
make test-integration

# Manualmente
cd tests
python test_backend.py
python test_integration.py
```

### Tests Manuales Recomendados

1. **Health Check del Backend:**
   ```bash
   curl http://localhost:8000/health | python -m json.tool
   ```

2. **Iniciar Chat:**
   ```bash
   curl -X POST http://localhost:8000/start_chat | python -m json.tool
   ```

3. **Enviar Mensaje:**
   ```bash
   curl -X POST http://localhost:8000/chat \
     -H "Content-Type: application/json" \
     -d '{
       "thread_id": "TU_THREAD_ID",
       "message": "¿Cuánto es 2+2?"
     }'
   ```

## 🔍 Debugging

### Backend

El backend está configurado con hot-reload. Los cambios se aplican automáticamente.

**Logs detallados:**
```python
# En main.py, ajusta el nivel de logging
logging.basicConfig(level=logging.DEBUG)
```

**Endpoints útiles para debugging:**
- `/health` - Estado del servicio
- `/cleanup_agent` - Limpia el agente (solo en local)

### Frontend

**Ver solicitudes al backend:**
```python
# En app.py, habilita logs detallados
logging.basicConfig(level=logging.DEBUG)
```

**Inspeccionar en el navegador:**
1. Abre las Developer Tools (F12)
2. Ve a la pestaña Network
3. Observa las solicitudes al backend

### Problemas Comunes y Soluciones

#### 1. Error de Autenticación con Azure

**Síntoma:** `Error: DefaultAzureCredential failed`

**Solución:**
```bash
# Verificar autenticación
az account show

# Re-autenticar
az logout
az login

# Si usas Docker, asegúrate de montar las credenciales
docker-compose down
docker-compose up --build
```

#### 2. Backend No Responde

**Síntoma:** Frontend muestra "Cannot connect to backend"

**Solución:**
```bash
# Verificar que el backend está corriendo
curl http://localhost:8000/health

# Revisar logs del backend
make logs-backend  # Si usas Docker

# Verificar variables de entorno
cat .env
```

#### 3. Agente No Se Crea

**Síntoma:** `Error creating agent`

**Solución:**
```bash
# Verificar el endpoint del proyecto
echo $PROJECT_ENDPOINT

# Verificar permisos en Azure
az role assignment list --assignee $(az account show --query user.name -o tsv)

# Limpiar y recrear el agente
curl -X DELETE http://localhost:8000/cleanup_agent
```

#### 4. Imágenes No Se Muestran

**Síntoma:** Las visualizaciones no aparecen en el chat

**Solución:**
```bash
# Verificar permisos del Storage Account
az storage container show \
  --name images \
  --account-name $STORAGE_ACCOUNT_NAME

# Verificar que el contenedor es público
az storage container set-permission \
  --name images \
  --public-access blob \
  --account-name $STORAGE_ACCOUNT_NAME
```

## 📊 Monitoreo

### Monitor en Tiempo Real

```bash
# Estado de servicios
make monitor

# O manualmente
watch -n 2 'curl -s http://localhost:8000/health | python -m json.tool'
```

### Métricas del Sistema

```python
# Añadir en main.py para métricas personalizadas
import psutil

@app.get("/metrics")
async def metrics():
    return {
        "cpu_percent": psutil.cpu_percent(),
        "memory_percent": psutil.virtual_memory().percent,
        "active_threads": len(agent_manager.active_threads)
    }
```

## 🔧 Configuración Avanzada

### Variables de Entorno Adicionales

```env
# Timeouts
STARTUP_TIMEOUT=30
CHAT_TIMEOUT=60

# Logging
LOG_LEVEL=DEBUG

# Desarrollo
RELOAD=true
DEBUG=true
```

### Personalización del Agente

Edita `backend/main.py`:

```python
agent = project_client.agents.create_agent(
    model=model_deployment_name,
    name=AGENT_NAME,
    instructions="""
    Tu personalización aquí...
    """,
    tools=code_interpreter.definitions,
    temperature=0.7,  # Ajustar creatividad
    max_tokens=2000   # Ajustar longitud de respuesta
)
```

## 🚀 Workflow de Desarrollo Recomendado

1. **Hacer cambios en el código**
2. **Verificar que los tests pasan:**
   ```bash
   make test
   ```
3. **Probar localmente:**
   ```bash
   make run-local
   ```
4. **Verificar en el navegador:**
   - Abrir http://localhost:7860
   - Probar diferentes escenarios
5. **Commit y push:**
   ```bash
   git add .
   git commit -m "feat: descripción del cambio"
   git push
   ```
6. **Desplegar a Azure:**
   ```bash
   make deploy
   ```

## 📝 Scripts Útiles

### Reiniciar Todo

```bash
make restart  # Si usas Docker
# O
make clean-all && make setup && make run-local
```

### Ver Estado Completo

```bash
make health-check
```

### Formatear Código

```bash
make format
```

### Analizar Código

```bash
make lint
```

## 🆘 Soporte

Si encuentras problemas:

1. Revisa los logs detallados
2. Consulta la sección de problemas comunes
3. Verifica las variables de entorno
4. Asegúrate de tener los permisos correctos en Azure
5. Abre un issue en el repositorio con los detalles del error

## 📚 Recursos Adicionales

- [Azure AI Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Gradio Documentation](https://www.gradio.app/docs/)
- [Azure CLI Reference](https://docs.microsoft.com/cli/azure/)

---

💡 **Tip:** Mantén siempre actualizadas tus dependencias y revisa regularmente los logs para detectar posibles problemas tempranamente.