"""
Configuration for Unified Ingestion System
Edit this file to customize what gets ingested
"""

# ============================================================================
# DOCUMENT INGESTION CONFIGURATION
# ============================================================================

# Base path where documents are stored
DOCUMENTS_BASE_PATH = r"C:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\documents"

# Document categories to ingest
# Format: "folder_path": "category_name"
# NOTE: Use "ROOT" (special key) for root-level files only (non-recursive)
DOCUMENT_CATEGORIES = {
    # Proposal documents
    "proposals/type-1": "proposals_sorting_conveyor",
    "proposals/type-2": "proposals_warehouse_automation",
    "proposals/type-3": "proposals_specialized_systems",
    
    # Technical documentation
    "support": "technical_support",
    "manuals": "technical_manuals",
    "specifications": "technical_specifications",
    "sops": "standard_operating_procedures",
    
    # Training materials — ALL subfolders explicitly listed to avoid duplication
    "training_docs/Training_Decks": "training_decks",
    "training_docs/Cross_belt_sorter_segment_wise_detailed_ppts": "training_cbs_detailed",
    "training_docs/sorter_modules_ppts_IT": "training_sorter_modules",
    "training_docs/Sorting_system_pdfs": "training_sorting_systems",
    
    # Root-level files ONLY (does NOT recurse into subfolders — no duplicates)
    "ROOT": "general_documentation",
}

# Maximum embeddings per OpenAI batch API call (OpenAI limit = 2048)
EMBEDDING_BATCH_SIZE = 64

# ============================================================================
# CODE INGESTION CONFIGURATION
# ============================================================================

# Enable/disable code ingestion
ENABLE_CODE_INGESTION = False  # Set to False - don't need C# code in chatbot

# Code repositories to ingest
# Each repository is a dictionary with:
#   - path: Full path to the codebase
#   - category: Category name for the code
#   - enabled: True to ingest, False to skip
CODE_REPOSITORIES = [
    {
        "path": r"C:\Users\Balmukund.Mishra\Desktop\neo-fleet-manager-noon-min-2.0",
        "category": "neo-fleet-manager-code",
        "description": "NEO Fleet Manager C# Application",
        "enabled": True
    },
    
    # Add more repositories here as needed
    # {
    #     "path": r"C:\path\to\another\codebase",
    #     "category": "another-project-code",
    #     "description": "Another Project",
    #     "enabled": False
    # },
]

# ============================================================================
# ADVANCED SETTINGS
# ============================================================================

# Chunk size for document splitting (characters)
CHUNK_SIZE = 1000

# Chunk overlap for context preservation (characters)
CHUNK_OVERLAP = 200

# Enable OCR for extracting text from images in PDFs
ENABLE_OCR = True

# Skip already ingested files (True = faster, False = re-ingest all)
SKIP_EXISTING = True

# Show detailed progress for large batches
VERBOSE_PROGRESS = True

# Maximum number of failed items to display in summary
MAX_FAILED_DISPLAY = 10
