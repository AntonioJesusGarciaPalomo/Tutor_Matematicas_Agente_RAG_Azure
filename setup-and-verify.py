#!/usr/bin/env python3
"""
Script de configuración y verificación para desarrollo local
Ejecutar con: python setup-and-verify.py

VERSIÓN SIMPLIFICADA:
- No crea scripts (deben estar en el repo)
- Solo verifica y configura el entorno
- Mejor detección de OS y rutas
- Más robusto y limpio
"""

import os
import sys
import subprocess
import json
import time
import platform
import shutil
from pathlib import Path
from typing import Dict, List, Optional
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Colores para output (desactivar en Windows sin soporte ANSI)
class Colors:
    if platform.system() == 'Windows':
        try:
            import colorama
            colorama.init()
            RED = '\033[0;31m'
            GREEN = '\033[0;32m'
            YELLOW = '\033[1;33m'
            BLUE = '\033[0;34m'
            CYAN = '\033[0;36m'
            NC = '\033[0m'
        except ImportError:
            RED = GREEN = YELLOW = BLUE = CYAN = NC = ''
    else:
        RED = '\033[0;31m'
        GREEN = '\033[0;32m'
        YELLOW = '\033[1;33m'
        BLUE = '\033[0;34m'
        CYAN = '\033[0;36m'
        NC = '\033[0m'

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
    icons = {
        "OK": f"{Colors.GREEN}✅{Colors.NC}",
        "ERROR": f"{Colors.RED}❌{Colors.NC}",
        "WARNING": f"{Colors.YELLOW}⚠️{Colors.NC}",
        "INFO": f"{Colors.BLUE}ℹ️{Colors.NC}",
        "": f"{Colors.BLUE}▶{Colors.NC}"
    }
    icon = icons.get(status, icons[""])
    print(f"  {icon} {step}")

def run_command(cmd: List[str], capture: bool = True, check: bool = True, timeout: int = 30) -> Optional[str]:
    """Ejecuta un comando y retorna el output"""
    try:
        if capture:
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                check=check,
                timeout=timeout
            )
            return result.stdout.strip()
        else:
            subprocess.run(cmd, check=check, timeout=timeout)
            return None
    except subprocess.TimeoutExpired:
        logger.error(f"Command timed out: {' '.join(cmd)}")
        return None
    except subprocess.CalledProcessError as e:
        if check:
            logger.error(f"Command failed: {' '.join(cmd)}")
            logger.error(f"Error: {e.stderr}")
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
        self.env_template = self.root_dir / ".env.template"
        self.errors = []
        self.warnings = []
        self.is_windows = platform.system() == 'Windows'
        self.python_cmd = self._get_python_command()
        
    def _get_python_command(self) -> str:
        """Detecta el comando de Python correcto según el OS"""
        for cmd in ['python3', 'python']:
            if run_command([cmd, '--version'], check=False):
                return cmd
        return 'python'
    
    def _get_pip_path(self, venv_dir: Path) -> Path:
        """Obtiene la ruta correcta de pip según el OS"""
        if self.is_windows:
            pip = venv_dir / "Scripts" / "pip.exe"
        else:
            pip = venv_dir / "bin" / "pip"
        
        if not pip.exists():
            # Fallback a python -m pip
            if self.is_windows:
                python = venv_dir / "Scripts" / "python.exe"
            else:
                python = venv_dir / "bin" / "python"
            return python
        return pip
        
    def check_prerequisites(self) -> bool:
        """Verifica los prerrequisitos del sistema"""
        print_header("1. Verificando Prerrequisitos")
        
        prerequisites = [
            ("Python 3.12+", [self.python_cmd, "--version"], False),
            ("pip", [self.python_cmd, "-m", "pip", "--version"], False),
            ("Azure CLI", ["az", "--version"], True),
            ("Docker", ["docker", "--version"], True),  # opcional
            ("Make", ["make", "--version"], True),  # opcional
        ]
        
        all_required_ok = True
        
        for name, cmd, optional in prerequisites:
            if run_command(cmd, check=False):
                print_step(f"{name} instalado", "OK")
            else:
                if optional:
                    print_step(f"{name} no instalado (opcional)", "WARNING")
                    self.warnings.append(f"{name} no está instalado")
                else:
                    print_step(f"{name} NO instalado", "ERROR")
                    self.errors.append(f"{name} no está instalado")
                    all_required_ok = False
        
        # Verificar versión específica de Python
        try:
            version_output = run_command([self.python_cmd, "--version"], check=False)
            if version_output:
                import re
                match = re.search(r'Python (\d+)\.(\d+)', version_output)
                if match:
                    major, minor = int(match.group(1)), int(match.group(2))
                    if major == 3 and minor >= 12:
                        print_step(f"Python {major}.{minor} verificado", "OK")
                    elif major == 3 and minor >= 10:
                        print_step(f"Python {major}.{minor} - Se recomienda 3.12+", "WARNING")
                        self.warnings.append(f"Python {major}.{minor} < 3.12")
                    else:
                        print_step(f"Python {major}.{minor} - Versión muy antigua", "ERROR")
                        self.errors.append(f"Python {major}.{minor} es demasiado antiguo")
                        all_required_ok = False
        except Exception as e:
            logger.debug(f"Error verificando versión de Python: {e}")
        
        return all_required_ok
    
    def check_azure_auth(self) -> bool:
        """Verifica y configura la autenticación de Azure"""
        print_header("2. Verificando Autenticación de Azure")
        
        account_info = run_command(["az", "account", "show"], check=False)
        
        if account_info:
            try:
                account = json.loads(account_info)
                user_name = account.get('user', {}).get('name', 'Unknown')
                subscription = account.get('name', 'Unknown')
                print_step(f"Autenticado como: {user_name}", "OK")
                print_step(f"Suscripción: {subscription}", "OK")
                return True
            except json.JSONDecodeError:
                print_step("Error parseando información de cuenta", "WARNING")
        
        print_step("No autenticado en Azure", "WARNING")
        response = input("\n  ¿Deseas autenticarte ahora? (s/n): ").lower().strip()
        
        if response == 's':
            print_step("Ejecutando 'az login'...")
            try:
                run_command(["az", "login"], capture=False)
                return True
            except:
                self.errors.append("Fallo al autenticar con Azure")
                return False
        else:
            self.warnings.append("No autenticado en Azure - algunos features no funcionarán")
            return False
    
    def setup_virtual_environments(self) -> bool:
        """Crea los entornos virtuales si no existen"""
        print_header("3. Configurando Entornos Virtuales")
        
        success = True
        
        for name, venv_dir in [("Backend", self.backend_dir / ".venv"), 
                                ("Frontend", self.frontend_dir / ".venv")]:
            if not venv_dir.exists():
                print_step(f"Creando venv para {name}...")
                try:
                    run_command([self.python_cmd, "-m", "venv", str(venv_dir)])
                    print_step(f"Venv del {name} creado", "OK")
                except Exception as e:
                    print_step(f"Error creando venv para {name}: {e}", "ERROR")
                    self.errors.append(f"Failed to create {name} venv")
                    success = False
            else:
                print_step(f"Venv del {name} ya existe", "OK")
        
        return success
    
    def install_dependencies(self) -> bool:
        """Instala las dependencias de Python"""
        print_header("4. Instalando Dependencias")
        
        success = True
        
        for name, proj_dir in [("Backend", self.backend_dir), 
                               ("Frontend", self.frontend_dir)]:
            
            venv_dir = proj_dir / ".venv"
            req_file = proj_dir / "requirements.txt"
            
            if not req_file.exists():
                print_step(f"requirements.txt no encontrado para {name}", "ERROR")
                self.errors.append(f"{name} requirements.txt missing")
                success = False
                continue
            
            print_step(f"Instalando dependencias del {name}...")
            
            pip_path = self._get_pip_path(venv_dir)
            
            try:
                # Actualizar pip primero
                if pip_path.name.endswith('python') or pip_path.name.endswith('python.exe'):
                    # Usar python -m pip
                    run_command([str(pip_path), "-m", "pip", "install", "--upgrade", "pip"], 
                               capture=False, timeout=60)
                    run_command([str(pip_path), "-m", "pip", "install", "-r", str(req_file)], 
                               capture=False, timeout=300)
                else:
                    # Usar pip directamente
                    run_command([str(pip_path), "install", "--upgrade", "pip"], 
                               capture=False, timeout=60)
                    run_command([str(pip_path), "install", "-r", str(req_file)], 
                               capture=False, timeout=300)
                
                print_step(f"Dependencias del {name} instaladas", "OK")
                
            except Exception as e:
                print_step(f"Error instalando dependencias del {name}: {e}", "ERROR")
                self.errors.append(f"Failed to install {name} dependencies")
                success = False
        
        # Verificar auth_config.py
        auth_config_path = self.backend_dir / "auth_config.py"
        if not auth_config_path.exists():
            print_step("auth_config.py no existe", "WARNING")
            self.warnings.append("auth_config.py missing - authentication may fail")
        else:
            print_step("auth_config.py encontrado", "OK")
        
        return success
    
    def check_env_file(self) -> bool:    
        """Verifica y configura el archivo .env"""
        print_header("5. Verificando Configuración (.env)")
        
        if not self.env_file.exists():
            print_step(".env NO existe", "WARNING")
            
            if self.env_template.exists():
                response = input("\n  ¿Deseas crear .env desde .env.template? (s/n): ").lower().strip()
                if response == 's':
                    shutil.copy(self.env_template, self.env_file)
                    print_step(".env creado desde template", "OK")
                    print_step("⚠️ Edita .env con tus valores de Azure antes de continuar", "WARNING")
                    self.warnings.append(".env creado pero necesita configuración")
                else:
                    print_step("Necesitas crear .env manualmente", "ERROR")
                    self.errors.append(".env file missing")
                    return False
            else:
                print_step(".env.template tampoco existe", "ERROR")
                self.errors.append("Both .env and .env.template missing")
                return False
        
        # Leer y verificar variables
        env_vars = {}
        with open(self.env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
        
        # Variables críticas requeridas
        required_vars = {
            "PROJECT_ENDPOINT": "Endpoint del proyecto AI",
            "STORAGE_ACCOUNT_NAME": "Nombre de la cuenta de storage",
            "MODEL_DEPLOYMENT_NAME": "Nombre del modelo desplegado"
        }
        
        missing_vars = []
        configured_vars = []
        
        for var, description in required_vars.items():
            if var in env_vars and env_vars[var]:
                value_preview = env_vars[var][:30] + "..." if len(env_vars[var]) > 30 else "***"
                print_step(f"{var}: {value_preview}", "OK")
                configured_vars.append(var)
            else:
                print_step(f"{var}: NO CONFIGURADO ({description})", "ERROR")
                missing_vars.append(var)
        
        # Variables opcionales pero recomendadas
        optional_vars = {
            "AZURE_CLIENT_ID": "Service Principal ID",
            "DEBUG": "Modo debug",
            "ENVIRONMENT": "Entorno (local/azure)"
        }
        
        for var, description in optional_vars.items():
            if var in env_vars and env_vars[var]:
                print_step(f"{var}: configurado", "INFO")
            else:
                print_step(f"{var}: no configurado ({description})", "INFO")
        
        if missing_vars:
            self.errors.append(f"Variables críticas faltantes: {', '.join(missing_vars)}")
            return False
        
        # Copiar .env a subdirectorios si no existen
        for subdir in [self.backend_dir, self.frontend_dir]:
            subdir_env = subdir / ".env"
            if not subdir_env.exists():
                shutil.copy(self.env_file, subdir_env)
                print_step(f".env copiado a {subdir.name}/", "OK")
            else:
                print_step(f"{subdir.name}/.env ya existe", "INFO")
        
        print_step(".env verificado correctamente", "OK")
        return True
    
    def verify_scripts(self) -> bool:
        """Verifica que los scripts de ejecución existen"""
        print_header("6. Verificando Scripts de Ejecución")
        
        # Scripts esperados según el OS
        if self.is_windows:
            expected_scripts = {
                "run-local.bat": "Ejecutar backend + frontend",
                "run-local.ps1": "Ejecutar con PowerShell (opcional)",
            }
        else:
            expected_scripts = {
                "run-local.sh": "Ejecutar backend + frontend",
                "run-backend.sh": "Solo backend",
                "run-frontend.sh": "Solo frontend",
            }
        
        # Scripts opcionales multiplataforma
        optional_scripts = {
            "Makefile": "Comandos make",
            "docker-compose.yml": "Ejecución con Docker",
            "test-api.py": "Tests de API",
        }
        
        all_ok = True
        
        # Verificar scripts principales
        for script, description in expected_scripts.items():
            script_path = self.root_dir / script
            if script_path.exists():
                print_step(f"{script}: {description}", "OK")
                
                # Verificar permisos de ejecución en Unix
                if not self.is_windows and script.endswith('.sh'):
                    import stat
                    st = os.stat(script_path)
                    if not (st.st_mode & stat.S_IEXEC):
                        print_step(f"  Agregando permisos de ejecución a {script}", "INFO")
                        os.chmod(script_path, st.st_mode | stat.S_IEXEC)
            else:
                print_step(f"{script}: NO ENCONTRADO - {description}", "ERROR")
                self.errors.append(f"Script {script} missing")
                all_ok = False
        
        # Verificar scripts opcionales
        for script, description in optional_scripts.items():
            if (self.root_dir / script).exists():
                print_step(f"{script}: {description}", "INFO")
        
        return all_ok
    
    def test_backend_connection(self) -> bool:
        """Verifica si el backend está ejecutándose"""
        print_header("7. Verificando Conexión con Backend")
        
        print_step("Intentando conectar con el backend...")
        
        try:
            import requests
            response = requests.get("http://localhost:8000/health", timeout=2)
            
            if response.status_code == 200:
                health_data = response.json()
                print_step(f"Backend respondiendo: {health_data.get('status', 'unknown')}", "OK")
                
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
                
                return True
                
        except requests.exceptions.ConnectionError:
            print_step("Backend no está ejecutándose", "INFO")
            print_step("Ejecuta './run-backend.sh' o 'make run-backend' para iniciarlo", "INFO")
            
        except ImportError:
            print_step("Módulo 'requests' no instalado en el entorno global", "WARNING")
            
        except Exception as e:
            print_step(f"Error verificando backend: {e}", "WARNING")
        
        return True  # No es crítico que el backend esté corriendo durante setup
    
    def verify_azure_resources(self) -> bool:
        """Verifica que los recursos de Azure están disponibles"""
        print_header("8. Verificando Recursos de Azure")
        
        if not self.env_file.exists():
            print_step(".env no existe, saltando verificación de Azure", "WARNING")
            return True
        
        # Leer configuración
        env_vars = {}
        with open(self.env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
        
        # Verificar AI Project endpoint
        project_endpoint = env_vars.get("PROJECT_ENDPOINT", "")
        if project_endpoint:
            print_step(f"Project Endpoint configurado", "OK")
            
            # Validar formato básico del endpoint
            if "azure" in project_endpoint.lower() or "api" in project_endpoint.lower():
                print_step("Formato del endpoint parece correcto", "OK")
            else:
                print_step("Formato del endpoint puede ser incorrecto", "WARNING")
                self.warnings.append("PROJECT_ENDPOINT format may be incorrect")
        else:
            print_step("Project Endpoint no configurado", "ERROR")
            self.errors.append("PROJECT_ENDPOINT not configured")
        
        # Verificar Storage Account
        storage_account = env_vars.get("STORAGE_ACCOUNT_NAME", "")
        if storage_account:
            print_step(f"Storage Account: {storage_account}", "OK")
            
            # Intentar verificar en Azure (solo si está autenticado)
            if run_command(["az", "account", "show"], check=False):
                result = run_command([
                    "az", "storage", "account", "show",
                    "--name", storage_account
                ], check=False)
                
                if result:
                    print_step("Storage Account verificado en Azure", "OK")
                else:
                    print_step("Storage Account no encontrado o sin permisos", "WARNING")
                    self.warnings.append("Cannot verify Storage Account in Azure")
        else:
            print_step("Storage Account no configurado", "ERROR")
            self.errors.append("STORAGE_ACCOUNT_NAME not configured")
        
        return len([e for e in self.errors if "Azure" in e]) == 0
    
    def print_summary(self):
        """Imprime un resumen final con recomendaciones"""
        print_header("📊 RESUMEN DE CONFIGURACIÓN")
        
        total_errors = len(self.errors)
        total_warnings = len(self.warnings)
        
        if self.errors:
            print_colored(f"\n❌ {total_errors} ERRORES ENCONTRADOS:", Colors.RED)
            for error in self.errors:
                print(f"  • {error}")
        
        if self.warnings:
            print_colored(f"\n⚠️ {total_warnings} ADVERTENCIAS:", Colors.YELLOW)
            for warning in self.warnings:
                print(f"  • {warning}")
        
        if not self.errors:
            print_colored("\n✅ CONFIGURACIÓN EXITOSA", Colors.GREEN)
            
            print("\n📋 PRÓXIMOS PASOS:")
            print_colored("─" * 40, Colors.CYAN)
            
            if self.env_file.exists():
                env_configured = True
                with open(self.env_file, 'r') as f:
                    content = f.read()
                    if 'YOUR_' in content or 'REPLACE_' in content:
                        env_configured = False
                
                if not env_configured:
                    print("  1. ⚠️ Edita .env con tus valores reales de Azure")
                else:
                    print("  1. ✅ .env parece estar configurado")
            
            print("\n  2. 🚀 EJECUTAR LA APLICACIÓN:")
            
            if self.is_windows:
                print(f"     {Colors.CYAN}Opción A:{Colors.NC} run-local.bat")
                print(f"     {Colors.CYAN}Opción B:{Colors.NC} make run-local")
                print(f"     {Colors.CYAN}Opción C:{Colors.NC} docker-compose up")
            else:
                print(f"     {Colors.CYAN}Opción A:{Colors.NC} ./run-local.sh")
                print(f"     {Colors.CYAN}Opción B:{Colors.NC} make run-local")
                print(f"     {Colors.CYAN}Opción C:{Colors.NC} docker-compose up")
            
            print("\n  3. 🌐 ABRIR EN EL NAVEGADOR:")
            print(f"     Frontend: {Colors.CYAN}http://localhost:7860{Colors.NC}")
            print(f"     API Docs: {Colors.CYAN}http://localhost:8000/docs{Colors.NC}")
            
            print("\n💡 COMANDOS ÚTILES:")
            print_colored("─" * 40, Colors.CYAN)
            print(f"  {Colors.GREEN}make help{Colors.NC}          - Ver todos los comandos disponibles")
            print(f"  {Colors.GREEN}make test{Colors.NC}          - Ejecutar tests")
            print(f"  {Colors.GREEN}make logs-backend{Colors.NC}  - Ver logs del backend")
            print(f"  {Colors.GREEN}make health-check{Colors.NC}  - Verificar estado de servicios")
            
            if self.warnings:
                print(f"\n📝 Nota: Hay {total_warnings} advertencias que podrías revisar")
                
        else:
            print_colored("\n❌ CONFIGURACIÓN INCOMPLETA", Colors.RED)
            print("\nPor favor, resuelve los errores antes de continuar.")
            print("\nPosibles soluciones:")
            
            if any("Python" in e for e in self.errors):
                print("  • Instala Python 3.12+: https://www.python.org/downloads/")
            if any("Azure CLI" in e for e in self.errors):
                print("  • Instala Azure CLI: https://docs.microsoft.com/cli/azure/install")
            if any(".env" in e for e in self.errors):
                print("  • Crea .env desde .env.template y configura las variables")
            if any("Script" in e for e in self.errors):
                print("  • Verifica que todos los scripts estén en el repositorio")
    
    def run(self):
        """Ejecuta todo el proceso de setup"""
        print_colored("\n🚀 MATH TUTOR - VERIFICACIÓN DE DESARROLLO LOCAL", Colors.CYAN)
        print("="*60)
        print(f"Sistema Operativo: {platform.system()} {platform.release()}")
        print(f"Python: {self.python_cmd}")
        print(f"Directorio: {self.root_dir}")
        print("="*60)
        
        # Ejecutar verificaciones
        steps = [
            ("Prerrequisitos", self.check_prerequisites, True),   # Crítico
            ("Autenticación Azure", self.check_azure_auth, False), # No crítico
            ("Entornos Virtuales", self.setup_virtual_environments, True), # Crítico
            ("Dependencias", self.install_dependencies, True),     # Crítico
            ("Configuración .env", self.check_env_file, True),    # Crítico
            ("Scripts", self.verify_scripts, True),               # Crítico
            ("Backend", self.test_backend_connection, False),     # No crítico
            ("Recursos Azure", self.verify_azure_resources, False), # No crítico
        ]
        
        for step_name, step_func, is_critical in steps:
            try:
                if not step_func():
                    if is_critical and self.errors:
                        print_colored(f"\n⛔ Setup detenido por errores críticos en: {step_name}", Colors.RED)
                        break
            except Exception as e:
                logger.error(f"Error ejecutando {step_name}: {e}")
                if is_critical:
                    self.errors.append(f"Critical error in {step_name}: {str(e)}")
                    break
                else:
                    self.warnings.append(f"Non-critical error in {step_name}: {str(e)}")
        
        # Mostrar resumen
        self.print_summary()

def main():
    """Función principal con manejo de argumentos"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Setup y verificación para desarrollo local de Math Tutor'
    )
    parser.add_argument(
        '--fix', 
        action='store_true', 
        help='Intenta corregir problemas automáticamente'
    )
    parser.add_argument(
        '--verbose', 
        action='store_true', 
        help='Muestra información detallada de debug'
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    setup = LocalDevSetup()
    
    try:
        setup.run()
        
        # Retornar código de salida apropiado
        if setup.errors:
            sys.exit(1)  # Hay errores
        elif setup.warnings:
            sys.exit(0)  # Solo warnings, pero OK
        else:
            sys.exit(0)  # Todo perfecto
            
    except KeyboardInterrupt:
        print_colored("\n\n⚠️ Setup interrumpido por el usuario", Colors.YELLOW)
        sys.exit(130)
    except Exception as e:
        print_colored(f"\n❌ Error inesperado: {e}", Colors.RED)
        logger.exception("Unexpected error")
        sys.exit(1)

if __name__ == "__main__":
    main()