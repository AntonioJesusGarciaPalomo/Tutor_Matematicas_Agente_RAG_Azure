# ================================================
# SETUP LOCAL DEVELOPMENT ENVIRONMENT FOR WINDOWS
# ================================================
# Este script configura el entorno de desarrollo local
# SIN provisionar recursos en Azure

$ErrorActionPreference = "Stop"

# Configuración
$PYTHON_CMD = "python"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "🚀 MATH TUTOR - LOCAL DEVELOPMENT SETUP" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Función para verificar prerrequisitos
function Test-Prerequisites {
    Write-Host "`n▶ Verificando Prerrequisitos" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    $allOk = $true
    
    # Check Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "✅ Python instalado" -ForegroundColor Green
    } else {
        Write-Host "❌ Python NO instalado" -ForegroundColor Red
        Write-Host "   Instala desde: https://www.python.org/downloads/" -ForegroundColor Gray
        $allOk = $false
    }
    
    # Check pip
    try {
        python -m pip --version | Out-Null
        Write-Host "✅ pip instalado" -ForegroundColor Green
    } catch {
        Write-Host "❌ pip NO instalado" -ForegroundColor Red
        $allOk = $false
    }
    
    # Check Azure CLI (opcional)
    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Host "✅ Azure CLI instalado" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Azure CLI no instalado (opcional para desarrollo local)" -ForegroundColor Yellow
    }
    
    # Check Docker (opcional)
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-Host "✅ Docker instalado (opcional)" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  Docker no instalado (opcional)" -ForegroundColor Blue
    }
    
    if (-not $allOk) {
        Write-Host "❌ Faltan prerrequisitos obligatorios" -ForegroundColor Red
        exit 1
    }
}

# Configurar archivo .env
function Setup-EnvFile {
    Write-Host "`n▶ Configurando archivo .env" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    if (Test-Path ".env") {
        Write-Host "✅ .env ya existe" -ForegroundColor Green
        $response = Read-Host "¿Deseas sobrescribirlo con el template? (s/n)"
        if ($response -ne 's') {
            return
        }
    }
    
    if (Test-Path ".env.template") {
        Copy-Item ".env.template" ".env" -Force
        Write-Host "✅ .env creado desde template" -ForegroundColor Green
        Write-Host "⚠️  IMPORTANTE: Edita .env con tus valores de Azure" -ForegroundColor Yellow
        
        # Copiar a subdirectorios
        if (Test-Path "backend") {
            Copy-Item ".env" "backend\.env" -Force
            Write-Host "✅ .env copiado a backend\" -ForegroundColor Green
        }
        
        if (Test-Path "frontend") {
            Copy-Item ".env" "frontend\.env" -Force
            Write-Host "✅ .env copiado a frontend\" -ForegroundColor Green
        }
    } else {
        Write-Host "❌ .env.template no encontrado" -ForegroundColor Red
        exit 1
    }
}

# Crear entornos virtuales
function Setup-VirtualEnvironments {
    Write-Host "`n▶ Creando Entornos Virtuales" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Backend venv
    if (-not (Test-Path "backend\.venv")) {
        Write-Host "ℹ️  Creando venv para Backend..." -ForegroundColor Blue
        & $PYTHON_CMD -m venv backend\.venv
        Write-Host "✅ Backend venv creado" -ForegroundColor Green
    } else {
        Write-Host "✅ Backend venv ya existe" -ForegroundColor Green
    }
    
    # Frontend venv
    if (-not (Test-Path "frontend\.venv")) {
        Write-Host "ℹ️  Creando venv para Frontend..." -ForegroundColor Blue
        & $PYTHON_CMD -m venv frontend\.venv
        Write-Host "✅ Frontend venv creado" -ForegroundColor Green
    } else {
        Write-Host "✅ Frontend venv ya existe" -ForegroundColor Green
    }
}

# Instalar dependencias
function Install-Dependencies {
    Write-Host "`n▶ Instalando Dependencias" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    # Backend dependencies
    if (Test-Path "backend\requirements.txt") {
        Write-Host "ℹ️  Instalando dependencias del Backend..." -ForegroundColor Blue
        & backend\.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
        & backend\.venv\Scripts\pip.exe install -r backend\requirements.txt --quiet
        Write-Host "✅ Dependencias del Backend instaladas" -ForegroundColor Green
    } else {
        Write-Host "❌ backend\requirements.txt no encontrado" -ForegroundColor Red
    }
    
    # Frontend dependencies
    if (Test-Path "frontend\requirements.txt") {
        Write-Host "ℹ️  Instalando dependencias del Frontend..." -ForegroundColor Blue
        & frontend\.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
        & frontend\.venv\Scripts\pip.exe install -r frontend\requirements.txt --quiet
        Write-Host "✅ Dependencias del Frontend instaladas" -ForegroundColor Green
    } else {
        Write-Host "❌ frontend\requirements.txt no encontrado" -ForegroundColor Red
    }
}

# Verificar la configuración
function Test-Setup {
    Write-Host "`n▶ Verificando Configuración" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    $allOk = $true
    
    # Verificar directorios
    if (Test-Path "backend") {
        Write-Host "✅ Directorio backend existe" -ForegroundColor Green
    } else {
        Write-Host "❌ Directorio backend NO existe" -ForegroundColor Red
        $allOk = $false
    }
    
    if (Test-Path "frontend") {
        Write-Host "✅ Directorio frontend existe" -ForegroundColor Green
    } else {
        Write-Host "❌ Directorio frontend NO existe" -ForegroundColor Red
        $allOk = $false
    }
    
    # Verificar .env
    if (Test-Path ".env") {
        Write-Host "✅ Archivo .env existe" -ForegroundColor Green
        
        # Verificar variables críticas
        $envContent = Get-Content ".env" -Raw
        
        if ($envContent -match "PROJECT_ENDPOINT=.+" -and $envContent -notmatch "PROJECT_ENDPOINT=$") {
            Write-Host "✅ PROJECT_ENDPOINT configurado" -ForegroundColor Green
        } else {
            Write-Host "⚠️  PROJECT_ENDPOINT no configurado en .env" -ForegroundColor Yellow
        }
        
        if ($envContent -match "STORAGE_ACCOUNT_NAME=.+" -and $envContent -notmatch "STORAGE_ACCOUNT_NAME=$") {
            Write-Host "✅ STORAGE_ACCOUNT_NAME configurado" -ForegroundColor Green
        } else {
            Write-Host "⚠️  STORAGE_ACCOUNT_NAME no configurado en .env" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Archivo .env NO existe" -ForegroundColor Red
        $allOk = $false
    }
    
    # Verificar venvs
    if (Test-Path "backend\.venv") {
        Write-Host "✅ Backend venv existe" -ForegroundColor Green
    } else {
        Write-Host "❌ Backend venv NO existe" -ForegroundColor Red
        $allOk = $false
    }
    
    if (Test-Path "frontend\.venv") {
        Write-Host "✅ Frontend venv existe" -ForegroundColor Green
    } else {
        Write-Host "❌ Frontend venv NO existe" -ForegroundColor Red
        $allOk = $false
    }
    
    if ($allOk) {
        Write-Host "`n✅ Configuración verificada correctamente" -ForegroundColor Green
        return $true
    } else {
        Write-Host "`n❌ La configuración no está completa" -ForegroundColor Red
        return $false
    }
}

# Mostrar próximos pasos
function Show-NextSteps {
    Write-Host ""
    Write-Host "🎉 CONFIGURACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host ""
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "📋 PRÓXIMOS PASOS:" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    # Verificar si .env necesita configuración
    if (Test-Path ".env") {
        $envContent = Get-Content ".env" -Raw
        if ($envContent -match "YOUR_|REPLACE_") {
            Write-Host "1. IMPORTANTE: Configura las variables en .env:" -ForegroundColor Yellow
            Write-Host "   - PROJECT_ENDPOINT"
            Write-Host "   - STORAGE_ACCOUNT_NAME"
            Write-Host "   - MODEL_DEPLOYMENT_NAME"
            Write-Host ""
        }
    }
    
    Write-Host "2. Ejecutar la aplicación:"
    Write-Host "   " -NoNewline
    Write-Host ".\run-local.bat" -ForegroundColor Cyan
    Write-Host " " -NoNewline
    Write-Host "       # Backend + Frontend" -ForegroundColor Gray
    Write-Host "   " -NoNewline
    Write-Host "make run-local" -ForegroundColor Cyan
    Write-Host " " -NoNewline
    Write-Host "        # Con Make (si está instalado)" -ForegroundColor Gray
    Write-Host "   " -NoNewline
    Write-Host "docker-compose up" -ForegroundColor Cyan
    Write-Host " " -NoNewline
    Write-Host "     # Con Docker" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Abrir en el navegador:"
    Write-Host "   Frontend: " -NoNewline
    Write-Host "http://localhost:7860" -ForegroundColor Cyan
    Write-Host "   Backend API: " -NoNewline
    Write-Host "http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "💡 COMANDOS ÚTILES:" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "• Verificar estado: " -NoNewline
    Write-Host "python setup-and-verify.py" -ForegroundColor Cyan
    Write-Host "• Ver logs: " -NoNewline
    Write-Host "Get-Content backend\backend.log -Tail 50 -Wait" -ForegroundColor Cyan
    Write-Host "• Ejecutar tests: " -NoNewline
    Write-Host "python tests\test_integration.py" -ForegroundColor Cyan
    Write-Host "• Provisionar Azure: " -NoNewline
    Write-Host ".\deploy-local-dev.ps1" -ForegroundColor Cyan
    Write-Host ""
}

# Main
function Main {
    Write-Host ""
    Write-Host "ℹ️  Este script configurará tu entorno de desarrollo local" -ForegroundColor Blue
    Write-Host "ℹ️  NO provisionará recursos en Azure" -ForegroundColor Blue
    Write-Host ""
    
    $response = Read-Host "¿Continuar? (s/n)"
    if ($response -ne 's') {
        Write-Host "⚠️  Setup cancelado" -ForegroundColor Yellow
        exit 1
    }
    
    # Ejecutar pasos
    Test-Prerequisites
    Setup-EnvFile
    Setup-VirtualEnvironments
    Install-Dependencies
    
    # Verificar
    if (Test-Setup) {
        Show-NextSteps
    } else {
        Write-Host "❌ Setup incompleto. Revisa los errores anteriores." -ForegroundColor Red
        exit 1
    }
}

# Ejecutar
Main
