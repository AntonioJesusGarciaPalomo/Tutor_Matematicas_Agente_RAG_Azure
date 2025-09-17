# 🎓 Tutor de Matemáticas con AI Foundry Agent Service

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=flat&logo=azure-devops&logoColor=white)](https://azure.microsoft.com)
[![Python](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=flat&logo=fastapi)](https://fastapi.tiangolo.com)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com)

[🚀 Inicio Rápido](#-inicio-rápido) | [💻 Desarrollo Local](#-desarrollo-local) | [☁️ Despliegue Azure](#-despliegue-en-azure) | [📖 Documentación](#-arquitectura) | [❓ FAQ](#-faq)

---

Este proyecto implementa un asistente matemático inteligente utilizando el Azure AI Foundry Agent Service. La solución ofrece un tutor virtual capaz de:

- 📚 Responder preguntas matemáticas de diversos niveles
- 📊 Generar visualizaciones y gráficas usando CodeInterpreterTool
- 🧮 Resolver problemas paso a paso
- 📝 Proporcionar explicaciones detalladas
- 🔄 Mantener conversaciones contextuales

## 🚀 Inicio Rápido

### Opción 1: Desarrollo Local (Recomendado para empezar)
```bash
# Clonar el repositorio
git clone <URL_DEL_REPOSITORIO>
cd math-tutor-aifoundry

# Configurar y ejecutar
python setup-and-verify.py
./run-local.sh  # En Windows: run-local.bat
```

### Opción 2: Despliegue Completo en Azure
```bash
azd auth login
azd init -e tutormates
azd provision
azd deploy
```

## 💻 Desarrollo Local

El proyecto está optimizado para desarrollo local con recursos mínimos de Azure. Solo necesitas crear un AI Hub y Storage Account, mientras ejecutas el backend y frontend localmente.

### 📋 Prerrequisitos

#### Software Requerido
- **Python 3.12+** - [Descargar](https://www.python.org/downloads/)
- **Azure CLI** - [Instalar](https://docs.microsoft.com/cli/azure/install)
- **Git** - [Descargar](https://git-scm.com/downloads)

#### Software Opcional
- **Docker Desktop** - Para ejecución con contenedores
- **Make** - Para usar comandos simplificados
- **Azure Developer CLI (azd)** - Para provisioning automatizado

### 🔧 Configuración del Entorno Local

#### Paso 1: Provisionar Recursos Azure Mínimos

Necesitas crear solo estos recursos en Azure:
- AI Hub y Project
- Storage Account
- Key Vault (requerido por AI Hub)

**Opción A: Usando Azure Developer CLI (Recomendado)**
```bash
# Autenticarse en Azure
az login

# Provisionar recursos mínimos para desarrollo local
# Windows PowerShell
.\deploy-local-dev.ps1

# Linux/Mac
./deploy-local-dev.sh
```

**Opción B: Creación Manual en Azure Portal**
1. Crear un AI Hub en [Azure AI Foundry](https://ai.azure.com)
2. Crear un Storage Account
3. Anotar las credenciales en `.env`

#### Paso 2: Configurar Variables de Entorno

1. Copiar el template:
```bash
cp .env.template .env
```

2. Editar `.env` con tus valores:
```env
# Azure AI Foundry
PROJECT_ENDPOINT=https://tu-proyecto.services.ai.azure.com/api/projects/tu-proyecto
MODEL_DEPLOYMENT_NAME=gpt-4o
AGENT_NAME=math-tutor-agent

# Azure Storage
STORAGE_ACCOUNT_NAME=tu-storage-account
IMAGES_CONTAINER_NAME=images

# URLs locales
BACKEND_URI=http://localhost:8000
FRONTEND_URI=http://localhost:7860
```

#### Paso 3: Verificar y Preparar el Entorno

```bash
# Este script verifica prerrequisitos, crea venvs e instala dependencias
python setup-and-verify.py
```

El script automáticamente:
- ✅ Verifica prerrequisitos (Python, Azure CLI, etc.)
- ✅ Verifica autenticación con Azure
- ✅ Crea entornos virtuales para backend y frontend
- ✅ Instala todas las dependencias
- ✅ Verifica el archivo `.env`
- ✅ Comprueba que los scripts de ejecución existen

### 🏃 Ejecutar la Aplicación Localmente

#### Método 1: Script Todo-en-Uno (Recomendado)
```bash
# Linux/Mac
./run-local.sh

# Windows
run-local.bat

# Con Make
make run-local
```

#### Método 2: Con Docker
```bash
docker-compose up
```

#### Método 3: Servicios por Separado
```bash
# Terminal 1 - Backend
cd backend
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python main.py

# Terminal 2 - Frontend
cd frontend
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python app.py
```

### 📍 URLs de Acceso

Una vez ejecutando:
- **Frontend (UI)**: http://localhost:7860
- **Backend API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health

### 🧪 Testing

```bash
# Ejecutar todos los tests
make test

# Test del backend
python tests/test_backend.py

# Test de integración
python tests/test_integration.py

# Test manual de la API
python test-api.py
```

### 📝 Comandos Útiles con Make

```bash
make help              # Ver todos los comandos disponibles
make setup            # Configuración inicial completa
make run-local        # Ejecutar backend y frontend
make run-backend      # Solo backend
make run-frontend     # Solo frontend
make test            # Ejecutar tests
make clean           # Limpiar archivos temporales
make health-check    # Verificar estado de servicios
make logs-backend    # Ver logs del backend
```

### 🔍 Debugging y Troubleshooting

#### Problemas Comunes y Soluciones

**1. Error de Autenticación con Azure**
```bash
# Verificar autenticación
az account show

# Re-autenticar
az logout
az login
```

**2. Backend no responde**
```bash
# Verificar logs
tail -f backend/backend.log

# Verificar health
curl http://localhost:8000/health
```

**3. Agente no se crea**
```bash
# Limpiar agente (solo en desarrollo)
curl -X DELETE http://localhost:8000/cleanup_agent

# Verificar variables en .env
cat .env | grep PROJECT_ENDPOINT
```

**4. Error en dependencias**
```bash
# Recrear entornos virtuales
rm -rf backend/.venv frontend/.venv
python setup-and-verify.py
```

## ☁️ Despliegue en Azure

Para un despliegue completo de producción en Azure con todos los servicios:

### 📋 Prerrequisitos para Producción

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- Suscripción de Azure con cuota suficiente

### 📦 Pasos de Despliegue Completo

#### Paso 1: Configuración Inicial
```bash
# Clonar repositorio
git clone <URL_DEL_REPOSITORIO>
cd math-tutor-aifoundry

# Autenticación
azd auth login
```

#### Paso 2: Aprovisionar Infraestructura
```bash
# Inicializar entorno
azd init -e production

# Configurar región
azd env set AZURE_LOCATION swedencentral

# Provisionar recursos (~15-20 minutos)
azd provision
```

#### Paso 3: Configurar Permisos (Container App)
```powershell
# Ejecutar el script de fix
.\fix-deployment.ps1

# O manualmente con los comandos del README original
```

#### Paso 4: Desplegar Aplicación
```bash
azd deploy
```

### 🧹 Limpieza de Recursos
```bash
# Eliminar todos los recursos
azd down

# O eliminar resource group manualmente
az group delete --name rg-aifoundry-tutor --yes
```

## 🏗️ Arquitectura

### Arquitectura de Desarrollo Local
```
┌─────────────────┐     ┌─────────────────┐
│   Frontend      │────▶│    Backend      │
│   (Gradio)      │     │   (FastAPI)     │
│  localhost:7860 │     │  localhost:8000 │
└─────────────────┘     └────────┬────────┘
                                  │
                        ┌─────────▼────────┐
                        │   Azure Cloud    │
                        ├──────────────────┤
                        │  • AI Project    │
                        │  • Storage       │
                        └──────────────────┘
```

### Arquitectura de Producción
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   App Service   │────▶│  Container App  │────▶│   AI Project    │
│   (Frontend)    │     │    (Backend)    │     │    & Agent      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                        │                       │
         └────────────────────────┴───────────────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │    Servicios Azure         │
                    ├─────────────────────────────┤
                    │  • Container Registry      │
                    │  • Storage Account         │
                    │  • Key Vault               │
                    │  • Application Insights    │
                    └─────────────────────────────┘
```

## 📁 Estructura del Proyecto

```
math-tutor-aifoundry/
├── backend/                 # API Backend (FastAPI)
│   ├── main.py             # Punto de entrada del backend
│   ├── auth_config.py      # Configuración de autenticación Azure
│   ├── requirements.txt    # Dependencias Python
│   └── Dockerfile          # Imagen para producción
├── frontend/               # UI Frontend (Gradio)
│   ├── app.py             # Aplicación Gradio
│   ├── requirements.txt   # Dependencias Python
│   └── Dockerfile         # Imagen para producción
├── infra/                  # Infraestructura como Código
│   ├── main.bicep         # Infraestructura producción
│   ├── main-local.bicep   # Infraestructura desarrollo
│   ├── modules/           # Módulos Bicep producción
│   └── modules-local/     # Módulos Bicep desarrollo
├── tests/                  # Suite de tests
│   ├── test_backend.py    # Tests del backend
│   ├── test_frontend.py   # Tests del frontend
│   └── test_integration.py # Tests de integración
├── .env.template          # Template de variables de entorno
├── docker-compose.yml     # Configuración Docker local
├── Makefile              # Comandos de automatización
├── setup-and-verify.py   # Script de setup automático
├── run-local.sh          # Ejecutar en Linux/Mac
├── run-local.bat         # Ejecutar en Windows
└── azure.yaml            # Configuración Azure Developer CLI
```

## 🛠️ Stack Tecnológico

### Core
- **Python 3.12** - Lenguaje principal
- **FastAPI** - Framework del backend
- **Gradio** - Framework del frontend
- **Azure AI Foundry** - Agente de IA

### Azure Services
- **AI Hub & Project** - Gestión de agentes
- **Container Apps** - Backend en producción
- **App Service** - Frontend en producción
- **Storage Account** - Almacenamiento de imágenes
- **Key Vault** - Gestión de secretos
- **Application Insights** - Monitorización

### Herramientas de Desarrollo
- **Docker** - Contenerización
- **Azure CLI** - Gestión de Azure
- **Azure Developer CLI** - Automatización de despliegues
- **Make** - Automatización de tareas

## ❓ FAQ

### ¿Cuál es la diferencia entre desarrollo local y producción?

**Desarrollo Local:**
- Solo crea AI Hub y Storage en Azure
- Backend y Frontend corren en tu máquina
- Ideal para desarrollo y pruebas
- Costo mínimo de Azure

**Producción:**
- Todos los servicios en Azure
- Alta disponibilidad y escalabilidad
- Monitorización completa
- Mayor costo pero producción-ready

### ¿Cómo cambio el modelo de IA?

Edita `MODEL_DEPLOYMENT_NAME` en `.env`:
```env
MODEL_DEPLOYMENT_NAME=gpt-4o  # Opciones: gpt-4o, gpt-4-turbo, gpt-35-turbo
```

### ¿Puedo usar esto sin Azure?

No, el proyecto requiere al menos:
- Azure AI Foundry para el agente
- Azure Storage para las imágenes generadas

### ¿Cómo agrego nuevas capacidades al tutor?

Modifica las instrucciones del agente en `backend/main.py`:
```python
agent = project_client.agents.create_agent(
    model=model_deployment_name,
    name=AGENT_NAME,
    instructions="Tus instrucciones personalizadas aquí...",
    tools=code_interpreter.definitions
)
```

## 🤝 Contribución

Las contribuciones son bienvenidas. Ver [CONTRIBUTING.md](CONTRIBUTING.md) para detalles.

### Guía Rápida
1. Fork del repositorio
2. Crea tu feature branch (`git checkout -b feature/NuevaCaracteristica`)
3. Commit tus cambios (`git commit -m 'Add: Nueva característica'`)
4. Push al branch (`git push origin feature/NuevaCaracteristica`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver [LICENSE](LICENSE) para más detalles.

## 🆘 Soporte

¿Necesitas ayuda?

- 📖 [Wiki del Proyecto](../../wiki)
- 🐛 [Reportar un Bug](../../issues/new?template=bug_report.md)
- 💡 [Solicitar Feature](../../issues/new?template=feature_request.md)
- 💬 [Discusiones](../../discussions)
- 📧 Email: soporte@tudominio.com

## 🙏 Agradecimientos

- Azure AI Foundry Team
- FastAPI Community
- Gradio Team
- Todos los contribuidores

---

<div align="center">
  <sub>Desarrollado con ❤️ por el equipo MS Data</sub>
  <br>
  <sub>© 2025 - Licencia MIT</sub>
</div>