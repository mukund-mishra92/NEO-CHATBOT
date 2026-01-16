"""
Quick script to clear and re-ingest all documents with consistent embeddings
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parent))

from app.modules.neo_chatbot.services.vector_store_service import VectorStoreService
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    """Clear vector store and re-ingest"""
    print("\n" + "="*80)
    print("🔄 RE-INGESTION SCRIPT")
    print("="*80)
    
    # Step 1: Clear vector store
    print("\n📦 Step 1: Clearing old vector store...")
    vs = VectorStoreService()
    old_count = len(vs.documents)
    vs.clear_store()
    print(f"✅ Cleared {old_count} old documents with mismatched embeddings")
    
    # Step 2: Run unified ingestion
    print("\n📥 Step 2: Re-ingesting all documents with OpenAI embeddings...")
    print("="*80)
    print()
    
    from ingest_unified import UnifiedIngestionSystem, main as ingest_main
    ingest_main()
    
    print("\n" + "="*80)
    print("✅ RE-INGESTION COMPLETE!")
    print("="*80)
    print("\n💡 All documents now use consistent 1536-dimension OpenAI embeddings")
    print("   Your chatbot queries will now work correctly!\n")

if __name__ == "__main__":
    main()
