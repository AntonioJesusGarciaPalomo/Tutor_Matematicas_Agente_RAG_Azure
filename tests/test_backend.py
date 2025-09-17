import pytest
import requests
import time
from typing import Optional

class TestBackend:
    """Suite de tests para el backend del Math Tutor"""
    
    BASE_URL = "http://localhost:8000"
    thread_id: Optional[str] = None
    
    @classmethod
    def setup_class(cls):
        """Setup antes de todos los tests"""
        # Esperar a que el backend esté listo
        max_retries = 10
        for i in range(max_retries):
            try:
                response = requests.get(f"{cls.BASE_URL}/health", timeout=5)
                if response.status_code == 200:
                    print("✅ Backend está listo")
                    break
            except:
                if i == max_retries - 1:
                    raise Exception("Backend no está disponible después de 10 intentos")
                print(f"Esperando backend... intento {i+1}/{max_retries}")
                time.sleep(2)
    
    def test_health_endpoint(self):
        """Test del endpoint de salud"""
        response = requests.get(f"{self.BASE_URL}/health")
        assert response.status_code == 200
        
        data = response.json()
        assert "status" in data
        assert "is_local" in data
        assert "agent_ready" in data
        assert "storage_ready" in data
        
        print(f"Health check response: {data}")
    
    def test_start_chat(self):
        """Test de inicio de chat"""
        response = requests.post(f"{self.BASE_URL}/start_chat")
        assert response.status_code == 200
        
        data = response.json()
        assert "thread_id" in data
        assert data["thread_id"] is not None
        
        # Guardar para otros tests
        TestBackend.thread_id = data["thread_id"]
        print(f"Chat iniciado con thread_id: {TestBackend.thread_id}")
    
    def test_simple_math_question(self):
        """Test con una pregunta matemática simple"""
        if not TestBackend.thread_id:
            self.test_start_chat()
        
        payload = {
            "thread_id": TestBackend.thread_id,
            "message": "¿Cuánto es 2 + 2?"
        }
        
        response = requests.post(
            f"{self.BASE_URL}/chat",
            json=payload,
            timeout=30
        )
        assert response.status_code == 200
        
        data = response.json()
        assert "reply" in data
        assert data["reply"] is not None
        assert len(data["reply"]) > 0
        
        # Verificar que la respuesta menciona "4"
        assert "4" in data["reply"]
        print(f"Respuesta: {data['reply'][:100]}...")
    
    def test_complex_math_with_visualization(self):
        """Test con visualización matemática"""
        if not TestBackend.thread_id:
            self.test_start_chat()
        
        payload = {
            "thread_id": TestBackend.thread_id,
            "message": "Dibuja la gráfica de y = x^2 entre -5 y 5"
        }
        
        print("Enviando solicitud de visualización (puede tardar)...")
        response = requests.post(
            f"{self.BASE_URL}/chat",
            json=payload,
            timeout=60
        )
        assert response.status_code == 200
        
        data = response.json()
        assert "reply" in data
        
        # Puede o no incluir una imagen dependiendo del agente
        if "image_url" in data and data["image_url"]:
            print(f"✅ Imagen generada: {data['image_url']}")
            # Verificar que la URL es válida
            assert data["image_url"].startswith("http")
        else:
            print("ℹ️ No se generó imagen para esta respuesta")
    
    def test_conversation_context(self):
        """Test de contexto en la conversación"""
        # Iniciar nueva conversación
        response = requests.post(f"{self.BASE_URL}/start_chat")
        thread_id = response.json()["thread_id"]
        
        # Primera pregunta
        payload1 = {
            "thread_id": thread_id,
            "message": "Mi número favorito es 42"
        }
        response1 = requests.post(f"{self.BASE_URL}/chat", json=payload1, timeout=30)
        assert response1.status_code == 200
        
        # Segunda pregunta referenciando la primera
        payload2 = {
            "thread_id": thread_id,
            "message": "¿Cuál es mi número favorito multiplicado por 2?"
        }
        response2 = requests.post(f"{self.BASE_URL}/chat", json=payload2, timeout=30)
        assert response2.status_code == 200
        
        data = response2.json()
        # Verificar que recuerda el contexto y menciona 84
        assert "84" in data["reply"] or "ochenta y cuatro" in data["reply"].lower()
        print("✅ El agente mantiene el contexto de la conversación")
    
    def test_error_handling(self):
        """Test de manejo de errores"""
        # Thread ID inválido
        payload = {
            "thread_id": "invalid-thread-id",
            "message": "Test"
        }
        
        response = requests.post(f"{self.BASE_URL}/chat", json=payload)
        assert response.status_code == 500  # Debería devolver error
        
        print("✅ Manejo de errores funciona correctamente")
        