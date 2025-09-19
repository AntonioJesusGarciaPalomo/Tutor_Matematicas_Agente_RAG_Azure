# ================================================
# VERIFY AND FIX PYTHON DEPENDENCIES
# ================================================

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "VERIFICANDO DEPENDENCIAS DE PYTHON" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar backend dependencies
Write-Host "BACKEND DEPENDENCIES:" -ForegroundColor Yellow
Write-Host "--------------------" -ForegroundColor Yellow

if (Test-Path "backend\.venv\Scripts\activate") {
    Write-Host "Activando entorno virtual del backend..." -ForegroundColor Gray
    
    # Listar paquetes instalados relacionados con Azure
    Write-Host "`nPaquetes Azure instalados:" -ForegroundColor Cyan
    & backend\.venv\Scripts\python.exe -m pip list | Select-String "azure"
    
    Write-Host "`nVerificando módulos críticos:" -ForegroundColor Cyan
    
    # Verificar cada módulo crítico
    $modules = @(
        "azure.ai.projects",
        "azure.ai.agents",
        "azure.identity",
        "azure.storage.blob"
    )
    
    foreach ($module in $modules) {
        & backend\.venv\Scripts\python.exe -c "import $module; print('✅ $module - OK')" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ $module - NO ENCONTRADO" -ForegroundColor Red
        }
    }
    
    Write-Host "`nIntentando importar los módulos del proyecto:" -ForegroundColor Cyan
    $testScript = @"
import sys
print(f"Python: {sys.version}")
print(f"Path: {sys.executable}")
print("\nIntentando importar módulos...")

try:
    from azure.ai.projects import AIProjectClient
    print("✅ azure.ai.projects.AIProjectClient - OK")
except ImportError as e:
    print(f"❌ azure.ai.projects.AIProjectClient - ERROR: {e}")

try:
    from azure.ai.projects.models import AgentThread
    print("✅ azure.ai.projects.models.AgentThread - OK")
except ImportError as e:
    print(f"❌ azure.ai.projects.models.AgentThread - ERROR: {e}")

try:
    from azure.ai.agents.models import CodeInterpreterTool
    print("✅ azure.ai.agents.models.CodeInterpreterTool - OK")
except ImportError as e:
    print(f"❌ azure.ai.agents.models.CodeInterpreterTool - ERROR: {e}")
    print("   Intentando alternativa...")
    try:
        from azure.ai.projects.models import CodeInterpreterTool
        print("   ✅ azure.ai.projects.models.CodeInterpreterTool - OK (ALTERNATIVA)")
    except ImportError as e2:
        print(f"   ❌ azure.ai.projects.models.CodeInterpreterTool - ERROR: {e2}")

try:
    from azure.identity import DefaultAzureCredential
    print("✅ azure.identity.DefaultAzureCredential - OK")
except ImportError as e:
    print(f"❌ azure.identity.DefaultAzureCredential - ERROR: {e}")

try:
    from azure.storage.blob import BlobServiceClient
    print("✅ azure.storage.blob.BlobServiceClient - OK")
except ImportError as e:
    print(f"❌ azure.storage.blob.BlobServiceClient - ERROR: {e}")
"@
    
    $testScript | & backend\.venv\Scripts\python.exe
    
} else {
    Write-Host "❌ No se encontró el entorno virtual del backend" -ForegroundColor Red
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "VERIFICANDO requirements.txt" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if (Test-Path "backend\requirements.txt") {
    Write-Host "`nContenido actual de backend\requirements.txt:" -ForegroundColor Yellow
    Get-Content "backend\requirements.txt" | ForEach-Object {
        if ($_ -like "*azure*") {
            Write-Host "  $_" -ForegroundColor Cyan
        } else {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "❌ backend\requirements.txt no encontrado" -ForegroundColor Red
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "¿NECESITAS REPARAR LAS DEPENDENCIAS?" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Si ves errores arriba, ejecuta:" -ForegroundColor Yellow
Write-Host "  .\fix-dependencies.ps1" -ForegroundColor Cyan
Write-Host ""