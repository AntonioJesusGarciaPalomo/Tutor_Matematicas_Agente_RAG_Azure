.PHONY: help setup install-deps create-env run-backend run-frontend run-local run-docker test clean deploy provision

# Variables
PYTHON := python3
PIP := pip3
VENV_BACKEND := backend/.venv
VENV_FRONTEND := frontend/.venv
BACKEND_PORT := 8000
FRONTEND_PORT := 7860

# Colores para output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Muestra esta ayuda
	@echo "$(GREEN)Math Tutor - AI Foundry Agent Service$(NC)"
	@echo "======================================"
	@echo ""
	@echo "$(YELLOW)Comandos disponibles:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

setup: create-env install-deps ## Configuración completa del entorno local
	@echo "$(GREEN)✅ Configuración completada$(NC)"
	@echo ""
	@echo "$(YELLOW)Próximos pasos:$(NC)"
	@echo "  1. Configura las variables en .env"
	@echo "  2. Ejecuta: make run-local"

create-env: ## Crea los entornos virtuales
	@echo "$(YELLOW)Creando entornos virtuales...$(NC)"
	@test -d $(VENV_BACKEND) || $(PYTHON) -m venv $(VENV_BACKEND)
	@test -d $(VENV_FRONTEND) || $(PYTHON) -m venv $(VENV_FRONTEND)
	@echo "$(GREEN)✅ Entornos virtuales creados$(NC)"

install-deps: ## Instala todas las dependencias
	@echo "$(YELLOW)Instalando dependencias del backend...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && $(PIP) install -q -r backend/requirements.txt
	@echo "$(YELLOW)Instalando dependencias del frontend...$(NC)"
	@. $(VENV_FRONTEND)/bin/activate && $(PIP) install -q -r frontend/requirements.txt
	@echo "$(GREEN)✅ Dependencias instaladas$(NC)"

check-env: ## Verifica que el archivo .env existe
	@if [ ! -f .env ]; then \
		echo "$(RED)❌ Error: No se encontró el archivo .env$(NC)"; \
		echo "$(YELLOW)Crea el archivo .env desde la plantilla:$(NC)"; \
		echo "  cp .env.template .env"; \
		echo "  # Luego edita .env con tus valores"; \
		exit 1; \
	fi
	@cp .env backend/.env
	@cp .env frontend/.env

run-backend: check-env ## Ejecuta solo el backend
	@echo "$(YELLOW)🚀 Iniciando Backend en http://localhost:$(BACKEND_PORT)$(NC)"
	@cd backend && . .venv/bin/activate && python main.py

run-frontend: check-env ## Ejecuta solo el frontend
	@echo "$(YELLOW)🚀 Iniciando Frontend en http://localhost:$(FRONTEND_PORT)$(NC)"
	@cd frontend && . .venv/bin/activate && BACKEND_URI=http://localhost:$(BACKEND_PORT) python app.py

run-local: check-env ## Ejecuta backend y frontend juntos
	@echo "$(GREEN)🚀 Iniciando Math Tutor en modo local...$(NC)"
	@echo "========================================="
	@bash run-local.sh

run-docker: check-env ## Ejecuta con Docker Compose
	@echo "$(YELLOW)🐳 Iniciando con Docker Compose...$(NC)"
	@docker-compose up --build

run-docker-detached: check-env ## Ejecuta con Docker en segundo plano
	@echo "$(YELLOW)🐳 Iniciando con Docker Compose (detached)...$(NC)"
	@docker-compose up -d --build
	@echo "$(GREEN)✅ Servicios iniciados en segundo plano$(NC)"
	@echo "  Backend:  http://localhost:$(BACKEND_PORT)"
	@echo "  Frontend: http://localhost:$(FRONTEND_PORT)"

stop-docker: ## Detiene los contenedores Docker
	@echo "$(YELLOW)🛑 Deteniendo contenedores...$(NC)"
	@docker-compose down
	@echo "$(GREEN)✅ Contenedores detenidos$(NC)"

logs-backend: ## Muestra los logs del backend
	@docker-compose logs -f backend

logs-frontend: ## Muestra los logs del frontend
	@docker-compose logs -f frontend

test: check-env ## Ejecuta la suite de tests
	@echo "$(YELLOW)🧪 Ejecutando tests...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && python -m pytest tests/ -v
	@echo "$(GREEN)✅ Tests completados$(NC)"

test-backend: check-env ## Ejecuta solo tests del backend
	@echo "$(YELLOW)🧪 Ejecutando tests del backend...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && python tests/test_backend.py
	@echo "$(GREEN)✅ Tests del backend completados$(NC)"

test-integration: check-env ## Ejecuta tests de integración
	@echo "$(YELLOW)🧪 Ejecutando tests de integración...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && python tests/test_integration.py
	@echo "$(GREEN)✅ Tests de integración completados$(NC)"

clean: ## Limpia archivos temporales y cachés
	@echo "$(YELLOW)🧹 Limpiando archivos temporales...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name ".DS_Store" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Limpieza completada$(NC)"

clean-all: clean ## Limpia todo incluyendo entornos virtuales
	@echo "$(YELLOW)🧹 Limpiando entornos virtuales...$(NC)"
	@rm -rf $(VENV_BACKEND) $(VENV_FRONTEND)
	@echo "$(GREEN)✅ Limpieza profunda completada$(NC)"

# Comandos de Azure
az-login: ## Login en Azure CLI
	@echo "$(YELLOW)🔐 Iniciando sesión en Azure...$(NC)"
	@az login

az-set-subscription: ## Configura la suscripción de Azure
	@echo "$(YELLOW)📋 Suscripciones disponibles:$(NC)"
	@az account list --output table
	@echo ""
	@read -p "Ingresa el ID de la suscripción: " sub_id; \
	az account set --subscription $$sub_id
	@echo "$(GREEN)✅ Suscripción configurada$(NC)"

provision: ## Aprovisiona la infraestructura en Azure
	@echo "$(YELLOW)🏗️ Aprovisionando infraestructura en Azure...$(NC)"
	@source .env && azd env set AZURE_LOCATION $$AZURE_LOCATION
	@azd provision
	@echo "$(GREEN)✅ Infraestructura aprovisionada$(NC)"

deploy: ## Despliega la aplicación en Azure
	@echo "$(YELLOW)🚀 Desplegando aplicación en Azure...$(NC)"
	@azd deploy
	@echo "$(GREEN)✅ Aplicación desplegada$(NC)"

destroy: ## Elimina todos los recursos de Azure
	@echo "$(RED)⚠️  ADVERTENCIA: Esto eliminará todos los recursos de Azure$(NC)"
	@read -p "¿Estás seguro? (y/N): " confirm; \
	if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then \
		echo "$(YELLOW)🗑️ Eliminando recursos...$(NC)"; \
		azd down; \
		echo "$(GREEN)✅ Recursos eliminados$(NC)"; \
	else \
		echo "$(YELLOW)Operación cancelada$(NC)"; \
	fi

# Utilidades de desarrollo
format: ## Formatea el código con black
	@echo "$(YELLOW)🎨 Formateando código...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && pip install -q black && black backend/
	@. $(VENV_FRONTEND)/bin/activate && pip install -q black && black frontend/
	@echo "$(GREEN)✅ Código formateado$(NC)"

lint: ## Ejecuta linters en el código
	@echo "$(YELLOW)🔍 Analizando código...$(NC)"
	@. $(VENV_BACKEND)/bin/activate && pip install -q pylint && pylint backend/*.py || true
	@. $(VENV_FRONTEND)/bin/activate && pip install -q pylint && pylint frontend/*.py || true
	@echo "$(GREEN)✅ Análisis completado$(NC)"

health-check: ## Verifica el estado de los servicios
	@echo "$(YELLOW)🏥 Verificando estado de servicios...$(NC)"
	@curl -s http://localhost:$(BACKEND_PORT)/health | python -m json.tool || echo "$(RED)❌ Backend no responde$(NC)"
	@curl -s http://localhost:$(FRONTEND_PORT) > /dev/null && echo "$(GREEN)✅ Frontend activo$(NC)" || echo "$(RED)❌ Frontend no responde$(NC)"

monitor: ## Monitorea los servicios en tiempo real
	@echo "$(YELLOW)📊 Monitoreando servicios...$(NC)"
	@watch -n 2 'curl -s http://localhost:$(BACKEND_PORT)/health | python -m json.tool'

# Desarrollo rápido
dev: setup run-local ## Setup completo y ejecución local

rebuild: clean-all setup ## Reconstruye todo desde cero

restart: stop-docker run-docker-detached ## Reinicia los contenedores Docker

.DEFAULT_GOAL := help