import os
import io

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.ai.agents.models import CodeInterpreterTool
from azure.storage.blob import BlobServiceClient

from dotenv import load_dotenv
load_dotenv()

app = FastAPI()

# --- NUEVAS CONFIGURACIONES ---
AGENT_NAME = "math-tutor-agent"
storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")
images_container_name = os.environ.get("IMAGES_CONTAINER_NAME")

# --- CREDENCIAL COMPARTIDA ---
credential = DefaultAzureCredential()

# AI Project Client
project_endpoint = os.environ.get("PROJECT_ENDPOINT")
model_deployment_name = os.environ.get("MODEL_DEPLOYMENT_NAME")
project_client = AIProjectClient(endpoint=project_endpoint, credential=credential)

# --- NUEVO CLIENTE DE BLOB ---
blob_service_client = BlobServiceClient(
    account_url=f"https://{storage_account_name}.blob.core.windows.net",
    credential=credential
)

# ... (El resto del código de la API, como ChatRequest y ChatResponse, sigue igual)
class ChatRequest(BaseModel):
    thread_id: str
    message: str

class ChatResponse(BaseModel):
    reply: str
    image_url: str | None = None

# Funcion de comenzar chat
@app.post("/start_chat", response_model=dict)
def start_chat():
    try:
        code_interpreter = CodeInterpreterTool()
        with project_client:
            agent = project_client.agents.create_or_update(
                model=model_deployment_name,
                name=AGENT_NAME,
                instructions="You are a friendly math tutor. Use the Code Interpreter tool to visualize mathematical concepts when asked.",
                tools=code_interpreter.definitions,
            )
            thread = project_client.agents.threads.create()
            return {"thread_id": thread.id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    try:
        with project_client:
            # Add user message
            project_client.agents.messages.create(
                thread_id=request.thread_id,
                role="user",
                content=request.message,
            )

            # Create and process run
            run = project_client.agents.runs.create_and_process(
                thread_id=request.thread_id,
                agent_id=AGENT_NAME,
            )

            if run.status == "failed":
                raise HTTPException(status_code=500, detail=f"Run failed: {run.last_error}")

            # Fetch messages
            messages = project_client.agents.messages.list(thread_id=request.thread_id)
            
            reply = ""
            image_url = None

            for message in reversed(messages):
                if message.role == "assistant":
                    reply = message.content
                    # --- LÓGICA DE GESTIÓN DE IMÁGENES ---
                    if message.image_contents:
                        # Tomamos la primera imagen
                        img = message.image_contents[0]
                        file_id = img.image_file.file_id
                        
                        # Descargamos el contenido del fichero
                        file_content_dict = project_client.agents.files.download(file_id=file_id)
                        image_bytes = file_content_dict['content']

                        # Subimos a Blob Storage
                        blob_client = blob_service_client.get_blob_client(
                            container=images_container_name, 
                            blob=f"{file_id}.png"
                        )
                        
                        with io.BytesIO(image_bytes) as stream:
                            blob_client.upload_blob(stream, overwrite=True)
                        
                        image_url = blob_client.url

                    break # Salimos al encontrar la primera respuesta del asistente
            
            return ChatResponse(reply=reply, image_url=image_url)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))