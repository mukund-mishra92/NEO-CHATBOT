from app.services.knowledge_base.vector_store_service import VectorStoreService

# Reuse the SAME embedding model used in vector store
_vector_store = VectorStoreService()

def generate_embedding(text: str):
    """
    Single embedding interface for entire system.
    Ensures schema + documents use same model.
    """
    return _vector_store.embed_query(text)