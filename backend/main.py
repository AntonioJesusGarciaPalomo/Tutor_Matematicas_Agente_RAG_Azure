import os
import io

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential, InteractiveBrowserCredential
from azure.ai.agents.models import CodeInterpreterTool
from azure.storage.blob import BlobServiceClient

from dotenv import load_dotenv
load_dotenv()

app = FastAPI()

# --- CONFIGURACIONES ---
AGENT_NAME = "math-tutor-agent"
storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")
images_container_name = os.environ.get("IMAGES_CONTAINER_NAME")

# --- CREDENCIAL (INTERACTIVA PARA LOCAL) ---
credential = InteractiveBrowserCredential()

# AI Project Client
project_endpoint = os.environ.get("PROJECT_ENDPOINT")
model_deployment_name = os.environ.get("MODEL_DEPLOYMENT_NAME")
project_client = AIProjectClient(endpoint=project_endpoint, credential=credential)

# Blob Storage Client
blob_service_client = BlobServiceClient(
    account_url=f"https://{storage_account_name}.blob.core.windows.net",
    credential=credential
)

class ChatRequest(BaseModel):
    thread_id: str
    message: str

class ChatResponse(BaseModel):
    reply: str
    image_url: str | None = None

# --- FUNCIÓN CORREGIDA ---
@app.post("/start_chat", response_model=dict)
def start_chat():
    try:
        code_interpreter = CodeInterpreterTool()
        with project_client:
            # CORRECCIÓN: Usamos 'create_agent' en lugar de 'create_or_update'
            agent = project_client.agents.create_agent(
                model=model_deployment_name,
                name=AGENT_NAME,
                instructions="You are a friendly math tutor. Use the Code Interpreter tool to visualize mathematical concepts when asked.",
                tools=code_interpreter.definitions,
            )
            thread = project_client.agents.threads.create()
            return {"thread_id": thread.id}
    except Exception as e:
        # Añadimos un log más detallado para ver el error exacto
        print(f"ERROR in start_chat: {e}")
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
                    if message.image_contents:
                        img = message.image_contents[0]
                        file_id = img.image_file.file_id
                        
                        file_content_dict = project_client.agents.files.download(file_id=file_id)
                        image_bytes = file_content_dict['content']

                        blob_client = blob_service_client.get_blob_client(
                            container=images_container_name, 
                            blob=f"{file_id}.png"
                        )
                        
                        with io.BytesIO(image_bytes) as stream:
                            blob_client.upload_blob(stream, overwrite=True)
                        
                        image_url = blob_client.url
                    break
            
            return ChatResponse(reply=reply, image_url=image_url)

    except Exception as e:
        print(f"ERROR in chat: {e}")
        raise HTTPException(status_code=500, detail=str(e))