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
    
    # Data Paths
    DATA_DIR: Path = BASE_DIR / "data"
    DOCUMENTS_DIR: Path = DATA_DIR / "documents"
    DATABASE_DIR: Path = DATA_DIR / "database"
    SUPPORT_DIR: Path = DATA_DIR / "support"
    MODELS_DIR: Path = DATA_DIR / "models"
    RLHF_DIR: Path = DATA_DIR / "rlhf"
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
    
    # SQL Assistant Configuration
    # Set to "gpt4" to use new GPT-4 multi-layer architecture
    # Set to "phase3" to use legacy semantic frame architecture
    SQL_ASSISTANT_MODE: str = os.getenv("SQL_ASSISTANT_MODE", "gpt4")  # "gpt4" or "phase3"

    # SQL Assistant Model Selection
    # Primary model for initial SQL generation
    SQL_ASSISTANT_PRIMARY_MODEL: str = os.getenv("SQL_ASSISTANT_PRIMARY_MODEL", "gpt-5.2")
    # Retry model for regeneration after validation failure (default: same as primary)
    SQL_ASSISTANT_RETRY_MODEL: str = os.getenv("SQL_ASSISTANT_RETRY_MODEL", SQL_ASSISTANT_PRIMARY_MODEL)

    # Determinism controls for SQL generation
    # Keep these low (0.0-0.2) for stable SQL output.
    SQL_ASSISTANT_PRIMARY_TEMPERATURE: float = float(os.getenv("SQL_ASSISTANT_PRIMARY_TEMPERATURE", "0.0"))
    SQL_ASSISTANT_RETRY_TEMPERATURE: float = float(os.getenv("SQL_ASSISTANT_RETRY_TEMPERATURE", "0.0"))

    # Extended thinking / reasoning mode for retries.
    # Supported values: "off", "extended" (maps to higher reasoning effort when supported by the OpenAI client).
    SQL_ASSISTANT_RETRY_THINKING_MODE: str = os.getenv("SQL_ASSISTANT_RETRY_THINKING_MODE", "extended")

    # Schema context sizing for SQL generation prompts
    SQL_ASSISTANT_SCHEMA_MAX_TABLES: int = int(os.getenv("SQL_ASSISTANT_SCHEMA_MAX_TABLES", "18"))
    SQL_ASSISTANT_SCHEMA_MAX_COLUMNS_PER_TABLE: int = int(
        os.getenv("SQL_ASSISTANT_SCHEMA_MAX_COLUMNS_PER_TABLE", "30")
    )
    LOCAL_LLM_TEMPERATURE: float = float(os.getenv("LOCAL_LLM_TEMPERATURE", "0.3"))
    
    # Agentic AI Configuration (Multi-Agent System)
    AGENTIC_MODE_ENABLED: bool = os.getenv("AGENTIC_MODE_ENABLED", "true").lower() == "true"
    AGENTIC_VERIFICATION_THRESHOLD: int = int(os.getenv("AGENTIC_VERIFICATION_THRESHOLD", "100"))
    
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
(BASE_DIR / "logs").mkdir(exist_ok=True)
