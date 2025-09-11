# 🎓 Tutor de Matemáticas con AI Foundry Agent Service

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=flat&logo=azure-devops&logoColor=white)](https://azure.microsoft.com)
[![Python](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org)

Este proyecto implementa un asistente matemático inteligente utilizando el Azure AI Foundry Agent Service. La solución ofrece un tutor virtual capaz de:

- 📚 Responder preguntas matemáticas de diversos niveles
- 📊 Generar visualizaciones y gráficas usando CodeInterpreterTool
- 🧮 Resolver problemas paso a paso
- 📝 Proporcionar explicaciones detalladas
- 🔄 Mantener conversaciones contextuales

La aplicación está diseñada para ser desplegada de forma totalmente automatizada en Azure mediante la Azure Developer CLI (azd).

## 🏗️ Arquitectura

La solución implementa una arquitectura moderna de microservicios contenerizados, siguiendo las mejores prácticas de desarrollo en la nube:

### 🔙 Backend
- **Tecnología**: API REST con FastAPI (Python)
- **Funcionalidades**:
  - Integración con Azure AI Agent Service
  - Gestión de conversaciones y contexto
  - Almacenamiento de imágenes en Azure Blob Storage
  - Logging y telemetría
- **Despliegue**: Azure Container App

### 🖥️ Frontend
- **Tecnología**: Gradio (Python)
- **Características**:
  - Interfaz de chat intuitiva
  - Soporte para visualización de imágenes y gráficos
  - Experiencia de usuario responsiva
  - Diseño minimalista y funcional
- **Despliegue**: Azure App Service

### ⚙️ Infraestructura como Código (IaC)
- **Tecnología**: Bicep
- **Componentes**:
  - AI Hub y AI Project
  - Container Apps y App Service
  - Storage Account y Key Vault
  - Application Insights
  - Container Registry
- **Características**:
  - Despliegue automatizado
  - Configuración versionada
  - Gestión de secretos segura

## 🛠️ Stack Tecnológico

### 🤖 IA & Agentes
- **Azure AI Foundry Agent Service**
  - Motor de procesamiento de lenguaje natural
  - Gestión de conversaciones contextuales
  - Integración con herramientas personalizadas

### 💻 Desarrollo
- **Backend**
  - Python 3.12
  - FastAPI
  - Azure SDK
- **Frontend**
  - Python 3.12
  - Gradio
  - WebSocket para comunicación en tiempo real

### 🔄 DevOps & Infraestructura
- **Infraestructura**
  - Bicep (IaC)
  - Azure Developer CLI (azd)
  - Docker
  
### ☁️ Servicios de Azure
| Servicio | Propósito |
|----------|-----------|
| AI Hub & Project | Gestión de agentes de IA |
| Container Apps | Ejecución del backend |
| App Service | Hosting del frontend |
| Container Registry | Almacenamiento de imágenes Docker |
| Storage Account | Almacenamiento de recursos generados |
| Key Vault | Gestión segura de secretos |
| Application Insights | Monitorización y telemetría |

## 🚀 Despliegue

Este proyecto utiliza Azure Developer CLI (azd) para automatizar completamente el proceso de despliegue.

### 📋 Prerrequisitos

- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) - Para gestionar el despliegue
- [Git](https://git-scm.com/downloads) - Para control de versiones
- [Docker Desktop](https://www.docker.com/products/docker-desktop) - Para construcción de contenedores
- Suscripción de Azure activa

### 📦 Pasos para el Despliegue

1. **Clonar el Repositorio**
   ```powershell
   git clone <URL_DEL_REPOSITORIO>
   cd <NOMBRE_DEL_REPOSITORIO>
   ```

2. **Autenticación en Azure**
   ```powershell
   # Esto abrirá tu navegador para autenticación
   azd auth login
   ```

3. **Configuración del Entorno**
   ```powershell
   # Inicializar el entorno de azd
   azd init -e tutormates

   # Configurar la región de Azure
   azd env set AZURE_LOCATION swedencentral
   ```

4. **Despliegue de la Aplicación**
   ```powershell
   # Este comando realizará todo el proceso de despliegue
   azd up
   ```
   > ⚠️ El despliegue puede tardar ~15-20 minutos en completarse.

   Al finalizar, recibirás la URL del frontend (FRONTEND_URI) para acceder a tu Tutor de Matemáticas.

### 🧹 Limpieza de Recursos

Para evitar costes innecesarios, puedes eliminar todos los recursos:
```powershell
azd down
```

## 📝 Contribución

Las contribuciones son bienvenidas. Por favor:

1. Haz Fork del repositorio
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## 🤝 Soporte

Si encuentras algún problema o tienes sugerencias, por favor abre un issue en el repositorio.