import os
import io
import logging
from typing import Optional, Dict, Any
from contextlib import contextmanager

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
from azure.core.exceptions import ResourceNotFoundError

from dotenv import load_dotenv

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Cargar variables de entorno
load_dotenv()

app = FastAPI(title="Math Tutor Backend")

# Agregar CORS para desarrollo local
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:7860", "http://127.0.0.1:7860"],
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
    raise

# --- GESTIÓN DE AGENTES ---
class AgentManager:
    """Gestiona la creación y reutilización de agentes"""
    
    def __init__(self, project_client: AIProjectClient):
        self.project_client = project_client
        self.agent_id: Optional[str] = None
    
    def get_or_create_agent(self) -> str:
        """Obtiene un agente existente o crea uno nuevo"""
        if self.agent_id:
            return self.agent_id
            
        try:
            # Intentar obtener un agente existente
            with self.project_client:
                agents = self.project_client.agents.list()
                for agent in agents:
                    if agent.name == AGENT_NAME:
                        self.agent_id = agent.id
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
                    Always show your work and explain your reasoning.""",
                    tools=code_interpreter.definitions,
                )
                self.agent_id = agent.id
                logger.info(f"Created new agent: {self.agent_id}")
                return self.agent_id
                
        except Exception as e:
            logger.error(f"Error managing agent: {e}")
            raise

agent_manager = AgentManager(project_client)

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

# --- ENDPOINTS ---
@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Verifica el estado del servicio"""
    try:
        # Verificar que podemos acceder al proyecto
        agent_ready = False
        storage_ready = False
        
        try:
            agent_id = agent_manager.get_or_create_agent()
            agent_ready = bool(agent_id)
        except:
            pass
        
        try:
            container_client.get_container_properties()
            storage_ready = True
        except:
            pass
        
        return HealthResponse(
            status="healthy",
            is_local=IS_LOCAL,
            agent_ready=agent_ready,
            storage_ready=storage_ready
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return HealthResponse(
            status="unhealthy",
            is_local=IS_LOCAL,
            agent_ready=False,
            storage_ready=False
        )

@app.post("/start_chat", response_model=dict)
async def start_chat():
    """Inicia una nueva sesión de chat"""
    try:
        # Asegurar que el agente existe
        agent_id = agent_manager.get_or_create_agent()
        
        # Crear un nuevo thread
        with project_client:
            thread = project_client.agents.threads.create()
            logger.info(f"Created new thread: {thread.id}")
            return {"thread_id": thread.id, "agent_id": agent_id}
            
    except Exception as e:
        logger.error(f"Error in start_chat: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Procesa un mensaje del chat"""
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

            # Crear y procesar el run
            logger.info("Creating and processing run...")
            run = project_client.agents.runs.create_and_process(
                thread_id=request.thread_id,
                agent_id=agent_id,
            )

            if run.status == "failed":
                logger.error(f"Run failed: {run.last_error}")
                raise HTTPException(
                    status_code=500, 
                    detail=f"Agent run failed: {run.last_error}"
                )

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
                                    reply += content.text.value if hasattr(content.text, 'value') else str(content.text)
                    
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
                            
                            # Subir a blob storage
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
                            
                            image_url = blob_client.url
                            logger.info(f"Image uploaded successfully: {image_url}")
                        except Exception as img_error:
                            logger.error(f"Error processing image: {img_error}", exc_info=True)
                    
                    break  # Solo necesitamos el mensaje más reciente
            
            if not reply:
                reply = "Lo siento, no pude generar una respuesta. Por favor, intenta de nuevo."
            
            logger.info("Chat response prepared successfully")
            return ChatResponse(reply=reply, image_url=image_url)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in chat: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/cleanup_agent")
async def cleanup_agent():
    """Limpia el agente (útil para desarrollo)"""
    try:
        if not IS_LOCAL:
            raise HTTPException(status_code=403, detail="Cleanup only available in local mode")
        
        with project_client:
            if agent_manager.agent_id:
                project_client.agents.delete(agent_id=agent_manager.agent_id)
                old_id = agent_manager.agent_id
                agent_manager.agent_id = None
                logger.info(f"Deleted agent: {old_id}")
                return {"message": f"Agent {old_id} deleted successfully"}
            else:
                return {"message": "No agent to delete"}
                
    except Exception as e:
        logger.error(f"Error cleaning up agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- EVENTO DE INICIO ---
@app.on_event("startup")
async def startup_event():
    """Inicialización al arrancar el servicio"""
    logger.info("="*50)
    logger.info("Math Tutor Backend Starting...")
    logger.info(f"Environment: {'LOCAL' if IS_LOCAL else 'AZURE'}")
    logger.info(f"Project Endpoint: {project_endpoint}")
    logger.info(f"Model: {model_deployment_name}")
    logger.info(f"Storage Account: {storage_account_name}")
    logger.info("="*50)
    
    # Pre-crear el agente para verificar que todo funciona
    try:
        agent_id = agent_manager.get_or_create_agent()
        logger.info(f"Agent ready: {agent_id}")
    except Exception as e:
        logger.error(f"Warning: Could not pre-create agent: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)