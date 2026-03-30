"""
NEO Chatbot Configuration
Environment-based configuration for the chatbot application
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Base directory - project root (Neo-Chatbot/)
BASE_DIR = Path(__file__).parent.parent.parent.parent
BACKEND_DIR = Path(__file__).parent.parent.parent

class Settings:
    """Application Settings"""
    
    # Application Info
    APP_NAME: str = "NEO Chatbot"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"
    
    # Database Configuration
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", "3306"))
    DB_USER: str = os.getenv("DB_USER", "root")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "root")
    DB_NAME: str = os.getenv("DB_NAME", "neo")
    
    # Multi-Tenant Configuration
    MULTI_TENANT_ENABLED: bool = os.getenv("MULTI_TENANT_ENABLED", "true").lower() == "true"
    TENANT_COLUMN: str = os.getenv("TENANT_COLUMN", "host_location")
    DEFAULT_TENANT: str = os.getenv("DEFAULT_TENANT", "frk")
    TENANT_EXTRACTION_THRESHOLD: float = float(os.getenv("TENANT_EXTRACTION_THRESHOLD", "0.65"))
    TENANT_DEFAULT_BEHAVIOR: str = os.getenv("TENANT_DEFAULT_BEHAVIOR", "smart_aggregate")  # Options: default_only, smart_aggregate, all_sites
    
    # Data Paths
    DATA_DIR: Path = BASE_DIR / "data"
    DOCUMENTS_DIR: Path = DATA_DIR / "documents"
    DATABASE_DIR: Path = DATA_DIR / "database"
    SUPPORT_DIR: Path = DATA_DIR / "support"
    MODELS_DIR: Path = DATA_DIR / "models"
    RLHF_DIR: Path = DATA_DIR / "rlhf"
    EMBEDDINGS_DIR: Path = DATA_DIR / "embeddings"
    VECTOR_STORE_PATH: Path = DATA_DIR / "vector_store.json"
    
    # LLM Configuration
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", os.getenv("GROK_API_KEY", ""))
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    HUGGINGFACE_API_KEY: str = os.getenv("HUGGINGFACE_API_KEY", os.getenv("HF_TOKEN", ""))
    
    # Local LLM Configuration (Fallback)
    LOCAL_LLM_ENABLED: bool = os.getenv("LOCAL_LLM_ENABLED", "true").lower() == "true"
    LOCAL_LLM_MODEL: str = os.getenv("LOCAL_LLM_MODEL", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")
    LOCAL_LLM_MAX_TOKENS: int = int(os.getenv("LOCAL_LLM_MAX_TOKENS", "500"))
    LOCAL_LLM_TEMPERATURE: float = float(os.getenv("LOCAL_LLM_TEMPERATURE", "0.3"))
    
    # Agentic AI Configuration (Multi-Agent System)
    AGENTIC_MODE_ENABLED: bool = os.getenv("AGENTIC_MODE_ENABLED", "true").lower() == "true"
    AGENTIC_VERIFICATION_THRESHOLD: int = int(os.getenv("AGENTIC_VERIFICATION_THRESHOLD", "100"))
    AGENTIC_MAX_ITERATIONS: int = int(os.getenv("AGENTIC_MAX_ITERATIONS", "1"))  # Max retry loops (default 1)
    AGENTIC_TIMEOUT_SECONDS: int = int(os.getenv("AGENTIC_TIMEOUT_SECONDS", "60"))  # Max execution time
    
    # Vector Store Configuration
    EMBEDDING_MODEL: str = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
    CHUNK_SIZE: int = int(os.getenv("CHUNK_SIZE", "1000"))
    CHUNK_OVERLAP: int = int(os.getenv("CHUNK_OVERLAP", "200"))
    TOP_K_RESULTS: int = int(os.getenv("TOP_K_RESULTS", "5"))
    
    # Logging
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_FILE: Path = BASE_DIR / "logs" / "chatbot.log"
    
    # CORS
    CORS_ORIGINS: list = os.getenv("CORS_ORIGINS", "*").split(",")
    
    # Server Configuration
    SERVER_HOST: str = os.getenv("SERVER_HOST", "0.0.0.0")
    SERVER_PORT: int = int(os.getenv("SERVER_PORT", "8000"))
    SERVER_RELOAD: bool = os.getenv("SERVER_RELOAD", "true").lower() == "true"

# Create settings instance
settings = Settings()

# Create necessary directories
settings.DATA_DIR.mkdir(exist_ok=True)
settings.DOCUMENTS_DIR.mkdir(exist_ok=True)
settings.DATABASE_DIR.mkdir(exist_ok=True)
settings.SUPPORT_DIR.mkdir(exist_ok=True)
settings.MODELS_DIR.mkdir(exist_ok=True)
settings.RLHF_DIR.mkdir(exist_ok=True)
settings.EMBEDDINGS_DIR.mkdir(exist_ok=True)
(BASE_DIR / "logs").mkdir(exist_ok=True)
