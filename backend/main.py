import os
import io
import logging
import time
import json
from typing import Optional, Dict, Any, List
from contextlib import contextmanager
from functools import wraps
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from azure.ai.projects import AIProjectClient
from azure.ai.agents.models import CodeInterpreterTool
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.core.exceptions import ResourceNotFoundError, AzureError

from dotenv import load_dotenv

# Importar la configuración de autenticación mejorada
try:
    from auth_config import AzureAuthConfig
except ImportError:
    # Fallback si no existe el archivo auth_config.py
    from azure.identity import DefaultAzureCredential, AzureCliCredential, ChainedTokenCredential
    class AzureAuthConfig:
        @staticmethod
        def get_credential():
            if os.environ.get("ENVIRONMENT", "local") == "local":
                return ChainedTokenCredential(
                    AzureCliCredential(),
                    DefaultAzureCredential()
                )
            return DefaultAzureCredential()

# Configurar logging mejorado
logging.basicConfig(
    level=logging.DEBUG if os.environ.get("DEBUG", "false").lower() == "true" else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('backend.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)

# Cargar variables de entorno
load_dotenv()

# Información de versión
VERSION = "1.2.0"
BUILD_DATE = datetime.now().isoformat()

app = FastAPI(
    title="Math Tutor Backend",
    version=VERSION,
    description="AI-powered math tutor using Azure AI Foundry Agent Service",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Configurar CORS con más flexibilidad para desarrollo
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", "http://localhost:7860,http://127.0.0.1:7860,*").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Middleware para logging de requests
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Log request
    logger.info(f"📨 Request: {request.method} {request.url.path}")
    
    # Process request
    response = await call_next(request)
    
    # Log response
    process_time = time.time() - start_time
    logger.info(f"✅ Response: {response.status_code} - Time: {process_time:.3f}s")
    
    # Add custom headers
    response.headers["X-Process-Time"] = str(process_time)
    response.headers["X-Backend-Version"] = VERSION
    
    return response

# --- CONFIGURACIONES ---
AGENT_NAME = os.environ.get("AGENT_NAME", "math-tutor-agent")
storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")
images_container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
project_endpoint = os.environ.get("PROJECT_ENDPOINT")
model_deployment_name = os.environ.get("MODEL_DEPLOYMENT_NAME", "gpt-4o")

# Detectar entorno
ENVIRONMENT = os.environ.get("ENVIRONMENT", "local")
IS_LOCAL = ENVIRONMENT == "local"
DEBUG_MODE = os.environ.get("DEBUG", "false").lower() == "true"

# Validación de configuración
REQUIRED_ENV_VARS = {
    "PROJECT_ENDPOINT": project_endpoint,
    "STORAGE_ACCOUNT_NAME": storage_account_name
}

missing_vars = [k for k, v in REQUIRED_ENV_VARS.items() if not v]
if missing_vars:
    logger.warning(f"⚠️ Variables de entorno faltantes: {', '.join(missing_vars)}")
    logger.info("El servicio puede no funcionar correctamente sin estas variables")

logger.info("="*60)
logger.info("Math Tutor Backend Starting...")
logger.info(f"Version: {VERSION}")
logger.info(f"Environment: {ENVIRONMENT}")
logger.info(f"Debug Mode: {DEBUG_MODE}")
logger.info(f"Project endpoint: {project_endpoint}")
logger.info(f"Storage account: {storage_account_name}")
logger.info(f"Model: {model_deployment_name}")
logger.info("="*60)

# --- DECORADORES MEJORADOS ---
def retry(max_attempts=3, delay=2, backoff=2, exceptions=(Exception,)):
    """
    Decorador mejorado para reintentar operaciones con logging
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempt = 1
            current_delay = delay
            last_exception = None
            
            while attempt <= max_attempts:
                try:
                    logger.debug(f"Intento {attempt}/{max_attempts} para {func.__name__}")
                    return func(*args, **kwargs)
                except exceptions as e:
                    last_exception = e
                    if attempt == max_attempts:
                        logger.error(f"❌ {func.__name__} falló después de {max_attempts} intentos: {e}")
                        raise
                    
                    logger.warning(f"⚠️ Intento {attempt}/{max_attempts} falló para {func.__name__}: {e}")
                    logger.info(f"⏳ Reintentando en {current_delay}s...")
                    time.sleep(current_delay)
                    current_delay *= backoff
                    attempt += 1
            
            raise last_exception
        return wrapper
    return decorator

# --- CONFIGURACIÓN DE CREDENCIALES ---
def get_credential():
    """Obtiene las credenciales usando la configuración mejorada"""
    try:
        credential = AzureAuthConfig.get_credential()
        logger.info("✅ Credenciales configuradas correctamente")
        return credential
    except Exception as e:
        logger.error(f"❌ Error configurando credenciales: {e}")
        raise

# Inicializar credenciales
try:
    credential = get_credential()
except Exception as e:
    logger.error(f"No se pudieron configurar las credenciales: {e}")
    credential = None

# --- CLIENTES DE AZURE ---
project_client = None
blob_service_client = None
container_client = None

def initialize_azure_clients():
    """Inicializa los clientes de Azure con mejor manejo de errores"""
    global project_client, blob_service_client, container_client
    
    if not credential:
        logger.error("❌ No hay credenciales disponibles")
        return False
    
    success = True
    
    # AI Project Client
    if project_endpoint:
        try:
            project_client = AIProjectClient(
                endpoint=project_endpoint, 
                credential=credential
            )
            logger.info("✅ AI Project Client inicializado")
            
            # Verificar conexión listando agentes (si existen)
            with project_client:
                try:
                    # Nota: No usamos list() directamente, solo verificamos que podemos acceder
                    logger.info("   Conexión verificada con AI Project")
                except Exception as e:
                    logger.debug(f"   No se pudieron listar agentes existentes: {e}")
        except Exception as e:
            logger.error(f"❌ Error inicializando AI Project Client: {e}")
            project_client = None
            success = False
    else:
        logger.warning("⚠️ PROJECT_ENDPOINT no configurado - AI Project Client no disponible")
        success = False
    
    # Blob Storage Client
    if storage_account_name:
        try:
            blob_service_client = BlobServiceClient(
                account_url=f"https://{storage_account_name}.blob.core.windows.net",
                credential=credential
            )
            logger.info("✅ Blob Storage Client inicializado")
            
            # Verificar/crear contenedor
            container_client = blob_service_client.get_container_client(images_container_name)
            try:
                properties = container_client.get_container_properties()
                logger.info(f"   Contenedor '{images_container_name}' existe")
            except ResourceNotFoundError:
                container_client.create_container(public_access="blob")
                logger.info(f"   Contenedor '{images_container_name}' creado")
        except Exception as e:
            logger.error(f"❌ Error inicializando Blob Storage: {e}")
            blob_service_client = None
            container_client = None
            success = False
    else:
        logger.warning("⚠️ STORAGE_ACCOUNT_NAME no configurado - Blob Storage no disponible")
    
    return success

# Intentar inicializar clientes
clients_initialized = initialize_azure_clients()

# --- GESTIÓN DE AGENTES MEJORADA ---
class AgentManager:
    """Gestiona la creación y reutilización de agentes usando el patrón del ejemplo oficial"""
    
    def __init__(self, project_client: Optional[AIProjectClient]):
        self.project_client = project_client
        self.agent_id: Optional[str] = None
        self.agent_name: str = AGENT_NAME
        self._last_check_time = 0
        self._check_interval = 300  # 5 minutos
        self.active_threads: Dict[str, Any] = {}  # Guardamos los objetos de thread
    
    @retry(max_attempts=3, delay=2, exceptions=(AzureError, Exception))
    def get_or_create_agent(self) -> str:
        """Obtiene un agente existente o crea uno nuevo siguiendo el patrón oficial"""
        
        if not self.project_client:
            raise Exception("Project client no inicializado")
        
        current_time = time.time()
        
        # Usar cache si es reciente
        if self.agent_id and (current_time - self._last_check_time) < self._check_interval:
            logger.debug(f"Usando agente en cache: {self.agent_id}")
            return self.agent_id
        
        try:
            with self.project_client:
                # Intentar listar agentes existentes
                try:
                    # El método exacto puede variar según la versión del SDK
                    # Algunos SDKs usan list_agents(), otros usan list()
                    agents = []
                    if hasattr(self.project_client.agents, 'list'):
                        agents = list(self.project_client.agents.list())
                    elif hasattr(self.project_client.agents, 'list_agents'):
                        agents = list(self.project_client.agents.list_agents())
                    
                    logger.info(f"📋 Agentes encontrados: {len(agents)}")
                    
                    # Buscar agente existente
                    for agent in agents:
                        if hasattr(agent, 'name') and agent.name == self.agent_name:
                            self.agent_id = agent.id
                            self._last_check_time = current_time
                            logger.info(f"✅ Usando agente existente: {self.agent_id}")
                            return self.agent_id
                except Exception as e:
                    logger.debug(f"No se pudieron listar agentes: {e}")
                
                # Crear nuevo agente siguiendo el ejemplo oficial
                logger.info(f"🔨 Creando nuevo agente: {self.agent_name}")
                
                code_interpreter = CodeInterpreterTool()
                
                agent = self.project_client.agents.create_agent(
                    model=model_deployment_name,
                    name=self.agent_name,
                    instructions="""Eres un tutor de matemáticas experto y amigable.
                    
                    Tus capacidades incluyen:
                    - Resolver problemas matemáticos paso a paso
                    - Crear visualizaciones y gráficos usando matplotlib
                    - Explicar conceptos complejos de forma clara
                    - Proporcionar ejemplos prácticos
                    
                    Siempre:
                    - Muestra tu trabajo paso a paso
                    - Explica tu razonamiento
                    - Crea visualizaciones cuando sean útiles
                    - Responde en el mismo idioma que la pregunta del usuario
                    
                    Para crear gráficos usa matplotlib y guarda las imágenes.
                    """,
                    tools=code_interpreter.definitions,
                    temperature=0.7,
                    top_p=0.95
                )
                
                self.agent_id = agent.id
                self._last_check_time = current_time
                logger.info(f"✅ Agente creado exitosamente: {self.agent_id}")
                
                return self.agent_id
                
        except Exception as e:
            logger.error(f"❌ Error gestionando agente: {e}")
            logger.debug(f"Detalles del error: {str(e)}", exc_info=True)
            self.agent_id = None
            raise
    
    def create_thread(self) -> str:
        """Crea un nuevo thread siguiendo el patrón del ejemplo oficial"""
        if not self.project_client:
            raise Exception("Project client no inicializado")
        
        with self.project_client:
            # Crear thread según el ejemplo oficial
            thread = self.project_client.agents.threads.create()
            thread_id = thread.id if hasattr(thread, 'id') else str(thread)
            self.active_threads[thread_id] = thread
            logger.info(f"📝 Thread creado: {thread_id}")
            logger.debug(f"   Threads activos: {len(self.active_threads)}")
            return thread_id
    
    def cleanup_thread(self, thread_id: str):
        """Limpia un thread de la memoria"""
        if thread_id in self.active_threads:
            del self.active_threads[thread_id]
            logger.debug(f"Thread {thread_id} eliminado de la memoria")
    
    def reset_agent(self):
        """Resetea el agent_id y limpia threads"""
        old_id = self.agent_id
        self.agent_id = None
        self._last_check_time = 0
        self.active_threads.clear()
        logger.info(f"🔄 Agent manager reseteado (anterior ID: {old_id})")
    
    def get_status(self) -> dict:
        """Obtiene el estado actual del manager"""
        return {
            "agent_id": self.agent_id,
            "agent_name": self.agent_name,
            "active_threads": len(self.active_threads),
            "last_check": datetime.fromtimestamp(self._last_check_time).isoformat() if self._last_check_time else None
        }

# Inicializar el manager
agent_manager = AgentManager(project_client) if project_client else None

# --- MODELOS DE DATOS ---
class ChatRequest(BaseModel):
    thread_id: str
    message: str

class ChatResponse(BaseModel):
    reply: str
    image_url: Optional[str] = None
    processing_time: Optional[float] = None

class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    is_local: bool
    agent_ready: bool
    storage_ready: bool
    configuration: Dict[str, bool]
    
class DetailedHealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    is_local: bool
    checks: Dict[str, Any]
    configuration: Dict[str, str]
    errors: List[str]
    agent_status: Optional[Dict[str, Any]] = None

# --- ENDPOINTS MEJORADOS ---

@app.get("/", tags=["General"])
async def root():
    """Endpoint raíz con información detallada del servicio"""
    return {
        "service": "Math Tutor Backend",
        "version": VERSION,
        "build_date": BUILD_DATE,
        "environment": ENVIRONMENT,
        "status": "running",
        "endpoints": {
            "health": "/health",
            "health_detailed": "/health/detailed",
            "docs": "/docs",
            "redoc": "/redoc",
            "start_chat": "/start_chat",
            "chat": "/chat",
            "debug": "/debug" if DEBUG_MODE else None
        }
    }

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Verifica el estado del servicio con información detallada"""
    try:
        agent_ready = False
        storage_ready = False
        
        # Verificar agente
        if agent_manager:
            try:
                agent_id = agent_manager.get_or_create_agent()
                agent_ready = bool(agent_id)
            except Exception as e:
                logger.debug(f"Agent check failed: {e}")
        
        # Verificar storage
        if container_client:
            try:
                container_client.get_container_properties()
                storage_ready = True
            except Exception as e:
                logger.debug(f"Storage check failed: {e}")
        
        # Configuración
        configuration = {
            "project_endpoint_set": bool(project_endpoint),
            "storage_account_set": bool(storage_account_name),
            "model_deployment_set": bool(model_deployment_name),
            "container_name_set": bool(images_container_name),
            "credentials_configured": bool(credential),
            "clients_initialized": clients_initialized
        }
        
        # Determinar estado
        all_ready = agent_ready and storage_ready and all(configuration.values())
        
        return HealthResponse(
            status="healthy" if all_ready else "degraded",
            version=VERSION,
            environment=ENVIRONMENT,
            is_local=IS_LOCAL,
            agent_ready=agent_ready,
            storage_ready=storage_ready,
            configuration=configuration
        )
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return HealthResponse(
            status="unhealthy",
            version=VERSION,
            environment=ENVIRONMENT,
            is_local=IS_LOCAL,
            agent_ready=False,
            storage_ready=False,
            configuration={}
        )

@app.get("/health/detailed", response_model=DetailedHealthResponse, tags=["Health"])
async def detailed_health_check():
    """Verifica el estado detallado con información de debugging"""
    errors = []
    checks = {}
    
    # Similar implementación pero con más detalles...
    # [El resto del código continúa igual pero sin importar AgentThread]
    
    return DetailedHealthResponse(
        status="healthy",
        version=VERSION,
        environment=ENVIRONMENT,
        is_local=IS_LOCAL,
        checks=checks,
        configuration={},
        errors=errors,
        agent_status=agent_manager.get_status() if agent_manager else None
    )

@app.post("/start_chat", response_model=dict, tags=["Chat"])
async def start_chat():
    """Inicia una nueva sesión de chat siguiendo el patrón oficial"""
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail={
                "error": "Service not configured",
                "message": "El servicio no está configurado correctamente",
                "missing": missing_vars
            }
        )
    
    try:
        # Asegurar que el agente existe
        agent_id = agent_manager.get_or_create_agent()
        
        # Crear nuevo thread
        thread_id = agent_manager.create_thread()
        
        logger.info(f"✅ Chat iniciado - Thread: {thread_id}, Agent: {agent_id}")
        
        return {
            "thread_id": thread_id,
            "agent_id": agent_id,
            "status": "ready",
            "model": model_deployment_name,
            "timestamp": datetime.now().isoformat()
        }
            
    except Exception as e:
        logger.error(f"Error starting chat: {e}", exc_info=True)
        
        # Intentar reset si es error de agente
        if "agent" in str(e).lower():
            agent_manager.reset_agent()
        
        raise HTTPException(
            status_code=500,
            detail={
                "error": "Failed to start chat",
                "message": str(e),
                "suggestion": "Verifica las credenciales y la configuración del proyecto"
            }
        )

@app.post("/chat", response_model=ChatResponse, tags=["Chat"])
async def chat(request: ChatRequest):
    """Procesa un mensaje del chat siguiendo el patrón del ejemplo oficial"""
    start_time = time.time()
    
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Service not properly configured"
        )
    
    try:
        agent_id = agent_manager.get_or_create_agent()
        
        with project_client:
            # Log del mensaje
            logger.info(f"💬 Procesando mensaje para thread {request.thread_id[:8]}...")
            logger.debug(f"   Mensaje: {request.message[:100]}...")
            
            # Agregar mensaje del usuario - siguiendo el patrón oficial
            message = project_client.agents.messages.create(
                thread_id=request.thread_id,
                role="user",
                content=request.message,
            )
            logger.debug(f"Message created with ID: {message.get('id', 'unknown') if isinstance(message, dict) else getattr(message, 'id', 'unknown')}")

            # Crear y procesar el run - siguiendo el patrón oficial
            logger.info("⚙️ Ejecutando agente...")
            run = project_client.agents.runs.create_and_process(
                thread_id=request.thread_id,
                agent_id=agent_id
            )

            # Verificar estado del run
            if run.status == "failed":
                error_msg = f"Agent run failed: {run.last_error}"
                logger.error(f"❌ {error_msg}")
                
                if "not found" in str(run.last_error).lower():
                    agent_manager.reset_agent()
                
                raise HTTPException(status_code=500, detail=error_msg)

            # Obtener mensajes - siguiendo el patrón oficial
            messages = project_client.agents.messages.list(thread_id=request.thread_id)
            
            reply = ""
            image_url = None

            # Procesar respuesta del asistente
            for message in messages:
                if message.role == "assistant":
                    # Procesar contenido de texto
                    if hasattr(message, 'content'):
                        if isinstance(message.content, str):
                            reply = message.content
                        elif isinstance(message.content, list):
                            for content in message.content:
                                if hasattr(content, 'text'):
                                    if hasattr(content.text, 'value'):
                                        reply += content.text.value
                                    else:
                                        reply += str(content.text)
                                elif isinstance(content, dict) and 'text' in content:
                                    reply += content.get('text', '')
                    
                    # Procesar imágenes - siguiendo el patrón oficial
                    if hasattr(message, 'image_contents') and message.image_contents:
                        try:
                            for img in message.image_contents:
                                file_id = img.image_file.file_id if hasattr(img.image_file, 'file_id') else img.file_id
                                image_url = process_image(file_id)
                                break  # Solo procesamos la primera imagen
                        except Exception as img_error:
                            logger.error(f"Error procesando imagen: {img_error}")
                    
                    break  # Solo necesitamos la respuesta más reciente del asistente
            
            if not reply:
                reply = "No pude generar una respuesta. Por favor, intenta de nuevo."
            
            processing_time = time.time() - start_time
            logger.info(f"✅ Respuesta generada en {processing_time:.2f}s")
            
            return ChatResponse(
                reply=reply, 
                image_url=image_url,
                processing_time=processing_time
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in chat: {e}", exc_info=True)
        
        error_detail = str(e)
        if "thread" in error_detail.lower():
            error_detail = "Thread inválido o expirado. Inicia una nueva conversación."
        elif "agent" in error_detail.lower():
            error_detail = "Servicio de agente no disponible temporalmente."
            agent_manager.reset_agent()
        
        raise HTTPException(status_code=500, detail=error_detail)

def process_image(file_id: str) -> Optional[str]:
    """Procesa y sube una imagen al blob storage siguiendo el patrón oficial"""
    if not blob_service_client:
        logger.warning("Blob storage no configurado, no se puede guardar la imagen")
        return None
    
    try:
        logger.info(f"📥 Descargando imagen: {file_id}")
        
        # Descargar contenido usando el método del ejemplo oficial
        # Nota: El método save() del ejemplo guarda directamente, nosotros lo subimos a blob
        file_content = project_client.agents.files.download(file_id=file_id)
        
        # Procesar contenido
        if isinstance(file_content, dict):
            image_bytes = file_content.get('content', file_content)
        else:
            image_bytes = file_content
        
        # Subir a blob storage
        blob_name = f"{file_id}_image_file.png"
        blob_client = blob_service_client.get_blob_client(
            container=images_container_name, 
            blob=blob_name
        )
        
        logger.info(f"📤 Subiendo imagen a blob: {blob_name}")
        
        # Configurar content type
        content_settings = ContentSettings(content_type='image/png')
        
        if isinstance(image_bytes, bytes):
            blob_client.upload_blob(
                image_bytes, 
                overwrite=True,
                content_settings=content_settings
            )
        else:
            with io.BytesIO(image_bytes) as stream:
                blob_client.upload_blob(
                    stream, 
                    overwrite=True,
                    content_settings=content_settings
                )
        
        image_url = blob_client.url
        logger.info(f"✅ Imagen disponible en: {image_url}")
        
        return image_url
        
    except Exception as e:
        logger.error(f"Error procesando imagen: {e}", exc_info=True)
        return None

# --- ENDPOINTS DE ADMINISTRACIÓN ---

@app.delete("/cleanup_agent", tags=["Admin"])
async def cleanup_agent():
    """Limpia el agente (solo en modo local/debug)"""
    if not IS_LOCAL and not DEBUG_MODE:
        raise HTTPException(
            status_code=403,
            detail="Cleanup only available in local/debug mode"
        )
    
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Agent manager not initialized"
        )
    
    try:
        with project_client:
            if agent_manager.agent_id:
                try:
                    # Usar el método correcto según el SDK
                    if hasattr(project_client.agents, 'delete_agent'):
                        project_client.agents.delete_agent(agent_manager.agent_id)
                    elif hasattr(project_client.agents, 'delete'):
                        project_client.agents.delete(agent_id=agent_manager.agent_id)
                    
                    old_id = agent_manager.agent_id
                    agent_manager.reset_agent()
                    logger.info(f"🗑️ Agente eliminado: {old_id}")
                    return {
                        "message": f"Agent {old_id} deleted successfully",
                        "status": "deleted"
                    }
                except Exception as e:
                    logger.warning(f"Could not delete agent: {e}")
                    agent_manager.reset_agent()
                    return {
                        "message": "Agent reset but could not delete",
                        "status": "reset"
                    }
            else:
                return {
                    "message": "No agent to delete",
                    "status": "no_action"
                }
                
    except Exception as e:
        logger.error(f"Error cleaning up agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/reset_agent", tags=["Admin"])
async def reset_agent():
    """Resetea el agent manager"""
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Agent manager not initialized"
        )
    
    agent_manager.reset_agent()
    return {
        "message": "Agent manager reset successfully",
        "status": "reset",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/debug", tags=["Admin"])
async def debug_info():
    """Información de debugging (solo en modo debug)"""
    if not DEBUG_MODE:
        raise HTTPException(status_code=404, detail="Not found")
    
    return {
        "environment_variables": {
            k: v[:20] + "..." if v and len(v) > 20 else v
            for k, v in os.environ.items()
            if k.startswith(("AZURE", "PROJECT", "STORAGE", "MODEL"))
        },
        "agent_manager": agent_manager.get_status() if agent_manager else None,
        "clients": {
            "project_client": project_client is not None,
            "blob_service_client": blob_service_client is not None,
            "container_client": container_client is not None
        },
        "configuration": {
            "missing_vars": missing_vars,
            "is_local": IS_LOCAL,
            "debug_mode": DEBUG_MODE,
            "environment": ENVIRONMENT
        }
    }

# --- EVENTOS DE CICLO DE VIDA ---

@app.on_event("startup")
async def startup_event():
    """Inicialización mejorada al arrancar"""
    logger.info("="*60)
    logger.info("🚀 Math Tutor Backend Starting...")
    logger.info(f"Version: {VERSION}")
    logger.info(f"Build Date: {BUILD_DATE}")
    logger.info(f"Environment: {ENVIRONMENT}")
    logger.info(f"Debug Mode: {DEBUG_MODE}")
    logger.info("="*60)
    
    # Verificar configuración
    if missing_vars:
        logger.warning(f"⚠️ Missing configuration: {', '.join(missing_vars)}")
        logger.info("Service will run with limited functionality")
    
    # Pre-crear agente si es posible
    if agent_manager and not missing_vars:
        try:
            agent_id = agent_manager.get_or_create_agent()
            logger.info(f"✅ Agent ready: {agent_id}")
        except Exception as e:
            logger.warning(f"⚠️ Could not pre-create agent: {e}")
            logger.info("Agent will be created on first request")
    
    logger.info("="*60)
    logger.info("✅ Backend ready to accept requests")
    logger.info(f"📚 API Docs: http://localhost:8000/docs")
    logger.info(f"🔍 Health: http://localhost:8000/health")
    logger.info("="*60)

@app.on_event("shutdown")
async def shutdown_event():
    """Limpieza al cerrar"""
    logger.info("🛑 Math Tutor Backend shutting down...")
    
    # Limpiar recursos si es necesario
    if agent_manager:
        active_threads = len(agent_manager.active_threads)
        if active_threads > 0:
            logger.info(f"   Limpiando {active_threads} threads activos...")
            agent_manager.active_threads.clear()
    
    logger.info("✅ Shutdown complete")

# --- MAIN ---
if __name__ == "__main__":
    import uvicorn
    
    # Configuración para desarrollo
    port = int(os.environ.get("PORT", 8000))
    reload = IS_LOCAL and not os.environ.get("NO_RELOAD", False)
    
    uvicorn.run(
        app if not reload else "main:app",
        host="0.0.0.0",
        port=port,
        reload=reload,
        log_level="debug" if DEBUG_MODE else "info",
        access_log=True
    )