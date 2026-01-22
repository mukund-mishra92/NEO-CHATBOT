"""
Complete Re-ingestion Script
Clears vector store and re-ingests all documents with consistent embeddings
"""

import sys
from pathlib import Path

# Add project root to path
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from backend.app.services.vector_store_service import VectorStoreService
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def main():
    """Clear vector store and re-ingest all data"""
    print("\n" + "="*80)
    print("🔄 COMPLETE RE-INGESTION SCRIPT")
    print("="*80)
    print("\n⚠️  WARNING: This will DELETE your existing vector store!")
    print("   All embeddings will be regenerated from source documents.")
    
    # Confirmation
    response = input("\n   Continue? (yes/no): ").strip().lower()
    if response not in ['yes', 'y']:
        print("\n❌ Cancelled by user\n")
        return
    
    # Step 1: Clear vector store
    print("\n" + "─"*80)
    print("📦 Step 1: Clearing old vector store...")
    print("─"*80)
    
    try:
        vs = VectorStoreService()
        old_count = len(vs.documents)
        vs.clear_store()
        print(f"✅ Cleared {old_count} old documents")
    except Exception as e:
        logger.error(f"❌ Error clearing vector store: {e}")
        return
    
    # Step 2: Run unified ingestion
    print("\n" + "─"*80)
    print("📥 Step 2: Re-ingesting all documents...")
    print("─"*80)
    print()
    
    try:
        from scripts.ingest_unified import main as ingest_main
        ingest_main()
    except Exception as e:
        logger.error(f"❌ Error during ingestion: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Step 3: Verify
    print("\n" + "─"*80)
    print("🔍 Step 3: Verifying vector store...")
    print("─"*80)
    
    try:
        vs_new = VectorStoreService()
        new_count = len(vs_new.documents)
        stats = vs_new.get_statistics()
        
        print(f"\n✅ Vector store rebuilt successfully!")
        print(f"   Total chunks: {new_count}")
        print(f"   Unique files: {stats.get('total_files', 'N/A')}")
        print(f"\n   Categories:")
        for cat, count in sorted(stats.get('categories', {}).items()):
            print(f"      • {cat}: {count}")
    except Exception as e:
        logger.warning(f"⚠️  Could not verify vector store: {e}")
    
    # Done
    print("\n" + "="*80)
    print("✅ RE-INGESTION COMPLETE!")
    print("="*80)
    print("\n💡 All documents now use consistent embeddings")
    print("   Restart your chatbot backend to use the new vector store.\n")
    print("   Command: cd backend && ..\\venv\\Scripts\\python -m uvicorn app.main:app --reload\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        print("   Vector store may be in inconsistent state - run again to complete\n")
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
