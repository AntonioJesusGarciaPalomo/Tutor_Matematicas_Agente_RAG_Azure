import os
import io
import logging
import time
from typing import Optional, Dict, Any
from contextlib import contextmanager
from functools import wraps

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from azure.ai.projects import AIProjectClient
from azure.identity import (
    DefaultAzureCredential, 
    InteractiveBrowserCredential,
    ChainedTokenCredential,
    ManagedIdentityCredential,
    AzureCliCredential
)
from azure.ai.agents.models import CodeInterpreterTool
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceNotFoundError, AzureError

from dotenv import load_dotenv

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Cargar variables de entorno
load_dotenv()

app = FastAPI(
    title="Math Tutor Backend",
    version="1.0.0",
    description="AI-powered math tutor using Azure AI Foundry Agent Service"
)

# Agregar CORS para desarrollo local
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:7860", "http://127.0.0.1:7860", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- CONFIGURACIONES ---
AGENT_NAME = "math-tutor-agent"
storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")
images_container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
project_endpoint = os.environ.get("PROJECT_ENDPOINT")
model_deployment_name = os.environ.get("MODEL_DEPLOYMENT_NAME", "gpt-4o")

# Detectar si estamos en local o en Azure
IS_LOCAL = os.environ.get("AZURE_CLIENT_ID") is None

logger.info(f"Running in {'LOCAL' if IS_LOCAL else 'AZURE'} mode")
logger.info(f"Project endpoint: {project_endpoint}")
logger.info(f"Storage account: {storage_account_name}")

# --- DECORADOR PARA RETRY LOGIC ---
def retry(max_attempts=3, delay=2, backoff=2, exceptions=(Exception,)):
    """
    Decorador para reintentar operaciones que pueden fallar
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempt = 1
            current_delay = delay
            
            while attempt <= max_attempts:
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    if attempt == max_attempts:
                        logger.error(f"Failed after {max_attempts} attempts: {e}")
                        raise
                    
                    logger.warning(f"Attempt {attempt}/{max_attempts} failed: {e}. Retrying in {current_delay}s...")
                    time.sleep(current_delay)
                    current_delay *= backoff
                    attempt += 1
            
            return None
        return wrapper
    return decorator

# --- CONFIGURACIÓN DE CREDENCIALES ---
def get_credential():
    """
    Obtiene las credenciales apropiadas según el entorno.
    En local usa InteractiveBrowserCredential o AzureCliCredential.
    En Azure usa ManagedIdentityCredential.
    """
    if IS_LOCAL:
        # Para desarrollo local, intentar primero Azure CLI, luego browser
        credential = ChainedTokenCredential(
            AzureCliCredential(),
            InteractiveBrowserCredential()
        )
        logger.info("Using local development credentials (Azure CLI or Browser)")
    else:
        # En Azure, usar Managed Identity
        credential = ChainedTokenCredential(
            ManagedIdentityCredential(),
            DefaultAzureCredential()
        )
        logger.info("Using Azure Managed Identity credentials")
    
    return credential

# Inicializar credenciales
credential = get_credential()

# --- CLIENTES DE AZURE ---
try:
    # AI Project Client
    project_client = AIProjectClient(
        endpoint=project_endpoint, 
        credential=credential
    )
    logger.info("AI Project Client initialized successfully")
    
    # Blob Storage Client
    blob_service_client = BlobServiceClient(
        account_url=f"https://{storage_account_name}.blob.core.windows.net",
        credential=credential
    )
    logger.info("Blob Storage Client initialized successfully")
    
    # Verificar/crear contenedor de imágenes
    container_client = blob_service_client.get_container_client(images_container_name)
    try:
        container_client.get_container_properties()
        logger.info(f"Container '{images_container_name}' exists")
    except ResourceNotFoundError:
        container_client.create_container(public_access="blob")
        logger.info(f"Container '{images_container_name}' created")
        
except Exception as e:
    logger.error(f"Error initializing Azure clients: {e}")
    # No hacer raise aquí para permitir que el servicio arranque
    # y devuelva errores apropiados en los endpoints

# --- GESTIÓN DE AGENTES ---
class AgentManager:
    """Gestiona la creación y reutilización de agentes"""
    
    def __init__(self, project_client: AIProjectClient):
        self.project_client = project_client
        self.agent_id: Optional[str] = None
        self._last_check_time = 0
        self._check_interval = 300  # Verificar cada 5 minutos
    
    @retry(max_attempts=3, delay=2, exceptions=(AzureError, Exception))
    def get_or_create_agent(self) -> str:
        """Obtiene un agente existente o crea uno nuevo con retry logic"""
        # Si ya tenemos un agent_id y no ha pasado mucho tiempo, usarlo
        current_time = time.time()
        if self.agent_id and (current_time - self._last_check_time) < self._check_interval:
            return self.agent_id
        
        try:
            with self.project_client:
                # Intentar obtener un agente existente
                agents = self.project_client.agents.list()
                for agent in agents:
                    if agent.name == AGENT_NAME:
                        self.agent_id = agent.id
                        self._last_check_time = current_time
                        logger.info(f"Using existing agent: {self.agent_id}")
                        return self.agent_id
                
                # Si no existe, crear uno nuevo
                logger.info("Creating new agent...")
                code_interpreter = CodeInterpreterTool()
                agent = self.project_client.agents.create_agent(
                    model=model_deployment_name,
                    name=AGENT_NAME,
                    instructions="""You are a friendly and expert math tutor. 
                    Use the Code Interpreter tool to:
                    - Solve mathematical problems step by step
                    - Create visualizations and graphs when helpful
                    - Explain complex concepts clearly
                    Always show your work and explain your reasoning.
                    Respond in the same language as the user's question.""",
                    tools=code_interpreter.definitions,
                    temperature=0.7,
                    top_p=0.95
                )
                self.agent_id = agent.id
                self._last_check_time = current_time
                logger.info(f"Created new agent: {self.agent_id}")
                return self.agent_id
                
        except Exception as e:
            logger.error(f"Error managing agent: {e}")
            self.agent_id = None  # Reset para intentar de nuevo
            raise
    
    def reset_agent(self):
        """Resetea el agent_id para forzar una nueva búsqueda/creación"""
        self.agent_id = None
        self._last_check_time = 0
        logger.info("Agent manager reset")

# Inicializar el manager solo si tenemos configuración válida
agent_manager = None
if project_endpoint and storage_account_name:
    try:
        agent_manager = AgentManager(project_client)
    except Exception as e:
        logger.error(f"Could not initialize AgentManager: {e}")

# --- MODELOS DE DATOS ---
class ChatRequest(BaseModel):
    thread_id: str
    message: str

class ChatResponse(BaseModel):
    reply: str
    image_url: Optional[str] = None

class HealthResponse(BaseModel):
    status: str
    is_local: bool
    agent_ready: bool
    storage_ready: bool
    configuration: Dict[str, bool]

class DetailedHealthResponse(BaseModel):
    status: str
    is_local: bool
    checks: Dict[str, Any]
    configuration: Dict[str, str]
    errors: list

# --- ENDPOINTS ---
@app.get("/", tags=["General"])
async def root():
    """Endpoint raíz con información del servicio"""
    return {
        "service": "Math Tutor Backend",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "health_detailed": "/health/detailed",
            "docs": "/docs",
            "start_chat": "/start_chat",
            "chat": "/chat"
        }
    }

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Verifica el estado básico del servicio"""
    try:
        agent_ready = False
        storage_ready = False
        
        # Verificar agente
        if agent_manager:
            try:
                agent_id = agent_manager.get_or_create_agent()
                agent_ready = bool(agent_id)
            except Exception as e:
                logger.warning(f"Agent check failed: {e}")
        
        # Verificar storage
        try:
            container_client.get_container_properties()
            storage_ready = True
        except Exception as e:
            logger.warning(f"Storage check failed: {e}")
        
        # Configuración
        configuration = {
            "project_endpoint_set": bool(project_endpoint),
            "storage_account_set": bool(storage_account_name),
            "model_deployment_set": bool(model_deployment_name),
            "container_name_set": bool(images_container_name)
        }
        
        # Determinar estado general
        all_ready = agent_ready and storage_ready and all(configuration.values())
        
        return HealthResponse(
            status="healthy" if all_ready else "degraded",
            is_local=IS_LOCAL,
            agent_ready=agent_ready,
            storage_ready=storage_ready,
            configuration=configuration
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return HealthResponse(
            status="unhealthy",
            is_local=IS_LOCAL,
            agent_ready=False,
            storage_ready=False,
            configuration={}
        )

@app.get("/health/detailed", response_model=DetailedHealthResponse, tags=["Health"])
async def detailed_health_check():
    """Verifica el estado detallado del servicio con todos los componentes"""
    errors = []
    checks = {}
    
    # Verificar configuración
    configuration = {
        "project_endpoint": project_endpoint or "NOT_SET",
        "storage_account": storage_account_name or "NOT_SET",
        "model_deployment": model_deployment_name or "NOT_SET",
        "container_name": images_container_name or "NOT_SET",
        "environment": "LOCAL" if IS_LOCAL else "AZURE"
    }
    
    # Verificar Project Client
    checks["project_client"] = False
    if project_client and project_endpoint:
        try:
            with project_client:
                # Intentar una operación simple
                _ = list(project_client.agents.list())
                checks["project_client"] = True
        except Exception as e:
            errors.append(f"Project client error: {str(e)}")
    else:
        errors.append("Project client not configured")
    
    # Verificar Storage
    checks["storage_account"] = False
    checks["storage_container"] = False
    if blob_service_client and storage_account_name:
        try:
            # Verificar cuenta
            _ = blob_service_client.get_account_information()
            checks["storage_account"] = True
            
            # Verificar contenedor
            container_client.get_container_properties()
            checks["storage_container"] = True
        except Exception as e:
            errors.append(f"Storage error: {str(e)}")
    else:
        errors.append("Storage not configured")
    
    # Verificar Agent
    checks["agent_available"] = False
    checks["agent_id"] = None
    if agent_manager:
        try:
            agent_id = agent_manager.get_or_create_agent()
            checks["agent_available"] = True
            checks["agent_id"] = agent_id
        except Exception as e:
            errors.append(f"Agent error: {str(e)}")
    else:
        errors.append("Agent manager not initialized")
    
    # Determinar estado general
    all_checks_pass = all(
        v for k, v in checks.items() 
        if k != "agent_id" and isinstance(v, bool)
    )
    
    return DetailedHealthResponse(
        status="healthy" if all_checks_pass else "degraded" if any(checks.values()) else "unhealthy",
        is_local=IS_LOCAL,
        checks=checks,
        configuration=configuration,
        errors=errors
    )

@app.post("/start_chat", response_model=dict, tags=["Chat"])
async def start_chat():
    """Inicia una nueva sesión de chat"""
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Service not properly configured. Check environment variables."
        )
    
    try:
        # Asegurar que el agente existe
        agent_id = agent_manager.get_or_create_agent()
        
        # Crear un nuevo thread
        with project_client:
            thread = project_client.agents.threads.create()
            logger.info(f"Created new thread: {thread.id}")
            return {
                "thread_id": thread.id,
                "agent_id": agent_id,
                "status": "ready"
            }
            
    except Exception as e:
        logger.error(f"Error in start_chat: {e}", exc_info=True)
        
        # Si el error es relacionado con el agente, intentar reset
        if "agent" in str(e).lower():
            agent_manager.reset_agent()
            
        raise HTTPException(
            status_code=500,
            detail=f"Failed to start chat: {str(e)}"
        )

@app.post("/chat", response_model=ChatResponse, tags=["Chat"])
async def chat(request: ChatRequest):
    """Procesa un mensaje del chat"""
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Service not properly configured. Check environment variables."
        )
    
    try:
        agent_id = agent_manager.get_or_create_agent()
        
        with project_client:
            # Agregar mensaje del usuario
            logger.info(f"Processing message for thread {request.thread_id}: {request.message[:50]}...")
            
            project_client.agents.messages.create(
                thread_id=request.thread_id,
                role="user",
                content=request.message,
            )

            # Crear y procesar el run con timeout
            logger.info("Creating and processing run...")
            run = project_client.agents.runs.create_and_process(
                thread_id=request.thread_id,
                agent_id=agent_id,
                timeout=60  # Timeout de 60 segundos
            )

            if run.status == "failed":
                error_msg = f"Agent run failed: {run.last_error}"
                logger.error(error_msg)
                
                # Si falla, intentar resetear el agente para el próximo intento
                if "not found" in str(run.last_error).lower():
                    agent_manager.reset_agent()
                
                raise HTTPException(status_code=500, detail=error_msg)

            # Obtener mensajes
            messages = project_client.agents.messages.list(thread_id=request.thread_id)
            
            reply = ""
            image_url = None

            # Buscar la respuesta más reciente del asistente
            for message in messages:
                if message.role == "assistant":
                    # Procesar contenido de texto
                    if hasattr(message, 'content') and message.content:
                        if isinstance(message.content, str):
                            reply = message.content
                        elif isinstance(message.content, list):
                            # El contenido puede ser una lista de objetos
                            for content in message.content:
                                if hasattr(content, 'text'):
                                    if hasattr(content.text, 'value'):
                                        reply += content.text.value
                                    else:
                                        reply += str(content.text)
                    
                    # Procesar imágenes si existen
                    if hasattr(message, 'image_contents') and message.image_contents:
                        try:
                            img = message.image_contents[0]
                            file_id = img.image_file.file_id if hasattr(img, 'image_file') else img.file_id
                            
                            logger.info(f"Downloading image file: {file_id}")
                            file_content = project_client.agents.files.download(file_id=file_id)
                            
                            # El contenido puede venir en diferentes formatos
                            if isinstance(file_content, dict):
                                image_bytes = file_content.get('content', file_content)
                            else:
                                image_bytes = file_content
                            
                            # Subir a blob storage con retry
                            @retry(max_attempts=3, delay=1)
                            def upload_image():
                                blob_name = f"{file_id}.png"
                                blob_client = blob_service_client.get_blob_client(
                                    container=images_container_name, 
                                    blob=blob_name
                                )
                                
                                logger.info(f"Uploading image to blob: {blob_name}")
                                if isinstance(image_bytes, bytes):
                                    blob_client.upload_blob(image_bytes, overwrite=True)
                                else:
                                    with io.BytesIO(image_bytes) as stream:
                                        blob_client.upload_blob(stream, overwrite=True)
                                
                                return blob_client.url
                            
                            image_url = upload_image()
                            logger.info(f"Image uploaded successfully: {image_url}")
                            
                        except Exception as img_error:
                            logger.error(f"Error processing image: {img_error}", exc_info=True)
                            # No fallar toda la respuesta por un error de imagen
                    
                    break  # Solo necesitamos el mensaje más reciente
            
            if not reply:
                reply = "Lo siento, no pude generar una respuesta. Por favor, intenta de nuevo."
            
            logger.info("Chat response prepared successfully")
            return ChatResponse(reply=reply, image_url=image_url)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in chat: {e}", exc_info=True)
        
        # Intentar proporcionar un mensaje de error más útil
        error_detail = str(e)
        if "thread" in error_detail.lower():
            error_detail = "Invalid or expired thread. Please start a new chat."
        elif "agent" in error_detail.lower():
            error_detail = "Agent service temporarily unavailable. Please try again."
            agent_manager.reset_agent()
        
        raise HTTPException(status_code=500, detail=error_detail)

@app.delete("/cleanup_agent", tags=["Admin"])
async def cleanup_agent():
    """Limpia el agente (útil para desarrollo y debugging)"""
    try:
        if not IS_LOCAL:
            raise HTTPException(
                status_code=403,
                detail="Cleanup only available in local mode for security"
            )
        
        if not agent_manager:
            raise HTTPException(
                status_code=503,
                detail="Agent manager not initialized"
            )
        
        with project_client:
            if agent_manager.agent_id:
                try:
                    project_client.agents.delete(agent_id=agent_manager.agent_id)
                    old_id = agent_manager.agent_id
                    agent_manager.reset_agent()
                    logger.info(f"Deleted agent: {old_id}")
                    return {"message": f"Agent {old_id} deleted successfully", "status": "deleted"}
                except Exception as e:
                    logger.warning(f"Could not delete agent: {e}")
                    agent_manager.reset_agent()
                    return {"message": "Agent reset but could not delete", "status": "reset"}
            else:
                return {"message": "No agent to delete", "status": "no_action"}
                
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error cleaning up agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/reset_agent", tags=["Admin"])
async def reset_agent():
    """Resetea el agent manager para forzar nueva búsqueda/creación"""
    if not agent_manager:
        raise HTTPException(
            status_code=503,
            detail="Agent manager not initialized"
        )
    
    agent_manager.reset_agent()
    return {"message": "Agent manager reset successfully", "status": "reset"}

# --- EVENTO DE INICIO ---
@app.on_event("startup")
async def startup_event():
    """Inicialización al arrancar el servicio"""
    logger.info("="*60)
    logger.info("Math Tutor Backend Starting...")
    logger.info(f"Environment: {'LOCAL' if IS_LOCAL else 'AZURE'}")
    logger.info(f"Project Endpoint: {project_endpoint}")
    logger.info(f"Model: {model_deployment_name}")
    logger.info(f"Storage Account: {storage_account_name}")
    logger.info("="*60)
    
    # Pre-crear el agente para verificar que todo funciona
    if agent_manager:
        try:
            agent_id = agent_manager.get_or_create_agent()
            logger.info(f"✅ Agent ready: {agent_id}")
        except Exception as e:
            logger.error(f"⚠️ Warning: Could not pre-create agent: {e}")
            logger.info("Agent will be created on first request")
    else:
        logger.warning("⚠️ Agent manager not initialized - check configuration")

@app.on_event("shutdown")
async def shutdown_event():
    """Limpieza al cerrar el servicio"""
    logger.info("Math Tutor Backend shutting down...")
    # Aquí podrías agregar limpieza adicional si es necesaria

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000, 
        reload=IS_LOCAL,  # Hot reload solo en desarrollo local
        log_level="info"
    )
    