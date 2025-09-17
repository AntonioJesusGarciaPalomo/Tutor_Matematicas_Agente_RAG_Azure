#!/usr/bin/env python3
"""
Script de configuración y verificación para desarrollo local
Ejecutar con: python setup-and-verify.py
"""

import os
import sys
import subprocess
import json
import time
import requests
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Colores para output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def print_colored(message: str, color: str = Colors.NC):
    """Imprime mensaje con color"""
    print(f"{color}{message}{Colors.NC}")

def print_header(title: str):
    """Imprime un header formateado"""
    print("\n" + "="*60)
    print_colored(f"  {title}", Colors.CYAN)
    print("="*60)

def print_step(step: str, status: str = ""):
    """Imprime un paso del proceso"""
    if status == "OK":
        print(f"  {Colors.GREEN}✅{Colors.NC} {step}")
    elif status == "ERROR":
        print(f"  {Colors.RED}❌{Colors.NC} {step}")
    elif status == "WARNING":
        print(f"  {Colors.YELLOW}⚠️{Colors.NC} {step}")
    else:
        print(f"  {Colors.BLUE}▶{Colors.NC} {step}")

def run_command(cmd: List[str], capture: bool = True, check: bool = True) -> Optional[str]:
    """Ejecuta un comando y retorna el output"""
    try:
        if capture:
            result = subprocess.run(cmd, capture_output=True, text=True, check=check)
            return result.stdout.strip()
        else:
            subprocess.run(cmd, check=check)
            return None
    except subprocess.CalledProcessError as e:
        if check:
            raise
        return None
    except FileNotFoundError:
        return None

class LocalDevSetup:
    """Gestiona la configuración del entorno de desarrollo local"""
    
    def __init__(self):
        self.root_dir = Path.cwd()
        self.backend_dir = self.root_dir / "backend"
        self.frontend_dir = self.root_dir / "frontend"
        self.env_file = self.root_dir / ".env"
        self.errors = []
        self.warnings = []
        
    def check_prerequisites(self) -> bool:
        """Verifica los prerrequisitos del sistema"""
        print_header("1. Verificando Prerrequisitos")
        
        prerequisites = {
            "python3": "Python 3.12+",
            "pip": "pip",
            "az": "Azure CLI",
            "docker": "Docker (opcional)"
        }
        
        all_ok = True
        for cmd, name in prerequisites.items():
            if run_command([cmd, "--version"], check=False):
                print_step(f"{name} instalado", "OK")
            else:
                if cmd == "docker":  # Docker es opcional
                    print_step(f"{name} no instalado (opcional)", "WARNING")
                    self.warnings.append(f"{name} no está instalado")
                else:
                    print_step(f"{name} NO instalado", "ERROR")
                    self.errors.append(f"{name} no está instalado")
                    all_ok = False
        
        # Verificar versión de Python
        python_version = sys.version_info
        if python_version.major == 3 and python_version.minor >= 12:
            print_step(f"Python {python_version.major}.{python_version.minor} detectado", "OK")
        else:
            print_step(f"Python {python_version.major}.{python_version.minor} - Se requiere 3.12+", "WARNING")
            self.warnings.append("Python version < 3.12")
        
        return all_ok
    
    def check_azure_auth(self) -> bool:
        """Verifica y configura la autenticación de Azure"""
        print_header("2. Verificando Autenticación de Azure")
        
        # Verificar si ya está autenticado
        account_info = run_command(["az", "account", "show"], check=False)
        
        if account_info:
            try:
                account = json.loads(account_info)
                print_step(f"Autenticado como: {account.get('user', {}).get('name', 'Unknown')}", "OK")
                print_step(f"Suscripción: {account.get('name', 'Unknown')}", "OK")
                return True
            except json.JSONDecodeError:
                pass
        
        print_step("No autenticado en Azure", "WARNING")
        response = input("\n  ¿Deseas autenticarte ahora? (s/n): ").lower()
        
        if response == 's':
            print_step("Ejecutando 'az login'...")
            run_command(["az", "login"], capture=False)
            return True
        else:
            self.warnings.append("No autenticado en Azure")
            return False
    
    def setup_virtual_environments(self) -> bool:
        """Crea los entornos virtuales"""
        print_header("3. Configurando Entornos Virtuales")
        
        all_ok = True
        
        # Backend venv
        backend_venv = self.backend_dir / ".venv"
        if not backend_venv.exists():
            print_step("Creando venv para backend...")
            run_command([sys.executable, "-m", "venv", str(backend_venv)])
            print_step("Venv del backend creado", "OK")
        else:
            print_step("Venv del backend ya existe", "OK")
        
        # Frontend venv
        frontend_venv = self.frontend_dir / ".venv"
        if not frontend_venv.exists():
            print_step("Creando venv para frontend...")
            run_command([sys.executable, "-m", "venv", str(frontend_venv)])
            print_step("Venv del frontend creado", "OK")
        else:
            print_step("Venv del frontend ya existe", "OK")
        
        return all_ok
    
    def install_dependencies(self) -> bool:
        """Instala las dependencias de Python"""
        print_header("4. Instalando Dependencias")
        
        all_ok = True
        
        # Backend dependencies
        print_step("Instalando dependencias del backend...")
        backend_pip = self.backend_dir / ".venv" / "bin" / "pip"
        if not backend_pip.exists():
            backend_pip = self.backend_dir / ".venv" / "Scripts" / "pip.exe"
        
        try:
            run_command([str(backend_pip), "install", "--upgrade", "pip"], capture=False)
            run_command([str(backend_pip), "install", "-r", str(self.backend_dir / "requirements.txt")], capture=False)
            print_step("Dependencias del backend instaladas", "OK")
        except Exception as e:
            print_step(f"Error instalando dependencias del backend: {e}", "ERROR")
            self.errors.append("Failed to install backend dependencies")
            all_ok = False
        
        # Frontend dependencies
        print_step("Instalando dependencias del frontend...")
        frontend_pip = self.frontend_dir / ".venv" / "bin" / "pip"
        if not frontend_pip.exists():
            frontend_pip = self.frontend_dir / ".venv" / "Scripts" / "pip.exe"
        
        try:
            run_command([str(frontend_pip), "install", "--upgrade", "pip"], capture=False)
            run_command([str(frontend_pip), "install", "-r", str(self.frontend_dir / "requirements.txt")], capture=False)
            print_step("Dependencias del frontend instaladas", "OK")
        except Exception as e:
            print_step(f"Error instalando dependencias del frontend: {e}", "ERROR")
            self.errors.append("Failed to install frontend dependencies")
            all_ok = False
        
        # Copiar auth_config.py al backend si no existe
        auth_config_path = self.backend_dir / "auth_config.py"
        if not auth_config_path.exists():
            print_step("Creando auth_config.py...")
            # Aquí podrías copiar el archivo o crearlo
            print_step("auth_config.py necesita ser creado manualmente", "WARNING")
            self.warnings.append("auth_config.py needs to be created")
        
        return all_ok
    
    def check_env_file(self) -> bool:    
        """Verifica el archivo .env sin modificarlo"""
        print_header("5. Verificando Configuración (.env)")
        
        if not self.env_file.exists():
            print_step(".env NO existe", "ERROR")
            print_step("Por favor, crea un .env basado en .env.template", "ERROR")
            self.errors.append(".env file missing")
            return False
        
        # Solo leer y verificar, sin modificar
        env_vars = {}
        with open(self.env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
        
        # Verificar variables requeridas
        required_vars = ["PROJECT_ENDPOINT", "STORAGE_ACCOUNT_NAME", "MODEL_DEPLOYMENT_NAME"]
        missing_vars = []
        
        for var in required_vars:
            if var not in env_vars or not env_vars[var]:
                missing_vars.append(var)
                print_step(f"{var}: NO CONFIGURADO", "ERROR")
            else:
                # Mostrar solo primeros caracteres por seguridad
                value_preview = env_vars[var][:20] + "..." if len(env_vars[var]) > 20 else "***"
                print_step(f"{var}: {value_preview}", "OK")
        
        if missing_vars:
            self.errors.append(f"Variables faltantes: {', '.join(missing_vars)}")
            return False
        
        print_step(".env verificado correctamente", "OK")
        return True
        
    
    def test_backend(self) -> bool:
        """Prueba que el backend funciona correctamente"""
        print_header("6. Verificando Backend")
        
        # Iniciar backend temporalmente
        print_step("Iniciando backend para pruebas...")
        
        backend_python = self.backend_dir / ".venv" / "bin" / "python"
        if not backend_python.exists():
            backend_python = self.backend_dir / ".venv" / "Scripts" / "python.exe"
        
        # Iniciar proceso del backend
        backend_process = subprocess.Popen(
            [str(backend_python), "main.py"],
            cwd=str(self.backend_dir),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Esperar a que inicie
        print_step("Esperando a que el backend inicie...")
        time.sleep(5)
        
        # Verificar health endpoint
        try:
            response = requests.get("http://localhost:8000/health", timeout=5)
            if response.status_code == 200:
                health_data = response.json()
                print_step(f"Backend respondiendo: {health_data['status']}", "OK")
                
                # Verificar componentes
                if health_data.get('agent_ready'):
                    print_step("Agent AI listo", "OK")
                else:
                    print_step("Agent AI no disponible", "WARNING")
                    self.warnings.append("AI Agent not ready")
                
                if health_data.get('storage_ready'):
                    print_step("Storage conectado", "OK")
                else:
                    print_step("Storage no conectado", "WARNING")
                    self.warnings.append("Storage not connected")
                
                backend_ok = True
            else:
                print_step(f"Backend respondió con error: {response.status_code}", "ERROR")
                backend_ok = False
        except Exception as e:
            print_step(f"No se pudo conectar al backend: {e}", "ERROR")
            self.errors.append("Backend connection failed")
            backend_ok = False
        
        # Detener el backend
        backend_process.terminate()
        time.sleep(2)
        
        return backend_ok
    
    def test_integration(self) -> bool:
        """Prueba la integración completa"""
        print_header("7. Prueba de Integración")
        
        print_step("Verificando scripts de ejecución...")
        
        scripts_ok = True
        for script in ["run-local.sh", "run-backend.sh", "run-frontend.sh"]:
            if (self.root_dir / script).exists():
                print_step(f"Script {script} existe", "OK")
            else:
                print_step(f"Script {script} no existe", "WARNING")
                self.warnings.append(f"Script {script} missing")
        
        return scripts_ok
    
    def verify_azure_resources(self) -> bool:
        """Verifica que los recursos de Azure están disponibles"""
        print_header("8. Verificando Recursos de Azure")
        
        # Leer configuración
        env_vars = {}
        if self.env_file.exists():
            with open(self.env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        env_vars[key] = value
        
        # Verificar AI Project endpoint
        project_endpoint = env_vars.get("PROJECT_ENDPOINT")
        if project_endpoint:
            print_step(f"Project Endpoint configurado: {project_endpoint[:50]}...", "OK")
        else:
            print_step("Project Endpoint no configurado", "ERROR")
            self.errors.append("PROJECT_ENDPOINT not configured")
        
        # Verificar Storage Account
        storage_account = env_vars.get("STORAGE_ACCOUNT_NAME")
        if storage_account:
            print_step(f"Storage Account: {storage_account}", "OK")
            
            # Verificar que existe usando Azure CLI
            result = run_command([
                "az", "storage", "account", "show",
                "--name", storage_account
            ], check=False)
            
            if result:
                print_step("Storage Account verificado en Azure", "OK")
            else:
                print_step("Storage Account no encontrado en Azure", "WARNING")
                self.warnings.append("Storage Account not found in Azure")
        else:
            print_step("Storage Account no configurado", "ERROR")
            self.errors.append("STORAGE_ACCOUNT_NAME not configured")
        
        return len(self.errors) == 0
    
    def create_helper_scripts(self) -> bool:
        """Crea scripts auxiliares para desarrollo"""
        print_header("9. Creando Scripts de Ayuda")
        
        scripts = {
            "run-local.sh": self.get_run_local_script(),
            "run-backend.sh": self.get_run_backend_script(),
            "run-frontend.sh": self.get_run_frontend_script(),
            "test-local.sh": self.get_test_local_script(),
            "run-local.bat": self.get_run_local_bat(),
            "test-api.py": self.get_test_api_script()
        }
        
        for filename, content in scripts.items():
            filepath = self.root_dir / filename
            with open(filepath, 'w') as f:
                f.write(content)
            
            # Hacer ejecutable en Unix
            if filename.endswith('.sh'):
                import stat
                st = os.stat(filepath)
                os.chmod(filepath, st.st_mode | stat.S_IEXEC)
            
            print_step(f"{filename} creado", "OK")
        
        return True
    
    def get_run_local_script(self) -> str:
        return '''#!/bin/bash
echo "🚀 Iniciando Math Tutor en modo local..."
echo "========================================="

# Función para matar procesos al salir
cleanup() {
    echo -e "\\n🛑 Deteniendo servicios..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    exit
}

trap cleanup EXIT INT TERM

# Iniciar backend
echo "▶️ Iniciando Backend en http://localhost:8000"
cd backend
source .venv/bin/activate
export ENVIRONMENT=local
export DEBUG=true
python main.py &
BACKEND_PID=$!
cd ..

# Esperar a que el backend esté listo
echo "⏳ Esperando a que el backend esté listo..."
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ Backend está listo"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ El backend no responde después de 30 segundos"
        exit 1
    fi
    sleep 1
done

# Iniciar frontend
echo "▶️ Iniciando Frontend en http://localhost:7860"
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py &
FRONTEND_PID=$!
cd ..

echo ""
echo "========================================="
echo "✅ Servicios iniciados:"
echo "   - Backend:  http://localhost:8000"
echo "   - Frontend: http://localhost:7860"
echo "   - API Docs: http://localhost:8000/docs"
echo "   - Health:   http://localhost:8000/health"
echo ""
echo "📝 Logs:"
echo "   - Presiona Ctrl+C para detener ambos servicios"
echo "========================================="

# Mantener el script ejecutándose
wait
'''
    
    def get_run_backend_script(self) -> str:
        return '''#!/bin/bash
echo "🚀 Iniciando Backend..."
cd backend
source .venv/bin/activate
export ENVIRONMENT=local
export DEBUG=true
python main.py
'''
    
    def get_run_frontend_script(self) -> str:
        return '''#!/bin/bash
echo "🚀 Iniciando Frontend..."
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py
'''
    
    def get_test_local_script(self) -> str:
        return '''#!/bin/bash
echo "🧪 Ejecutando Tests Locales..."
echo "=============================="

# Test Backend Health
echo ""
echo "1. Testing Backend Health..."
curl -s http://localhost:8000/health | python -m json.tool

# Test Backend Detailed Health
echo ""
echo "2. Testing Backend Detailed Health..."
curl -s http://localhost:8000/health/detailed | python -m json.tool

# Test Start Chat
echo ""
echo "3. Testing Start Chat..."
RESPONSE=$(curl -s -X POST http://localhost:8000/start_chat)
echo $RESPONSE | python -m json.tool
THREAD_ID=$(echo $RESPONSE | python -c "import sys, json; print(json.load(sys.stdin)['thread_id'])")

# Test Send Message
echo ""
echo "4. Testing Send Message..."
curl -s -X POST http://localhost:8000/chat \\
  -H "Content-Type: application/json" \\
  -d "{
    \\"thread_id\\": \\"$THREAD_ID\\",
    \\"message\\": \\"¿Cuánto es 2+2?\\"
  }" | python -m json.tool

echo ""
echo "✅ Tests completados"
'''
    
    def get_run_local_bat(self) -> str:
        return '''@echo off
echo 🚀 Iniciando Math Tutor en modo local...
echo =========================================

REM Iniciar backend
echo ▶️ Iniciando Backend en http://localhost:8000
start /B cmd /c "cd backend && .venv\\Scripts\\activate && set ENVIRONMENT=local && set DEBUG=true && python main.py"

REM Esperar 5 segundos
timeout /t 5 /nobreak > nul

REM Iniciar frontend
echo ▶️ Iniciando Frontend en http://localhost:7860
start /B cmd /c "cd frontend && .venv\\Scripts\\activate && set BACKEND_URI=http://localhost:8000 && python app.py"

echo.
echo =========================================
echo ✅ Servicios iniciados:
echo    - Backend:  http://localhost:8000
echo    - Frontend: http://localhost:7860
echo    - API Docs: http://localhost:8000/docs
echo.
echo 📝 Cierra esta ventana para detener los servicios
echo =========================================

pause
'''
    
    def get_test_api_script(self) -> str:
        return '''#!/usr/bin/env python3
"""Script de prueba de API para desarrollo local"""

import requests
import json
import time
from typing import Dict, Any

BASE_URL = "http://localhost:8000"

def test_health():
    """Prueba el endpoint de health"""
    print("\\n📍 Testing /health...")
    response = requests.get(f"{BASE_URL}/health")
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Status: {data['status']}")
        print(f"   Environment: {data.get('environment', 'unknown')}")
        print(f"   Agent Ready: {data.get('agent_ready', False)}")
        print(f"   Storage Ready: {data.get('storage_ready', False)}")
        return True
    else:
        print(f"❌ Error: {response.status_code}")
        return False

def test_detailed_health():
    """Prueba el health detallado"""
    print("\\n📍 Testing /health/detailed...")
    response = requests.get(f"{BASE_URL}/health/detailed")
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Status: {data['status']}")
        print(f"   Auth Method: {data.get('checks', {}).get('auth_method', 'unknown')}")
        print(f"   Agent Count: {data.get('checks', {}).get('agent_count', 0)}")
        if data.get('errors'):
            print(f"   ⚠️ Errors: {', '.join(data['errors'])}")
        return True
    else:
        print(f"❌ Error: {response.status_code}")
        return False

def test_chat_flow():
    """Prueba el flujo completo de chat"""
    print("\\n📍 Testing chat flow...")
    
    # 1. Iniciar chat
    print("   1. Starting chat...")
    response = requests.post(f"{BASE_URL}/start_chat")
    if response.status_code != 200:
        print(f"   ❌ Failed to start chat: {response.status_code}")
        return False
    
    chat_data = response.json()
    thread_id = chat_data['thread_id']
    print(f"   ✅ Thread ID: {thread_id}")
    
    # 2. Enviar mensaje simple
    print("   2. Sending test message...")
    message_data = {
        "thread_id": thread_id,
        "message": "¿Cuánto es 2 + 2?"
    }
    
    start_time = time.time()
    response = requests.post(
        f"{BASE_URL}/chat",
        json=message_data,
        timeout=60
    )
    elapsed = time.time() - start_time
    
    if response.status_code == 200:
        reply_data = response.json()
        reply = reply_data['reply'][:100] + "..." if len(reply_data['reply']) > 100 else reply_data['reply']
        print(f"   ✅ Got reply in {elapsed:.2f}s: {reply}")
        
        if reply_data.get('image_url'):
            print(f"   🖼️ Image generated: {reply_data['image_url']}")
        
        return True
    else:
        print(f"   ❌ Failed to send message: {response.status_code}")
        if response.text:
            print(f"   Error: {response.text[:200]}")
        return False

def test_visualization():
    """Prueba la generación de visualizaciones"""
    print("\\n📍 Testing visualization...")
    
    # Iniciar chat
    response = requests.post(f"{BASE_URL}/start_chat")
    if response.status_code != 200:
        print(f"   ❌ Failed to start chat")
        return False
    
    thread_id = response.json()['thread_id']
    
    # Pedir una visualización
    message_data = {
        "thread_id": thread_id,
        "message": "Dibuja la gráfica de y = sin(x) desde -2π hasta 2π"
    }
    
    print("   Requesting visualization (this may take a while)...")
    response = requests.post(
        f"{BASE_URL}/chat",
        json=message_data,
        timeout=90
    )
    
    if response.status_code == 200:
        reply_data = response.json()
        if reply_data.get('image_url'):
            print(f"   ✅ Visualization generated: {reply_data['image_url']}")
            return True
        else:
            print(f"   ⚠️ No image generated, but got response")
            return True
    else:
        print(f"   ❌ Failed: {response.status_code}")
        return False

def main():
    print("="*60)
    print("🧪 Math Tutor API Test Suite")
    print("="*60)
    
    # Verificar que el backend está disponible
    try:
        requests.get(f"{BASE_URL}/health", timeout=2)
    except:
        print("\\n❌ Backend no está disponible en {BASE_URL}")
        print("   Asegúrate de que el backend está ejecutándose")
        return
    
    # Ejecutar tests
    results = []
    
    results.append(("Health Check", test_health()))
    results.append(("Detailed Health", test_detailed_health()))
    results.append(("Chat Flow", test_chat_flow()))
    results.append(("Visualization", test_visualization()))
    
    # Resumen
    print("\\n" + "="*60)
    print("📊 Test Results Summary")
    print("="*60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASSED" if result else "❌ FAILED"
        print(f"  {test_name}: {status}")
    
    print(f"\\n  Total: {passed}/{total} tests passed")
    
    if passed == total:
        print("\\n🎉 All tests passed!")
    else:
        print(f"\\n⚠️ {total - passed} tests failed")

if __name__ == "__main__":
    main()
'''
    
    def print_summary(self):
        """Imprime un resumen final"""
        print_header("RESUMEN DE CONFIGURACIÓN")
        
        if self.errors:
            print_colored("\n❌ ERRORES ENCONTRADOS:", Colors.RED)
            for error in self.errors:
                print(f"  • {error}")
        
        if self.warnings:
            print_colored("\n⚠️ ADVERTENCIAS:", Colors.YELLOW)
            for warning in self.warnings:
                print(f"  • {warning}")
        
        if not self.errors:
            print_colored("\n✅ CONFIGURACIÓN EXITOSA", Colors.GREEN)
            print("\n📋 Próximos pasos:")
            print("  1. Verifica que el archivo .env tiene todas las variables configuradas")
            print("  2. Ejecuta los servicios:")
            print("     • En Unix/Mac: ./run-local.sh")
            print("     • En Windows: run-local.bat")
            print("     • O por separado:")
            print("       - ./run-backend.sh")
            print("       - ./run-frontend.sh")
            print("  3. Abre http://localhost:7860 en tu navegador")
            print("  4. Para probar la API: python test-api.py")
            print("\n💡 Tips:")
            print("  • Revisa los logs en backend.log")
            print("  • API Docs disponible en http://localhost:8000/docs")
            print("  • Health check en http://localhost:8000/health")
        else:
            print_colored("\n❌ CONFIGURACIÓN INCOMPLETA", Colors.RED)
            print("Por favor, resuelve los errores antes de continuar")
    
    def run(self):
        """Ejecuta todo el proceso de setup"""
        print_colored("\n🚀 MATH TUTOR - SETUP DE DESARROLLO LOCAL", Colors.CYAN)
        print("="*60)
        
        # Ejecutar verificaciones
        steps = [
            ("Prerrequisitos", self.check_prerequisites),
            ("Autenticación Azure", self.check_azure_auth),
            ("Entornos Virtuales", self.setup_virtual_environments),
            ("Dependencias", self.install_dependencies),
            ("Configuración .env", self.check_env_file),
            ("Backend", self.test_backend),
            ("Integración", self.test_integration),
            ("Recursos Azure", self.verify_azure_resources),
            ("Scripts Helper", self.create_helper_scripts)
        ]
        
        for step_name, step_func in steps:
            if not step_func():
                if self.errors and step_name in ["Prerrequisitos", "Configuración .env"]:
                    print_colored(f"\n⛔ Setup detenido por errores críticos en {step_name}", Colors.RED)
                    break
        
        # Mostrar resumen
        self.print_summary()

if __name__ == "__main__":
    setup = LocalDevSetup()
    setup.run()