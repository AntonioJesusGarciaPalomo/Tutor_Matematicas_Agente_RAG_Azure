# 🎓 Tutor de Matemáticas con AI Foundry Agent Service

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=flat&logo=azure-devops&logoColor=white)](https://azure.microsoft.com)
[![Python](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=flat&logo=fastapi)](https://fastapi.tiangolo.com)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com)

[🚀 Despliegue Rápido](#-despliegue) | [📖 Documentación](#-arquitectura) | [🤝 Contribuir](#-contribución) | [❓ FAQ](#-faq)

---

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

Este proyecto utiliza un enfoque de despliegue en dos fases: primero se aprovisiona la infraestructura con `azd` y luego se configuran manualmente los permisos necesarios para la Container App antes del despliegue final del código.

### 📋 Prerrequisitos

- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) - Para gestionar el despliegue
- [Git](https://git-scm.com/downloads) - Para control de versiones
- [Docker Desktop](https://www.docker.com/products/docker-desktop) - Para construcción de contenedores
- Suscripción de Azure activa

### 📦 Pasos para el Despliegue

#### **Paso 1: Clonar y Configurar el Entorno**

1.  **Clonar el Repositorio**
    ```powershell
    git clone <URL_DEL_REPOSITORIO>
    cd <NOMBRE_DEL_REPOSITORIO>
    ```

2.  **Autenticación en Azure**
    ```powershell
    # Esto abrirá tu navegador para autenticación
    azd auth login
    ```

3.  **Configuración del Entorno**
    ```powershell
    # Inicializar el entorno de azd
    azd init -e tutormates

    # Configurar la región de Azure
    azd env set AZURE_LOCATION swedencentral
    ```

#### **Paso 2: Aprovisionar la Infraestructura**

Este comando creará todos los recursos de Azure definidos en los ficheros Bicep.
> ⚠️ El aprovisionamiento puede tardar ~15-20 minutos en completarse.

```powershell
azd provision
```
Al finalizar, la terminal te mostrará un resumen de los recursos creados. Anota los nombres del Container Registry (ACR) y de la Container App para el siguiente paso.

#### **Paso 3: Configurar Permisos Manualmente** 🪄
Ahora, asignaremos los permisos necesarios para que la Container App pueda descargar su imagen desde el ACR. Copia el siguiente bloque de comandos, actualiza las 3 primeras variables con tus valores y ejecútalo en PowerShell.

```PowerShell
# --- CONFIGURA ESTAS 3 VARIABLES ---
$RESOURCE_GROUP = "rg-aifoundry-tutor"
$ACR_NAME = "pega_tu_nombre_de_acr_aqui"         # Ejemplo: acrg622n4pxv3as2
$CONTAINER_APP_NAME = "pega_tu_nombre_de_app_aqui" # Ejemplo: ca-backend-6ki6ilazt4y2o

# 1. Asegurar que la Identidad Gestionada está activa en la Container App
Write-Host "Asignando identidad a la Container App..."
az containerapp identity assign --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --system-assigned

# 2. Obtener el ID de la Identidad Gestionada (Principal ID)
Write-Host "Obteniendo Principal ID..."
$PRINCIPAL_ID = $(az containerapp identity show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# 3. Obtener el ID del Recurso del ACR
Write-Host "Obteniendo ID del ACR..."
$ACR_ID = $(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)

# 4. Asignar el rol 'AcrPull' a la identidad de la App en el ámbito del ACR
Write-Host "Asignando rol 'AcrPull'..."
az role assignment create --assignee $PRINCIPAL_ID --role AcrPull --scope $ACR_ID

# 5. (EL PASO CLAVE) Configurar la Container App para que USE su identidad al conectar con el ACR
Write-Host "Configurando el registro en la Container App..."
az containerapp registry set --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --server "$($ACR_NAME).azurecr.io" --identity system

Write-Host "✅ ¡Permisos y configuración aplicados correctamente!"
```

#### **Paso 4: Desplegar la Aplicación**

Con la infraestructura y los permisos listos, el último paso es desplegar el código de tus aplicaciones.

```PowerShell
azd deploy
```

Al finalizar, recibirás la URL del frontend (FRONTEND_URI) para acceder a tu Tutor de Matemáticas.

### 🧹 Limpieza de Recursos
Para evitar costes innecesarios, puedes eliminar todos los recursos:

```PowerShell
azd down
```

## ❓ FAQ

### ¿Cómo funciona el tutor matemático?
El tutor utiliza Azure AI Foundry Agent Service para procesar las preguntas y generar respuestas contextuales. Puede entender y resolver problemas matemáticos, generar visualizaciones y mantener un diálogo natural.

### ¿Qué tipos de problemas puede resolver?
- Álgebra básica y avanzada
- Cálculo diferencial e integral
- Estadística y probabilidad
- Geometría
- Visualización de funciones matemáticas

### ¿Puedo usar el tutor sin conexión?
No, el tutor requiere conexión a internet ya que utiliza servicios de Azure para procesar las consultas.

## 📝 Contribución

Las contribuciones son bienvenidas. Sigue estos pasos:

1. Fork del repositorio
2. Crea tu rama de feature
   ```bash
   git checkout -b feature/NuevaCaracteristica
   ```
3. Commit tus cambios
   ```bash
   git commit -m 'Añade alguna característica'
   ```
4. Push a tu rama
   ```bash
   git push origin feature/NuevaCaracteristica
   ```
5. Abre un Pull Request

### Guía de Estilo �
- Sigue PEP 8 para código Python
- Documenta las nuevas funciones y clases
- Añade pruebas unitarias para nuevas características
- Mantén el estilo de código existente

## �📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## 🤝 Soporte

¿Necesitas ayuda? Tenemos varias opciones:

- 📖 [Documentación](#-arquitectura)
- 🐛 [Reportar un bug](../../issues)
- 💡 [Proponer nuevas características](../../issues)
- 💬 [Discusiones](../../discussions)

---

<div align="center">
  <sub>Desarrollado con ❤️ por el equipo MS Data</sub>
</div>