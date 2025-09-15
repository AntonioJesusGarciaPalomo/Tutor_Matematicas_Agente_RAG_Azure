import gradio as gr
import requests
import os

BACKEND_URL = os.environ.get("BACKEND_URI")

def start_new_chat():

    try:
        response = requests.post(f"{BACKEND_URL}/start_chat")
        response.raise_for_status()
        return response.json()["thread_id"]
    except requests.exceptions.RequestException as e:
        return f"Error starting new chat: {e}"

def chat_interface(message, history, thread_id_state):
    
    if not thread_id_state:
        thread_id_state = start_new_chat()
        if "Error" in thread_id_state:
            return thread_id_state, history, thread_id_state

    try:
        response = requests.post(
            f"{BACKEND_URL}/chat",
            json={"thread_id": thread_id_state, "message": message}
        )
        response.raise_for_status()
        chat_response = response.json()
        
        # --- LÓGICA DE VISUALIZACIÓN DE IMÁGENES ---
        reply_text = chat_response["reply"]
        image_url = chat_response.get("image_url") # Usamos .get para evitar errores si no hay imagen

        if image_url:
            # Si hay una URL, la añadimos al texto de respuesta como Markdown
            final_reply = f"{reply_text}\n\n![Generated Image]({image_url})"
        else:
            final_reply = reply_text
            
        # Actualizamos el historial con la respuesta final (texto + imagen)
        new_history = history + [[message, final_reply]]

        return "", new_history, thread_id_state # Limpiamos el textbox
    
    except requests.exceptions.RequestException as e:
        error_message = f"Error in chat: {e}"
        return "", history + [[message, error_message]], thread_id_state


# --- SECCIÓN DEL CHATBOT MODIFICADA PARA MEJOR EXPERIENCIA ---
with gr.Blocks(theme=gr.themes.Soft()) as demo:
    gr.Markdown("## 🤖 AI Math Tutor")
    
    thread_id = gr.State("")
    chatbot = gr.Chatbot(label="Chat with the Tutor", bubble_full_width=False, height=500)
    msg_box = gr.Textbox(label="Your message:", placeholder="Ask a math question or ask to draw a graph...")
    
    def handle_submit(message, history, thread_id_state):
        # Añade el mensaje del usuario al historial inmediatamente
        history.append([message, None])
        # Llama a la lógica del bot y actualiza el historial con la respuesta
        _, new_history, new_thread_id = chat_interface(message, history, thread_id_state)
        return "", new_history, new_thread_id

    msg_box.submit(
        handle_submit, 
        [msg_box, chatbot, thread_id], 
        [msg_box, chatbot, thread_id]
    )

    gr.ClearButton([msg_box, chatbot])


if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)