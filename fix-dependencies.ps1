# ================================================
# FIX PYTHON DEPENDENCIES
# ================================================

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "CORRIGIENDO DEPENDENCIAS DE PYTHON" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Función para reinstalar dependencias
function Fix-BackendDependencies {
    Write-Host "Reparando dependencias del Backend..." -ForegroundColor Yellow
    Write-Host "-------------------------------------" -ForegroundColor Yellow
    
    if (-not (Test-Path "backend\.venv")) {
        Write-Host "Creando entorno virtual del backend..." -ForegroundColor Yellow
        python -m venv backend\.venv
    }
    
    Write-Host "`nActualizando pip..." -ForegroundColor Cyan
    & backend\.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
    
    Write-Host "`nInstalando/Actualizando paquetes Azure AI..." -ForegroundColor Cyan
    
    # Instalar paquetes específicos con versiones que funcionan
    $packages = @(
        "azure-ai-projects==1.0.0b1",
        "azure-identity==1.17.1",
        "azure-storage-blob==12.22.0",
        "azure-core==1.30.2",
        "azure-ai-inference==1.0.0b5",
        "azure-ai-ml==1.0.0",
        "opentelemetry-api==1.25.0",
        "opentelemetry-sdk==1.25.0"
    )
    
    foreach ($package in $packages) {
        Write-Host "  Installing $package..." -ForegroundColor Gray
        & backend\.venv\Scripts\pip.exe install $package --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✅ $package installed" -ForegroundColor Green
        } else {
            Write-Host "    ⚠️ Issue with $package" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nInstalando resto de dependencias desde requirements.txt..." -ForegroundColor Cyan
    & backend\.venv\Scripts\pip.exe install -r backend\requirements.txt --quiet
    
    Write-Host "`nVerificando instalación..." -ForegroundColor Cyan
}

# Función para arreglar los imports en main.py
function Fix-MainPyImports {
    Write-Host "`nVerificando imports en main.py..." -ForegroundColor Yellow
    
    $mainPyPath = "backend\main.py"
    if (Test-Path $mainPyPath) {
        $content = Get-Content $mainPyPath -Raw
        
        # Verificar si usa el import incorrecto
        if ($content -match "from azure\.ai\.agents\.models import CodeInterpreterTool") {
            Write-Host "Corrigiendo import de CodeInterpreterTool..." -ForegroundColor Yellow
            
            # Hacer backup
            Copy-Item $mainPyPath "$mainPyPath.backup" -Force
            
            # Reemplazar el import incorrecto
            $content = $content -replace "from azure\.ai\.agents\.models import CodeInterpreterTool", "from azure.ai.projects.models import CodeInterpreterTool"
            
            # Guardar el archivo corregido
            $content | Out-File -FilePath $mainPyPath -Encoding UTF8 -NoNewline
            
            Write-Host "✅ Import corregido en main.py" -ForegroundColor Green
            Write-Host "   Backup guardado en main.py.backup" -ForegroundColor Gray
        } else {
            Write-Host "✅ Los imports en main.py parecen estar correctos" -ForegroundColor Green
        }
    }
}

# Función para verificar que todo funciona
function Test-BackendImports {
    Write-Host "`nProbando imports del backend..." -ForegroundColor Yellow
    
    $testScript = @"
print("Verificando imports críticos...")

try:
    from azure.ai.projects import AIProjectClient
    print("✅ AIProjectClient - OK")
except ImportError as e:
    print(f"❌ AIProjectClient - ERROR: {e}")
    exit(1)

try:
    from azure.ai.projects.models import AgentThread
    print("✅ AgentThread - OK")
except ImportError as e:
    print(f"❌ AgentThread - ERROR: {e}")
    exit(1)

try:
    # Primero intentar el import correcto
    from azure.ai.projects.models import CodeInterpreterTool
    print("✅ CodeInterpreterTool - OK (desde azure.ai.projects.models)")
except ImportError:
    try:
        # Si falla, intentar el alternativo
        from azure.ai.agents.models import CodeInterpreterTool
        print("⚠️ CodeInterpreterTool - OK (desde azure.ai.agents.models)")
    except ImportError as e:
        print(f"❌ CodeInterpreterTool - ERROR: {e}")
        exit(1)

try:
    from azure.identity import DefaultAzureCredential
    print("✅ DefaultAzureCredential - OK")
except ImportError as e:
    print(f"❌ DefaultAzureCredential - ERROR: {e}")
    exit(1)

try:
    from azure.storage.blob import BlobServiceClient
    print("✅ BlobServiceClient - OK")
except ImportError as e:
    print(f"❌ BlobServiceClient - ERROR: {e}")
    exit(1)

print("\n✅ Todos los imports funcionan correctamente!")
"@
    
    $result = $testScript | & backend\.venv\Scripts\python.exe
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Backend listo para ejecutar!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "`n❌ Aún hay problemas con las dependencias" -ForegroundColor Red
        return $false
    }
}

# Main
Write-Host "Este script va a:" -ForegroundColor Blue
Write-Host "  1. Reinstalar las dependencias de Azure AI" -ForegroundColor White
Write-Host "  2. Corregir los imports en main.py si es necesario" -ForegroundColor White
Write-Host "  3. Verificar que todo funcione" -ForegroundColor White
Write-Host ""

$continue = Read-Host "¿Continuar? (s/n)"
if ($continue -ne 's') {
    Write-Host "Operación cancelada" -ForegroundColor Yellow
    exit
}

# Ejecutar las correcciones
Fix-BackendDependencies
Fix-MainPyImports
$success = Test-BackendImports

if ($success) {
    Write-Host "`n================================================" -ForegroundColor Green
    Write-Host "✅ DEPENDENCIAS CORREGIDAS EXITOSAMENTE" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ahora puedes ejecutar:" -ForegroundColor Yellow
    Write-Host "  .\run-local.bat" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "`n================================================" -ForegroundColor Red
    Write-Host "❌ AÚN HAY PROBLEMAS" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Intenta:" -ForegroundColor Yellow
    Write-Host "  1. Eliminar el venv: Remove-Item -Recurse -Force backend\.venv" -ForegroundColor White
    Write-Host "  2. Volver a ejecutar este script" -ForegroundColor White
    Write-Host ""
}