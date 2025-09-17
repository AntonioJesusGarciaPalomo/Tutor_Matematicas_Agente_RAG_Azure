import pytest
import requests
import time
from test_backend import TestBackend
from test_frontend import TestFrontend

class TestIntegration:
    """Tests de integración end-to-end"""
    
    BACKEND_URL = "http://localhost:8000"
    FRONTEND_URL = "http://localhost:7860"
    
    def test_full_conversation_flow(self):
        """Test completo de flujo de conversación"""
        # 1. Verificar que ambos servicios están activos
        backend_health = requests.get(f"{self.BACKEND_URL}/health")
        assert backend_health.status_code == 200
        
        frontend_response = requests.get(self.FRONTEND_URL)
        assert frontend_response.status_code == 200
        
        # 2. Iniciar chat
        chat_response = requests.post(f"{self.BACKEND_URL}/start_chat")
        assert chat_response.status_code == 200
        thread_id = chat_response.json()["thread_id"]
        
        # 3. Enviar pregunta matemática
        payload = {
            "thread_id": thread_id,
            "message": "Explica el teorema de Pitágoras"
        }
        
        response = requests.post(
            f"{self.BACKEND_URL}/chat",
            json=payload,
            timeout=30
        )
        assert response.status_code == 200
        
        data = response.json()
        assert "reply" in data
        assert len(data["reply"]) > 50  # Respuesta sustancial
        
        # Verificar que menciona elementos clave
        reply_lower = data["reply"].lower()
        assert any(word in reply_lower for word in ["triángulo", "cateto", "hipotenusa", "cuadrado"])
        
        print("✅ Flujo completo de conversación funciona correctamente")
    
    def test_concurrent_sessions(self):
        """Test de múltiples sesiones concurrentes"""
        # Crear múltiples sesiones
        sessions = []
        for i in range(3):
            response = requests.post(f"{self.BACKEND_URL}/start_chat")
            assert response.status_code == 200
            sessions.append(response.json()["thread_id"])
        
        # Verificar que todas son diferentes
        assert len(set(sessions)) == 3
        
        # Enviar mensajes a cada sesión
        for i, thread_id in enumerate(sessions):
            payload = {
                "thread_id": thread_id,
                "message": f"¿Cuánto es {i+1} + {i+1}?"
            }
            response = requests.post(
                f"{self.BACKEND_URL}/chat",
                json=payload,
                timeout=30
            )
            assert response.status_code == 200
            
            expected = str((i+1) * 2)
            assert expected in response.json()["reply"]
        
        print("✅ Múltiples sesiones concurrentes funcionan correctamente")


# Archivo principal de ejecución de tests
if __name__ == "__main__":
    print("🧪 Ejecutando suite de tests del Math Tutor")
    print("="*50)
    
    # Ejecutar tests del backend
    print("\n📝 Tests del Backend:")
    backend_tests = TestBackend()
    backend_tests.setup_class()
    backend_tests.test_health_endpoint()
    backend_tests.test_start_chat()
    backend_tests.test_simple_math_question()
    backend_tests.test_complex_math_with_visualization()
    backend_tests.test_conversation_context()
    backend_tests.test_error_handling()
    
    # Ejecutar tests del frontend
    print("\n📝 Tests del Frontend:")
    frontend_tests = TestFrontend()
    frontend_tests.setup_class()
    frontend_tests.test_frontend_loads()
    frontend_tests.test_frontend_has_required_elements()
    frontend_tests.teardown_class()
    
    # Ejecutar tests de integración
    print("\n📝 Tests de Integración:")
    integration_tests = TestIntegration()
    integration_tests.test_full_conversation_flow()
    integration_tests.test_concurrent_sessions()
    
    print("\n" + "="*50)
    print("✅ ¡Todos los tests pasaron exitosamente!")
    print("="*50)
    