"""
Configuración de autenticación para Azure AI Foundry
Maneja diferentes escenarios de autenticación para desarrollo local y producción
"""
import os
import logging
from typing import Optional
from azure.identity import (
    DefaultAzureCredential,
    ChainedTokenCredential,
    AzureCliCredential,
    ManagedIdentityCredential,
    InteractiveBrowserCredential,
    ClientSecretCredential,
    EnvironmentCredential
)

logger = logging.getLogger(__name__)

class AzureAuthConfig:
    """Gestiona la configuración de autenticación para Azure"""
    
    @staticmethod
    def get_credential():
        """
        Obtiene las credenciales apropiadas según el entorno.
        
        Prioridad:
        1. Service Principal (si están configuradas las variables)
        2. Azure CLI (para desarrollo local)
        3. Interactive Browser (si Azure CLI no está disponible)
        4. Managed Identity (para Azure)
        5. DefaultAzureCredential (fallback)
        """
        
        # Detectar entorno
        is_local = os.environ.get("AZURE_CLIENT_ID") is None or os.environ.get("ENVIRONMENT", "local") == "local"
        
        try:
            if is_local:
                logger.info("Configurando autenticación para desarrollo local")
                
                # Intentar primero con Service Principal si está configurado
                client_id = os.environ.get("AZURE_CLIENT_ID")
                client_secret = os.environ.get("AZURE_CLIENT_SECRET")
                tenant_id = os.environ.get("AZURE_TENANT_ID")
                
                if all([client_id, client_secret, tenant_id]):
                    logger.info("Usando Service Principal para autenticación")
                    return ClientSecretCredential(
                        tenant_id=tenant_id,
                        client_id=client_id,
                        client_secret=client_secret
                    )
                
                # Para desarrollo local, usar Azure CLI como primera opción
                credential_chain = []
                
                # 1. Azure CLI (más común para desarrollo)
                try:
                    azure_cli_cred = AzureCliCredential()
                    # Verificar que funciona
                    token = azure_cli_cred.get_token("https://management.azure.com/.default")
                    if token:
                        logger.info("✅ Usando Azure CLI credential")
                        return azure_cli_cred
                except Exception as e:
                    logger.warning(f"Azure CLI no disponible: {e}")
                    credential_chain.append(AzureCliCredential())
                
                # 2. Interactive Browser como fallback
                credential_chain.append(InteractiveBrowserCredential())
                
                # 3. Environment variables si están configuradas
                credential_chain.append(EnvironmentCredential())
                
                credential = ChainedTokenCredential(*credential_chain)
                logger.info("Usando cadena de credenciales para desarrollo local")
                
            else:
                # En Azure, usar Managed Identity
                logger.info("Configurando autenticación para Azure (Managed Identity)")
                
                # Obtener el client_id si está configurado (para user-assigned identity)
                client_id = os.environ.get("AZURE_CLIENT_ID")
                
                if client_id:
                    credential = ManagedIdentityCredential(client_id=client_id)
                    logger.info(f"Usando User-Assigned Managed Identity: {client_id}")
                else:
                    credential = ChainedTokenCredential(
                        ManagedIdentityCredential(),
                        DefaultAzureCredential()
                    )
                    logger.info("Usando System-Assigned Managed Identity")
            
            # Verificar que la credencial funciona
            try:
                test_token = credential.get_token("https://management.azure.com/.default")
                if test_token:
                    logger.info("✅ Autenticación verificada correctamente")
                    return credential
            except Exception as e:
                logger.warning(f"No se pudo verificar la credencial: {e}")
                # Continuar de todos modos, puede funcionar para otros recursos
                return credential
                
        except Exception as e:
            logger.error(f"Error configurando credenciales: {e}")
            logger.info("Usando DefaultAzureCredential como fallback")
            return DefaultAzureCredential()
    
    @staticmethod
    def validate_credentials(credential) -> bool:
        """
        Valida que las credenciales funcionan correctamente
        
        Args:
            credential: Credencial de Azure a validar
            
        Returns:
            bool: True si las credenciales son válidas
        """
        try:
            # Intentar obtener un token para management
            token = credential.get_token("https://management.azure.com/.default")
            if token and token.token:
                logger.info("✅ Credenciales validadas exitosamente")
                return True
        except Exception as e:
            logger.error(f"❌ Error validando credenciales: {e}")
        
        return False
    
    @staticmethod
    def get_auth_info() -> dict:
        """
        Obtiene información sobre el método de autenticación actual
        
        Returns:
            dict: Información sobre la autenticación
        """
        info = {
            "environment": os.environ.get("ENVIRONMENT", "local"),
            "has_service_principal": bool(os.environ.get("AZURE_CLIENT_ID")),
            "has_azure_cli": False,
            "auth_method": "unknown"
        }
        
        # Verificar Azure CLI
        try:
            cli_cred = AzureCliCredential()
            token = cli_cred.get_token("https://management.azure.com/.default")
            if token:
                info["has_azure_cli"] = True
                info["auth_method"] = "Azure CLI"
        except:
            pass
        
        # Determinar método principal
        if info["has_service_principal"]:
            info["auth_method"] = "Service Principal"
        elif info["environment"] != "local":
            info["auth_method"] = "Managed Identity"
        elif not info["has_azure_cli"]:
            info["auth_method"] = "Interactive Browser"
        
        return info

# Función helper para configuración rápida
def setup_local_auth():
    """
    Configura la autenticación para desarrollo local
    Útil para scripts de inicialización
    """
    import subprocess
    
    logger.info("Configurando autenticación para desarrollo local...")
    
    # Verificar si ya está autenticado con Azure CLI
    try:
        result = subprocess.run(
            ["az", "account", "show"],
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.info("No autenticado con Azure CLI. Ejecutando 'az login'...")
            subprocess.run(["az", "login"], check=True)
        else:
            import json
            account = json.loads(result.stdout)
            logger.info(f"✅ Autenticado con Azure CLI como: {account.get('user', {}).get('name', 'Unknown')}")
            logger.info(f"   Suscripción: {account.get('name', 'Unknown')}")
    
    except FileNotFoundError:
        logger.error("❌ Azure CLI no está instalado. Por favor instálalo primero.")
        logger.info("   Visita: https://docs.microsoft.com/cli/azure/install-azure-cli")
        return False
    except Exception as e:
        logger.error(f"Error configurando autenticación: {e}")
        return False
    
    return True

if __name__ == "__main__":
    # Test de configuración
    logging.basicConfig(level=logging.INFO)
    
    print("🔐 Probando configuración de autenticación...")
    print("=" * 50)
    
    # Obtener información de autenticación
    auth_info = AzureAuthConfig.get_auth_info()
    print(f"Entorno: {auth_info['environment']}")
    print(f"Método de autenticación: {auth_info['auth_method']}")
    print(f"Service Principal configurado: {auth_info['has_service_principal']}")
    print(f"Azure CLI disponible: {auth_info['has_azure_cli']}")
    
    # Obtener credencial
    credential = AzureAuthConfig.get_credential()
    
    # Validar
    if AzureAuthConfig.validate_credentials(credential):
        print("✅ Autenticación configurada correctamente")
    else:
        print("❌ Error en la configuración de autenticación")
        print("\nPosibles soluciones:")
        print("1. Ejecuta: az login")
        print("2. Configura las variables AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID")
        print("3. Verifica que tienes permisos en la suscripción de Azure")