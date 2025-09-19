#!/usr/bin/env python3
"""
Script para verificar qué clases y métodos están disponibles en el SDK actual
"""

import sys
import importlib

print("="*60)
print("VERIFICANDO ESTRUCTURA DEL SDK AZURE AI")
print("="*60)

# Verificar azure.ai.projects
try:
    import azure.ai.projects
    print("\n✅ azure.ai.projects importado correctamente")
    print(f"   Versión: {azure.ai.projects.__version__ if hasattr(azure.ai.projects, '__version__') else 'N/A'}")
except ImportError as e:
    print(f"\n❌ Error importando azure.ai.projects: {e}")
    sys.exit(1)

# Verificar AIProjectClient
try:
    from azure.ai.projects import AIProjectClient
    print("✅ AIProjectClient disponible")
except ImportError as e:
    print(f"❌ AIProjectClient no encontrado: {e}")

# Verificar qué hay en models
print("\n📦 Explorando azure.ai.projects.models:")
print("-" * 40)
try:
    import azure.ai.projects.models as models
    available_classes = [item for item in dir(models) if not item.startswith('_')]
    print(f"Clases disponibles ({len(available_classes)}):")
    
    # Buscar clases relevantes
    relevant_keywords = ['Agent', 'Thread', 'Code', 'Tool', 'Message', 'Run']
    for keyword in relevant_keywords:
        matching = [c for c in available_classes if keyword in c]
        if matching:
            print(f"\n  {keyword}:")
            for cls in matching:
                print(f"    - {cls}")
except ImportError as e:
    print(f"❌ Error explorando models: {e}")

# Verificar azure.ai.agents
print("\n📦 Explorando azure.ai.agents:")
print("-" * 40)
try:
    import azure.ai.agents
    print("✅ azure.ai.agents existe como módulo")
    
    # Verificar models
    try:
        import azure.ai.agents.models as agent_models
        agent_classes = [item for item in dir(agent_models) if not item.startswith('_')]
        print(f"Clases en azure.ai.agents.models: {len(agent_classes)}")
        
        # Buscar CodeInterpreterTool
        if 'CodeInterpreterTool' in agent_classes:
            print("  ✅ CodeInterpreterTool encontrado en azure.ai.agents.models")
        else:
            print("  ❌ CodeInterpreterTool NO encontrado en azure.ai.agents.models")
            
    except ImportError as e:
        print(f"  ❌ azure.ai.agents.models no accesible: {e}")
        
except ImportError:
    print("❌ azure.ai.agents NO existe como módulo separado")

# Verificar la estructura del cliente
print("\n🔍 Verificando estructura del AIProjectClient:")
print("-" * 40)
try:
    from azure.ai.projects import AIProjectClient
    
    # Ver métodos disponibles
    client_attrs = [attr for attr in dir(AIProjectClient) if not attr.startswith('_')]
    
    # Buscar atributos relacionados con agents
    agent_related = [attr for attr in client_attrs if 'agent' in attr.lower()]
    if agent_related:
        print("Atributos relacionados con agents:")
        for attr in agent_related:
            print(f"  - {attr}")
            
except Exception as e:
    print(f"Error verificando AIProjectClient: {e}")

# Ejemplo de uso correcto según lo encontrado
print("\n" + "="*60)
print("EJEMPLO DE USO BASADO EN LA ESTRUCTURA ACTUAL:")
print("="*60)

code_example = """
# Basándome en la estructura encontrada, el código debería ser similar a:

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

# Si CodeInterpreterTool está en projects.models:
try:
    from azure.ai.projects.models import CodeInterpreterTool
except ImportError:
    # Si está en agents.models:
    from azure.ai.agents.models import CodeInterpreterTool

project_client = AIProjectClient(
    endpoint=project_endpoint,
    credential=DefaultAzureCredential(),
)

# El resto depende de la estructura exacta del SDK...
# Usa project_client.agents para acceder a las operaciones de agentes
"""

print(code_example)