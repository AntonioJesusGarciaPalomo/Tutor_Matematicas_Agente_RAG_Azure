import gradio as gr
import requests
import os
import logging
import asyncio
from typing import List, Tuple, Optional
from datetime import datetime

# Configuración de logging mejorada
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuración del backend
BACKEND_URL = os.environ.get("BACKEND_URI", "http://localhost:8000")
BACKEND_URL = BACKEND_URL.rstrip('/')

# Timeouts configurables
STARTUP_TIMEOUT = int(os.environ.get("STARTUP_TIMEOUT", "30"))
CHAT_TIMEOUT = int(os.environ.get("CHAT_TIMEOUT", "60"))

logger.info(f"Backend URL: {BACKEND_URL}")
logger.info(f"Startup timeout: {STARTUP_TIMEOUT}s, Chat timeout: {CHAT_TIMEOUT}s")

class BackendClient:
    """Cliente para comunicarse con el backend"""
    
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.session = requests.Session()
        self.is_healthy = False
        self.health_info = {}
    
    def check_health(self) -> bool:
        """Verifica el estado del backend"""
        try:
            response = self.session.get(
                f"{self.base_url}/health",
                timeout=5
            )
            if response.status_code == 200:
                self.health_info = response.json()
                self.is_healthy = True
                logger.info(f"Backend health: {self.health_info}")
                return True
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            self.is_healthy = False
        return False
    
    def start_chat(self) -> str:
        """Inicia una nueva sesión de chat"""
        try:
            response = self.session.post(
                f"{self.base_url}/start_chat",
                timeout=STARTUP_TIMEOUT
            )
            response.raise_for_status()
            data = response.json()
            thread_id = data.get("thread_id")
            agent_id = data.get("agent_id")
            logger.info(f"Chat started - Thread: {thread_id}, Agent: {agent_id}")
            return thread_id
        except requests.exceptions.ConnectionError:
            logger.error("Cannot connect to backend")
            return "ERROR: Cannot connect to backend"
        except requests.exceptions.Timeout:
            logger.error("Backend timeout")
            return "ERROR: Backend timeout"
        except Exception as e:
            logger.error(f"Error starting chat: {e}")
            return f"ERROR: {str(e)}"
    
    def send_message(self, thread_id: str, message: str) -> Tuple[str, Optional[str]]:
        """Envía un mensaje al backend"""
        try:
            response = self.session.post(
                f"{self.base_url}/chat",
                json={"thread_id": thread_id, "message": message},
                timeout=CHAT_TIMEOUT
            )
            response.raise_for_status()
            data = response.json()
            return data.get("reply", ""), data.get("image_url")
        except requests.exceptions.Timeout:
            return "⏱️ La solicitud tardó demasiado. El problema matemático puede ser complejo. Por favor, intenta de nuevo.", None
        except requests.exceptions.ConnectionError:
            return "🔌 Error de conexión con el backend. Verifica que el servicio esté activo.", None
        except Exception as e:
            logger.error(f"Error sending message: {e}")
            return f"❌ Error: {str(e)}", None

# Cliente global
backend_client = BackendClient(BACKEND_URL)

def format_message_with_image(text: str, image_url: Optional[str]) -> str:
    """Formatea el mensaje incluyendo la imagen si existe"""
    if image_url:
        # Usar HTML para mejor control de la imagen
        return f"""{text}

<div style="margin-top: 10px;">
    <img src="{image_url}" style="max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);" />
</div>"""
    return text

def start_new_chat() -> str:
    """Inicia una nueva conversación"""
    return backend_client.start_chat()

def process_message(
    message: str, 
    history: List[List[str]], 
    thread_id: str
) -> Tuple[str, List[List[str]], str]:
    """Procesa un mensaje del usuario"""
    
    if not message.strip():
        return "", history, thread_id
    
    # Verificar o iniciar thread
    if not thread_id or thread_id.startswith("ERROR"):
        thread_id = start_new_chat()
        if thread_id.startswith("ERROR"):
            error_msg = f"⚠️ {thread_id}\n\nPor favor, verifica que el backend esté ejecutándose."
            return "", history + [[message, error_msg]], thread_id
    
    # Enviar mensaje
    reply, image_url = backend_client.send_message(thread_id, message)
    
    # Formatear respuesta
    formatted_reply = format_message_with_image(reply, image_url)
    
    return "", history + [[message, formatted_reply]], thread_id

def clear_chat() -> Tuple[None, List, str]:
    """Limpia el chat y reinicia la sesión"""
    logger.info("Clearing chat and starting new session")
    new_thread_id = start_new_chat()
    return None, [], new_thread_id

def get_status_html() -> str:
    """Genera el HTML del estado del sistema"""
    backend_client.check_health()
    
    if backend_client.is_healthy:
        health = backend_client.health_info
        env_type = "Local" if health.get("is_local") else "Azure"
        agent_status = "✅" if health.get("agent_ready") else "⚠️"
        storage_status = "✅" if health.get("storage_ready") else "⚠️"
        
        return f"""
        <div style="padding: 10px; background: #f0f9ff; border-radius: 8px; margin-top: 10px;">
            <h4 style="margin: 0 0 10px 0;">Estado del Sistema</h4>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px;">
                <div>🌐 Backend: <strong>✅ Conectado</strong></div>
                <div>🔧 Entorno: <strong>{env_type}</strong></div>
                <div>🤖 Agente IA: <strong>{agent_status}</strong></div>
                <div>💾 Storage: <strong>{storage_status}</strong></div>
            </div>
        </div>
        """
    else:
        return """
        <div style="padding: 10px; background: #fee; border-radius: 8px; margin-top: 10px;">
            <h4 style="margin: 0 0 10px 0;">Estado del Sistema</h4>
            <div>🌐 Backend: <strong>❌ Desconectado</strong></div>
            <p style="margin: 10px 0 0 0; font-size: 0.9em;">
                Verifica que el backend esté ejecutándose en <code>{BACKEND_URL}</code>
            </p>
        </div>
        """.format(BACKEND_URL=BACKEND_URL)

# CSS personalizado
custom_css = """
.gradio-container {
    max-width: 1000px !important;
    margin: auto !important;
}
#chatbot {
    height: 600px !important;
}
.message img {
    max-width: 100%;
    height: auto;
}
.status-container {
    margin-top: 20px;
}
"""

# Interfaz de Gradio
with gr.Blocks(theme=gr.themes.Soft(), css=custom_css) as demo:
    gr.Markdown(
        """
        # 🎓 AI Math Tutor
        ### Powered by Azure AI Foundry Agent Service
        
        Haz cualquier pregunta matemática o solicita visualizaciones como gráficos y diagramas.
        El tutor puede resolver problemas paso a paso y crear visualizaciones interactivas.
        """
    )
    
    # Estado del thread
    thread_id = gr.State("")
    
    # Chatbot principal
    chatbot = gr.Chatbot(
        label="Tutor de Matemáticas IA",
        bubble_full_width=False,
        height=500,
        elem_id="chatbot",
        show_copy_button=True,
        render_markdown=True
    )
    
    # Área de entrada
    with gr.Row():
        msg_box = gr.Textbox(
            label="Tu mensaje:",
            placeholder="Ejemplo: 'Dibuja la gráfica de y = sin(x)' o 'Explica la fórmula cuadrática'",
            lines=2,
            scale=4
        )
        with gr.Column(scale=1):
            submit_btn = gr.Button("Enviar", variant="primary", size="lg")
            clear_btn = gr.Button("Nueva Conversación", variant="secondary")
    
    # Ejemplos
    with gr.Accordion("📚 Ejemplos de Preguntas", open=False):
        gr.Examples(
            examples=[
                "Dibuja la gráfica de y = x^2 - 4x + 3",
                "Explica la derivada de sin(x) paso a paso",
                "¿Qué es el teorema de Pitágoras? Muéstrame un ejemplo visual",
                "Grafica la función f(x) = e^(-x) * cos(2πx)",
                "Resuelve la ecuación: 2x^2 + 5x - 3 = 0",
                "Visualiza la distribución normal con media 0 y desviación estándar 1",
                "Muestra cómo calcular el área bajo la curva de y = x^2 entre 0 y 2",
                "Explica visualmente qué es una integral definida",
            ],
            inputs=msg_box,
            label="Haz clic en un ejemplo para usarlo"
        )
    
    # Estado del sistema
    with gr.Accordion("🔧 Estado del Sistema", open=False):
        status_html = gr.HTML(value=get_status_html())
        refresh_btn = gr.Button("🔄 Actualizar Estado", size="sm")
    
    # Información adicional
    with gr.Accordion("ℹ️ Acerca de este Tutor", open=False):
        gr.Markdown(
            """
            Este Tutor de Matemáticas IA utiliza Azure AI Foundry Agent Service con capacidades de Code Interpreter para:
            
            - **Resolver problemas matemáticos** paso a paso
            - **Generar visualizaciones** y gráficos interactivos
            - **Explicar conceptos complejos** de forma clara
            - **Proporcionar experiencias de aprendizaje** personalizadas
            
            ### Capacidades:
            - ✅ Álgebra y Cálculo
            - ✅ Estadística y Probabilidad
            - ✅ Geometría y Trigonometría
            - ✅ Visualización de funciones
            - ✅ Análisis numérico
            
            ### Cómo usar:
            1. Escribe tu pregunta matemática en el cuadro de texto
            2. Haz clic en "Enviar" o presiona Enter
            3. Espera la respuesta (puede incluir gráficos generados)
            4. Continúa la conversación o inicia una nueva
            """
        )
    
    # Configurar eventos
    msg_box.submit(
        process_message,
        [msg_box, chatbot, thread_id],
        [msg_box, chatbot, thread_id]
    )
    
    submit_btn.click(
        process_message,
        [msg_box, chatbot, thread_id],
        [msg_box, chatbot, thread_id]
    )
    
    clear_btn.click(
        clear_chat,
        [],
        [msg_box, chatbot, thread_id]
    )
    
    refresh_btn.click(
        get_status_html,
        [],
        [status_html]
    )
    
    # Inicializar al cargar
    demo.load(
        start_new_chat,
        [],
        [thread_id]
    )

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 7860))
    
    logger.info("="*50)
    logger.info("Starting Math Tutor Frontend")
    logger.info(f"Port: {port}")
    logger.info(f"Backend URL: {BACKEND_URL}")
    logger.info("="*50)
    
    # Verificar conexión inicial con el backend
    if backend_client.check_health():
        logger.info("✅ Backend connection successful")
    else:
        logger.warning("⚠️ Cannot connect to backend - frontend will start anyway")
    
    demo.launch(
        server_name="0.0.0.0",
        server_port=port,
        share=False
    )