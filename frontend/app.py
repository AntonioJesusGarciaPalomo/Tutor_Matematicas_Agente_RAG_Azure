import gradio as gr
import requests
import os
import logging
from typing import List, Tuple, Optional

# Configuración de logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Obtener la URL del backend con validación
BACKEND_URL = os.environ.get("BACKEND_URI")

# Validación crítica
if not BACKEND_URL:
    logger.error("BACKEND_URI environment variable is not set!")
    # Intentar usar un valor por defecto o mostrar error
    BACKEND_URL = "http://localhost:8000"
    logger.warning(f"Using default BACKEND_URL: {BACKEND_URL}")

# Asegurar que la URL no tenga trailing slash
BACKEND_URL = BACKEND_URL.rstrip('/')
logger.info(f"Backend URL configured: {BACKEND_URL}")

def start_new_chat() -> str:
    """Inicia una nueva conversación con el backend."""
    try:
        logger.info("Starting new chat session...")
        response = requests.post(
            f"{BACKEND_URL}/start_chat",
            timeout=30  # Añadir timeout
        )
        response.raise_for_status()
        thread_id = response.json()["thread_id"]
        logger.info(f"New chat started with thread_id: {thread_id}")
        return thread_id
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Connection error to backend: {e}")
        return f"Error: Cannot connect to backend at {BACKEND_URL}"
    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout connecting to backend: {e}")
        return "Error: Backend service timeout"
    except requests.exceptions.RequestException as e:
        logger.error(f"Error starting new chat: {e}")
        return f"Error starting new chat: {str(e)}"
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return f"Unexpected error: {str(e)}"

def chat_interface(
    message: str, 
    history: List[List[str]], 
    thread_id_state: str
) -> Tuple[str, List[List[str]], str]:
    """
    Maneja la interfaz de chat con el backend.
    
    Args:
        message: El mensaje del usuario
        history: El historial de conversación
        thread_id_state: El ID del thread actual
    
    Returns:
        Tuple con (mensaje_vacío, historial_actualizado, thread_id)
    """
    
    # Inicializar thread si no existe
    if not thread_id_state or "Error" in str(thread_id_state):
        thread_id_state = start_new_chat()
        if "Error" in thread_id_state:
            error_msg = f"⚠️ {thread_id_state}\n\nPlease check if the backend service is running."
            return "", history + [[message, error_msg]], thread_id_state

    try:
        logger.info(f"Sending message to thread {thread_id_state}: {message[:50]}...")
        
        response = requests.post(
            f"{BACKEND_URL}/chat",
            json={"thread_id": thread_id_state, "message": message},
            timeout=60  # Timeout más largo para procesamiento de IA
        )
        response.raise_for_status()
        chat_response = response.json()
        
        # Procesar la respuesta
        reply_text = chat_response.get("reply", "No response received")
        image_url = chat_response.get("image_url")

        if image_url:
            # Si hay una imagen, incluirla en formato Markdown
            final_reply = f"{reply_text}\n\n![Generated Image]({image_url})"
            logger.info("Response includes an image")
        else:
            final_reply = reply_text
            
        # Actualizar el historial
        new_history = history + [[message, final_reply]]
        logger.info("Chat response received successfully")

        return "", new_history, thread_id_state
    
    except requests.exceptions.Timeout:
        error_message = "⏱️ Request timeout - the math problem might be complex. Please try again."
        logger.error("Request timeout")
        return "", history + [[message, error_message]], thread_id_state
    
    except requests.exceptions.ConnectionError:
        error_message = f"🔌 Connection error: Cannot reach backend at {BACKEND_URL}"
        logger.error("Connection error")
        return "", history + [[message, error_message]], thread_id_state
    
    except requests.exceptions.RequestException as e:
        error_message = f"❌ Error in chat: {str(e)}"
        logger.error(f"Request error: {e}")
        return "", history + [[message, error_message]], thread_id_state
    
    except Exception as e:
        error_message = f"⚠️ Unexpected error: {str(e)}"
        logger.error(f"Unexpected error: {e}")
        return "", history + [[message, error_message]], thread_id_state

def handle_submit(
    message: str, 
    history: List[List[str]], 
    thread_id_state: str
) -> Tuple[str, List[List[str]], str]:
    """
    Maneja el envío de mensajes, mostrando el mensaje del usuario inmediatamente.
    """
    if not message.strip():
        return "", history, thread_id_state
    
    # Añadir el mensaje del usuario inmediatamente con indicador de carga
    history_with_user = history + [[message, "🤔 Thinking..."]]
    
    # Procesar la respuesta
    _, new_history, new_thread_id = chat_interface(message, history, thread_id_state)
    
    return "", new_history, new_thread_id

def clear_chat() -> Tuple[None, List, str]:
    """Limpia el chat y reinicia la sesión."""
    logger.info("Clearing chat and starting new session")
    new_thread_id = start_new_chat()
    return None, [], new_thread_id

# Interfaz de Gradio mejorada
with gr.Blocks(
    theme=gr.themes.Soft(),
    css="""
    .gradio-container {
        max-width: 900px !important;
        margin: auto !important;
    }
    #chatbot {
        height: 600px !important;
    }
    """
) as demo:
    gr.Markdown(
        """
        # 🎓 AI Math Tutor
        ### Powered by Azure AI Foundry Agent Service
        
        Ask any math question or request visualizations like graphs and charts!
        """
    )
    
    # Estado del thread
    thread_id = gr.State("")
    
    # Chatbot principal
    chatbot = gr.Chatbot(
        label="Math Tutor Assistant",
        bubble_full_width=False,
        height=500,
        elem_id="chatbot",
        show_copy_button=True
    )
    
    # Caja de mensaje con ejemplos
    msg_box = gr.Textbox(
        label="Your message:",
        placeholder="Try: 'Draw a graph of y = sin(x)' or 'Explain the quadratic formula'",
        lines=2,
        max_lines=4
    )
    
    # Botones de control
    with gr.Row():
        submit_btn = gr.Button("Send", variant="primary")
        clear_btn = gr.Button("New Chat", variant="secondary")
    
    # Ejemplos predefinidos
    gr.Examples(
        examples=[
            "Draw a graph of y = x^2 - 4x + 3",
            "Explain the derivative of sin(x)",
            "What is the Pythagorean theorem?",
            "Plot the function f(x) = e^(-x) * cos(2πx)",
            "Solve the equation: 2x^2 + 5x - 3 = 0",
        ],
        inputs=msg_box,
        label="Example Questions"
    )
    
    # Configurar eventos
    msg_box.submit(
        handle_submit, 
        [msg_box, chatbot, thread_id], 
        [msg_box, chatbot, thread_id]
    )
    
    submit_btn.click(
        handle_submit,
        [msg_box, chatbot, thread_id],
        [msg_box, chatbot, thread_id]
    )
    
    clear_btn.click(
        clear_chat,
        [],
        [msg_box, chatbot, thread_id]
    )
    
    # Información de estado
    gr.Markdown(
        f"""
        ---
        **Backend Status:** {'✅ Connected' if BACKEND_URL and not BACKEND_URL.startswith('http://localhost') else '⚠️ Check configuration'}
        
        <details>
        <summary>ℹ️ About this tutor</summary>
        
        This AI Math Tutor uses Azure AI Foundry Agent Service with Code Interpreter capabilities to:
        - Solve mathematical problems step by step
        - Generate visualizations and graphs
        - Explain complex mathematical concepts
        - Provide interactive learning experiences
        </details>
        """
    )

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 7860))
    logger.info(f"Starting Gradio app on port {port}")
    logger.info(f"Backend URL: {BACKEND_URL}")
    
    demo.launch(
        server_name="0.0.0.0",
        server_port=port,
        share=False
    )