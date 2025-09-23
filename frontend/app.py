import gradio as gr
import requests
import os
import logging
import time
from typing import List, Tuple, Optional, Dict, Any
from datetime import datetime
from functools import wraps

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
RETRY_ATTEMPTS = int(os.environ.get("RETRY_ATTEMPTS", "3"))

logger.info("="*60)
logger.info("Math Tutor Frontend Starting...")
logger.info(f"Backend URL: {BACKEND_URL}")
logger.info(f"Timeouts - Startup: {STARTUP_TIMEOUT}s, Chat: {CHAT_TIMEOUT}s")
logger.info(f"Retry attempts: {RETRY_ATTEMPTS}")
logger.info("="*60)

def retry_on_error(max_attempts=3, delay=1, backoff=2):
    """Decorador para reintentar operaciones en caso de error"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempt = 1
            current_delay = delay
            
            while attempt <= max_attempts:
                try:
                    return func(*args, **kwargs)
                except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
                    if attempt == max_attempts:
                        logger.error(f"Failed after {max_attempts} attempts: {e}")
                        raise
                    
                    logger.warning(f"Attempt {attempt}/{max_attempts} failed. Retrying in {current_delay}s...")
                    time.sleep(current_delay)
                    current_delay *= backoff
                    attempt += 1
            
            return None
        return wrapper
    return decorator

class BackendClient:
    """Cliente mejorado para comunicarse con el backend"""
    
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
        self.is_healthy = False
        self.health_info = {}
        self.last_health_check = 0
        self.health_check_interval = 30  # Verificar salud cada 30 segundos
    
    @retry_on_error(max_attempts=3, delay=1)
    def check_health(self, force=False) -> bool:
        """Verifica el estado del backend con cache"""
        current_time = time.time()
        
        # Usar cache si no ha pasado mucho tiempo y no se fuerza
        if not force and (current_time - self.last_health_check) < self.health_check_interval:
            return self.is_healthy
        
        try:
            response = self.session.get(
                f"{self.base_url}/health",
                timeout=5
            )
            if response.status_code == 200:
                self.health_info = response.json()
                self.is_healthy = True
                self.last_health_check = current_time
                logger.info(f"Backend health check passed: {self.health_info}")
                return True
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            self.is_healthy = False
            self.health_info = {"error": str(e)}
        
        return False
    
    def check_detailed_health(self) -> Dict[str, Any]:
        """Obtiene información detallada de salud"""
        try:
            response = self.session.get(
                f"{self.base_url}/health/detailed",
                timeout=10
            )
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            logger.error(f"Detailed health check failed: {e}")
        
        return {
            "status": "unknown",
            "errors": ["Could not retrieve detailed health information"]
        }
    
    @retry_on_error(max_attempts=RETRY_ATTEMPTS, delay=2)
    def start_chat(self) -> str:
        """Inicia una nueva sesión de chat con reintentos"""
        try:
            response = self.session.post(
                f"{self.base_url}/start_chat",
                timeout=STARTUP_TIMEOUT
            )
            response.raise_for_status()
            data = response.json()
            thread_id = data.get("thread_id")
            agent_id = data.get("agent_id")
            status = data.get("status", "unknown")
            
            logger.info(f"Chat started - Thread: {thread_id}, Agent: {agent_id}, Status: {status}")
            return thread_id
            
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 503:
                logger.error("Backend service not properly configured")
                return "ERROR: Backend service not configured. Check server logs."
            else:
                logger.error(f"HTTP error starting chat: {e}")
                return f"ERROR: HTTP {e.response.status_code}"
                
        except requests.exceptions.ConnectionError:
            logger.error("Cannot connect to backend")
            return "ERROR: Cannot connect to backend"
            
        except requests.exceptions.Timeout:
            logger.error("Backend timeout")
            return "ERROR: Backend timeout"
            
        except Exception as e:
            logger.error(f"Unexpected error starting chat: {e}")
            return f"ERROR: {str(e)}"
    
    def send_message(self, thread_id: str, message: str, retry_count=0) -> Tuple[str, Optional[str]]:
        """Envía un mensaje al backend con manejo mejorado de errores"""
        try:
            response = self.session.post(
                f"{self.base_url}/chat",
                json={"thread_id": thread_id, "message": message},
                timeout=CHAT_TIMEOUT
            )
            response.raise_for_status()
            data = response.json()
            return data.get("reply", ""), data.get("image_url")
            
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 500:
                # Intentar parsear el mensaje de error del backend
                try:
                    error_detail = e.response.json().get("detail", str(e))
                except:
                    error_detail = str(e)
                
                # Si es un error de thread, sugerir reiniciar
                if "thread" in error_detail.lower():
                    return "❌ La sesión ha expirado. Por favor, haz clic en 'Nueva Conversación' para continuar.", None
                elif "agent" in error_detail.lower() and retry_count < 2:
                    # Reintentar si es un error de agente
                    logger.warning(f"Agent error, retrying... (attempt {retry_count + 1})")
                    time.sleep(2)
                    return self.send_message(thread_id, message, retry_count + 1)
                else:
                    return f"❌ Error del servidor: {error_detail}", None
            else:
                return f"❌ Error HTTP {e.response.status_code}", None
                
        except requests.exceptions.Timeout:
            return "⏱️ La solicitud tardó demasiado. El problema matemático puede ser complejo. Por favor, intenta de nuevo.", None
            
        except requests.exceptions.ConnectionError:
            return "🔌 Error de conexión con el backend. Verifica que el servicio esté activo.", None
            
        except Exception as e:
            logger.error(f"Unexpected error sending message: {e}")
            return f"❌ Error inesperado: {str(e)}", None

# Cliente global
backend_client = BackendClient(BACKEND_URL)

def format_message_with_image(text: str, image_url: Optional[str]) -> str:
    """Formatea el mensaje incluyendo la imagen si existe"""
    if image_url:
        # Usar HTML para mejor control de la imagen
        return f"""{text}

<div style="margin-top: 10px;">
    <a href="{image_url}" target="_blank">
        <img src="{image_url}" style="max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); cursor: pointer;" title="Click para ver en tamaño completo" />
    </a>
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
    """Procesa un mensaje del usuario con mejor manejo de errores"""
    
    if not message.strip():
        return "", history, thread_id
    
    # Agregar indicador de procesamiento inmediatamente
    temp_history = history + [[message, "🤔 Procesando tu pregunta..."]]
    
    # Verificar o iniciar thread
    if not thread_id or thread_id.startswith("ERROR"):
        thread_id = start_new_chat()
        if thread_id.startswith("ERROR"):
            error_msg = f"""⚠️ {thread_id}

**Posibles soluciones:**
1. Verifica que el backend esté ejecutándose en {BACKEND_URL}
2. Revisa las variables de entorno en el archivo .env
3. Consulta los logs del backend para más detalles"""
            return "", history + [[message, error_msg]], thread_id
    
    # Enviar mensaje
    reply, image_url = backend_client.send_message(thread_id, message)
    
    # Formatear respuesta
    formatted_reply = format_message_with_image(reply, image_url)
    
    # Actualizar historial con la respuesta real
    final_history = history + [[message, formatted_reply]]
    
    return "", final_history, thread_id

def clear_chat() -> Tuple[None, List, str]:
    """Limpia el chat y reinicia la sesión"""
    logger.info("Clearing chat and starting new session")
    new_thread_id = start_new_chat()
    return None, [], new_thread_id

def get_status_html() -> str:
    """Genera el HTML del estado del sistema con información detallada"""
    # Forzar verificación de salud
    backend_client.check_health(force=True)
    
    if backend_client.is_healthy:
        health = backend_client.health_info
        env_type = "Local" if health.get("is_local") else "Azure"
        agent_status = "✅ Listo" if health.get("agent_ready") else "⚠️ No disponible"
        storage_status = "✅ Conectado" if health.get("storage_ready") else "⚠️ Desconectado"
        
        # Obtener configuración
        config = health.get("configuration", {})
        config_items = []
        for key, value in config.items():
            status_icon = "✅" if value else "❌"
            config_items.append(f"<li>{status_icon} {key.replace('_', ' ').title()}</li>")
        
        return f"""
        <div style="padding: 15px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 10px; color: white;">
            <h4 style="margin: 0 0 15px 0; font-size: 1.2em;">🚀 Estado del Sistema</h4>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px;">
                <div style="background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px;">
                    <strong>🌐 Backend:</strong> ✅ Conectado
                </div>
                <div style="background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px;">
                    <strong>🔧 Entorno:</strong> {env_type}
                </div>
                <div style="background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px;">
                    <strong>🤖 Agente IA:</strong> {agent_status}
                </div>
                <div style="background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px;">
                    <strong>💾 Storage:</strong> {storage_status}
                </div>
            </div>
            <details style="margin-top: 10px;">
                <summary style="cursor: pointer;">📋 Configuración Detallada</summary>
                <ul style="margin-top: 10px; padding-left: 20px;">
                    {''.join(config_items)}
                </ul>
            </details>
        </div>
        """
    else:
        # Intentar obtener información detallada de error
        detailed = backend_client.check_detailed_health()
        errors = detailed.get("errors", ["No se pudo conectar con el backend"])
        
        error_list = "".join([f"<li>❌ {error}</li>" for error in errors])
        
        return f"""
        <div style="padding: 15px; background: linear-gradient(135deg, #f93b1d 0%, #ea1e63 100%); border-radius: 10px; color: white;">
            <h4 style="margin: 0 0 15px 0; font-size: 1.2em;">⚠️ Sistema No Disponible</h4>
            <div style="background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px; margin-bottom: 10px;">
                <strong>Estado:</strong> Desconectado
            </div>
            <details>
                <summary style="cursor: pointer;">🔍 Detalles del Error</summary>
                <ul style="margin-top: 10px; padding-left: 20px;">
                    {error_list}
                </ul>
                <div style="margin-top: 10px; padding: 10px; background: rgba(0,0,0,0.2); border-radius: 5px;">
                    <strong>Solución sugerida:</strong><br>
                    1. Verifica que el backend esté ejecutándose<br>
                    2. Revisa la configuración en <code>{BACKEND_URL}</code><br>
                    3. Consulta los logs del servidor
                </div>
            </details>
        </div>
        """

def refresh_status() -> str:
    """Actualiza el estado del sistema"""
    return get_status_html()

# CSS personalizado mejorado
custom_css = """
.gradio-container {
    max-width: 1200px !important;
    margin: auto !important;
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif !important;
}
#chatbot {
    height: 600px !important;
    border: 1px solid #e5e7eb !important;
    border-radius: 8px !important;
}
.message img {
    max-width: 100%;
    height: auto;
    border-radius: 8px;
    margin-top: 10px;
}
.status-container {
    margin-top: 20px;
}
/* Mejorar el aspecto de los botones */
.gr-button {
    transition: all 0.3s ease !important;
}
.gr-button:hover {
    transform: translateY(-2px) !important;
    box-shadow: 0 5px 15px rgba(0,0,0,0.1) !important;
}
/* Animación de carga */
@keyframes pulse {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
}
.loading {
    animation: pulse 2s infinite;
}
"""

# Interfaz de Gradio mejorada
with gr.Blocks(theme=gr.themes.Soft(
    primary_hue="indigo",
    secondary_hue="purple"
), css=custom_css) as demo:
    gr.Markdown(
        """
        # 🎓 AI Math Tutor
        ### Powered by Azure AI Foundry Agent Service
        
        <p style="color: #6b7280; font-size: 0.95em;">
        Haz cualquier pregunta matemática o solicita visualizaciones. 
        El tutor puede resolver problemas paso a paso, crear gráficos interactivos y explicar conceptos complejos.
        </p>
        """
    )
    
    # Estado del thread
    thread_id = gr.State("")
    
    # Chatbot principal con configuración mejorada
    chatbot = gr.Chatbot(
        label="Tutor de Matemáticas IA",
        bubble_full_width=False,
        height=500,
        elem_id="chatbot",
        show_copy_button=True,
        render_markdown=True,
        avatar_images=(None, None)
    )
    
    # Área de entrada mejorada
    with gr.Row():
        msg_box = gr.Textbox(
            label="Tu pregunta:",
            placeholder="Ejemplo: 'Dibuja la gráfica de y = sin(x)' o 'Explica la derivada paso a paso'",
            lines=2,
            scale=4,
            autofocus=True
        )
        with gr.Column(scale=1):
            submit_btn = gr.Button(
                "🚀 Enviar", 
                variant="primary", 
                size="lg"
            )
            clear_btn = gr.Button(
                "🔄 Nueva Conversación", 
                variant="secondary"
            )
    
    # Ejemplos organizados por categoría
    with gr.Accordion("📚 Ejemplos de Preguntas", open=False):
        gr.Examples(
            examples=[
                # Visualizaciones
                "Dibuja la gráfica de y = x^2 - 4x + 3",
                "Grafica la función f(x) = e^(-x) * cos(2πx)",
                "Visualiza la distribución normal con media 0 y desviación estándar 1",
                # Cálculo
                "Explica la derivada de sin(x) paso a paso",
                "Muestra cómo calcular la integral de x^2 dx",
                "¿Qué es una integral definida? Muéstrame un ejemplo visual",
                # Álgebra
                "Resuelve la ecuación: 2x^2 + 5x - 3 = 0",
                "Factoriza x^3 - 8",
                # Geometría
                "Explica el teorema de Pitágoras con un ejemplo visual",
                "Calcula el área de un círculo de radio 5",
                # Estadística
                "¿Qué es la desviación estándar?",
                "Explica la distribución binomial con un ejemplo"
            ],
            inputs=msg_box,
            label="Haz clic en un ejemplo para usarlo"
        )
    
    # Estado del sistema con auto-actualización
    with gr.Accordion("🔧 Estado del Sistema", open=False):
        status_html = gr.HTML(value=get_status_html())
        with gr.Row():
            refresh_btn = gr.Button("🔄 Actualizar Estado", size="sm")
            auto_refresh = gr.Checkbox(label="Auto-actualizar cada 30s", value=False)
    
    # Información adicional mejorada
    with gr.Accordion("ℹ️ Guía de Uso", open=False):
        gr.Markdown(
            """
            ### 🎯 Capacidades del Tutor
            
            **Matemáticas que puede resolver:**
            - ✅ **Álgebra**: Ecuaciones, factorización, sistemas de ecuaciones
            - ✅ **Cálculo**: Derivadas, integrales, límites, series
            - ✅ **Geometría**: Áreas, volúmenes, teoremas
            - ✅ **Trigonometría**: Funciones, identidades, gráficas
            - ✅ **Estadística**: Distribuciones, probabilidad, análisis de datos
            - ✅ **Álgebra Lineal**: Matrices, vectores, transformaciones
            
            ### 💡 Tips para mejores resultados:
            1. **Sé específico**: "Resuelve x^2 + 2x - 3 = 0" en lugar de "resuelve esta ecuación"
            2. **Pide visualizaciones**: "Dibuja la gráfica de..." para ver representaciones visuales
            3. **Solicita explicaciones paso a paso**: "Explica paso a paso cómo..."
            4. **Usa notación matemática estándar**: x^2 para x², sqrt(x) para √x
            
            ### ⚡ Atajos de teclado:
            - **Enter**: Enviar mensaje
            - **Shift+Enter**: Nueva línea
            - **Ctrl+K**: Limpiar chat
            """
        )
    
    # # Timer para auto-actualización (simulado con JavaScript)
    # auto_refresh_timer = gr.Timer(30, active=False)
    
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
        refresh_status,
        [],
        [status_html]
    )
    
    # # Auto-refresh cuando está activado
    # def toggle_auto_refresh(checked):
    #     return gr.Timer(active=checked)
    
    # auto_refresh.change(
    #     toggle_auto_refresh,
    #     [auto_refresh],
    #     [auto_refresh_timer]
    # )
    
    # auto_refresh_timer.tick(
    #     refresh_status,
    #     [],
    #     [status_html]
    # )
    
    # Inicializar al cargar
    demo.load(
        start_new_chat,
        [],
        [thread_id]
    )

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 7860))
    
    logger.info("="*60)
    logger.info("Starting Math Tutor Frontend")
    logger.info(f"Port: {port}")
    logger.info(f"Backend URL: {BACKEND_URL}")
    logger.info("="*60)
    
    # Verificar conexión inicial con el backend
    initial_health = backend_client.check_health(force=True)
    if initial_health:
        logger.info("✅ Backend connection successful")
        logger.info(f"Backend status: {backend_client.health_info}")
    else:
        logger.warning("⚠️ Cannot connect to backend - frontend will start anyway")
        logger.info("Users will see connection errors until backend is available")
    
    # Lanzar la aplicación
    demo.launch(
        server_name="0.0.0.0",
        server_port=port,
        share=False,
        show_error=True,  # Mostrar errores en la UI
        quiet=False  # Mostrar logs
    )