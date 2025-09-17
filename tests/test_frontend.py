import pytest
import requests
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

class TestFrontend:
    """Suite de tests para el frontend del Math Tutor"""
    
    FRONTEND_URL = "http://localhost:7860"
    driver = None
    
    @classmethod
    def setup_class(cls):
        """Setup del navegador para tests"""
        # Configurar Chrome en modo headless
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        
        # Descomentar para usar Selenium
        # cls.driver = webdriver.Chrome(options=chrome_options)
        
        # Verificar que el frontend está disponible
        max_retries = 10
        for i in range(max_retries):
            try:
                response = requests.get(cls.FRONTEND_URL, timeout=5)
                if response.status_code == 200:
                    print("✅ Frontend está listo")
                    break
            except:
                if i == max_retries - 1:
                    raise Exception("Frontend no está disponible")
                print(f"Esperando frontend... intento {i+1}/{max_retries}")
                time.sleep(2)
    
    @classmethod
    def teardown_class(cls):
        """Cleanup después de los tests"""
        if cls.driver:
            cls.driver.quit()
    
    def test_frontend_loads(self):
        """Test que el frontend carga correctamente"""
        response = requests.get(self.FRONTEND_URL)
        assert response.status_code == 200
        assert "AI Math Tutor" in response.text
        print("✅ Frontend carga correctamente")
    
    def test_frontend_has_required_elements(self):
        """Test que el frontend tiene los elementos necesarios"""
        response = requests.get(self.FRONTEND_URL)
        content = response.text
        
        # Verificar elementos clave
        assert "Tutor" in content
        assert "Azure AI Foundry" in content
        assert "Enviar" in content or "Send" in content
        
        print("✅ Frontend contiene todos los elementos requeridos")
