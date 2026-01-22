"""
Centralized Ingestion Configuration
All paths relative to project root: Neo-Chatbot/
"""

from pathlib import Path

# Project root (Neo-Chatbot/)
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# ============================================================================
# DATA PATHS
# ============================================================================

# Main data directory (all static/source data)
DATA_DIR = PROJECT_ROOT / "data"

# Documents to ingest
DOCUMENTS_BASE_PATH = str(DATA_DIR / "documents")

# Document categories (folder -> category name for vector store)
DOCUMENT_CATEGORIES = {
    'manuals': 'technical_manuals',
    'proposals': 'project_proposals',
    'sops': 'standard_operating_procedures',
    'training_docs': 'training_documentation',
    '.': 'general_documentation'  # Root level documents
}

# Support CSV files
SUPPORT_LOGS_PATH = DATA_DIR / "support" / "support_logs"

# Database schema
SCHEMA_PATH = DATA_DIR / "database" / "schema.json"

# Vector store output
VECTOR_STORE_PATH = DATA_DIR / "vector_store.json"

# ============================================================================
# CODE INGESTION
# ============================================================================

# Enable/disable code ingestion
ENABLE_CODE_INGESTION = False  # Set to True to ingest code repositories

# Code repositories to ingest
CODE_REPOSITORIES = [
    # Example:
    # {
    #     'path': r'C:\path\to\your\codebase',
    #     'category': 'fleet-manager-code',
    #     'enabled': True
    # }
]

# ============================================================================
# INGESTION SETTINGS
# ============================================================================

# Embedding provider (openai, huggingface, local)
EMBEDDING_PROVIDER = "openai"  # Use OpenAI for consistent 1536-dim embeddings

# Chunk size for document splitting
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 200

# Skip already ingested files
SKIP_EXISTING = True

# Verbose logging
VERBOSE = True

# ============================================================================
# RLHF DATA
# ============================================================================

# RLHF learning data (feedback, patterns)
# Runtime writes: backend/app/data/rlhf/
# Backup/archive: data/rlhf/
RLHF_RUNTIME_PATH = PROJECT_ROOT / "backend" / "app" / "data" / "rlhf"
RLHF_BACKUP_PATH = DATA_DIR / "rlhf"

# ============================================================================
# VALIDATION
# ============================================================================

def validate_paths():
    """Validate that required paths exist"""
    print("\n📁 Validating paths...")
    
    issues = []
    
    # Check data directory
    if not DATA_DIR.exists():
        issues.append(f"❌ Data directory not found: {DATA_DIR}")
    else:
        print(f"✅ Data directory: {DATA_DIR}")
    
    # Check documents
    if not Path(DOCUMENTS_BASE_PATH).exists():
        issues.append(f"⚠️  Documents directory not found: {DOCUMENTS_BASE_PATH}")
    else:
        print(f"✅ Documents directory: {DOCUMENTS_BASE_PATH}")
    
    # Check support logs
    if not SUPPORT_LOGS_PATH.exists():
        issues.append(f"⚠️  Support logs not found: {SUPPORT_LOGS_PATH}")
    else:
        print(f"✅ Support logs: {SUPPORT_LOGS_PATH}")
    
    # Check RLHF paths
    if not RLHF_RUNTIME_PATH.exists():
        print(f"⚠️  RLHF runtime path not found (will be created): {RLHF_RUNTIME_PATH}")
        RLHF_RUNTIME_PATH.mkdir(parents=True, exist_ok=True)
    else:
        print(f"✅ RLHF runtime: {RLHF_RUNTIME_PATH}")
    
    if issues:
        print("\n⚠️  Issues found:")
        for issue in issues:
            print(f"   {issue}")
        print()
    else:
        print("\n✅ All paths validated!\n")
    
    return len(issues) == 0


if __name__ == "__main__":
    print("="*80)
    print("📋 INGESTION CONFIGURATION")
    print("="*80)
    print(f"\nProject root: {PROJECT_ROOT}")
    print(f"Data directory: {DATA_DIR}")
    print(f"Documents: {DOCUMENTS_BASE_PATH}")
    print(f"Vector store: {VECTOR_STORE_PATH}")
    print(f"Code ingestion: {'Enabled' if ENABLE_CODE_INGESTION else 'Disabled'}")
    
    validate_paths()
