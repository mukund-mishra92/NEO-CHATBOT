"""Quick test to check vector store contents"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from app.modules.neo_chatbot.services.vector_store_service import VectorStoreService

vs = VectorStoreService()
print(f"Total documents in vector store: {len(vs.documents)}")

if vs.documents:
    print("\nFirst 3 documents:")
    for i, doc in enumerate(vs.documents[:3], 1):
        print(f"{i}. {doc['metadata']['filename']} - {doc['metadata']['category']}")
        print(f"   Content preview: {doc['content'][:100]}...")
        print()
