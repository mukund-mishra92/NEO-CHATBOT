"""
Vector Store Service - Storage and search for document embeddings
Uses simple file-based storage (can be upgraded to Pinecone/Weaviate/ChromaDB later)
"""

import os
import json
import logging
from typing import List, Dict, Any, Optional
import numpy as np
from pathlib import Path

logger = logging.getLogger(__name__)


class VectorStoreService:
    """
    Service for storing and searching document vectors
    Supports semantic search using cosine similarity
    """
    
    def __init__(self, storage_path: Optional[str] = None):
        """Initialize vector store"""
        if storage_path is None:
            # Go up to project root: backend/app -> backend -> root
            base_path = Path(__file__).parent.parent.parent.parent / "data"
            storage_path = str(base_path / "vector_store.json")
        
        self.storage_path = storage_path
        self.documents: List[Dict[str, Any]] = []
        self.load_store()
        logger.info(f"✅ Vector store initialized with {len(self.documents)} documents")
    
    def load_store(self):
        """Load vector store from disk"""
        try:
            if os.path.exists(self.storage_path):
                with open(self.storage_path, 'r', encoding='utf-8') as f:
                    self.documents = json.load(f)
                logger.info(f"📂 Loaded {len(self.documents)} documents from vector store")
            else:
                logger.info("📂 No existing vector store found - starting fresh")
                self.documents = []
        except Exception as e:
            logger.error(f"❌ Error loading vector store: {e}")
            self.documents = []
    
    def save_store(self):
        """Save vector store to disk"""
        try:
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
            
            # Convert numpy types to Python types for JSON serialization
            serializable_documents = []
            for doc in self.documents:
                serializable_doc = {
                    "id": doc["id"],
                    "content": doc["content"],
                    "embedding": [float(x) for x in doc["embedding"]],  # Convert numpy.float32 to Python float
                    "metadata": doc["metadata"]
                }
                serializable_documents.append(serializable_doc)
            
            with open(self.storage_path, 'w', encoding='utf-8') as f:
                json.dump(serializable_documents, f, indent=2)
            logger.info(f"💾 Saved {len(self.documents)} documents to vector store")
        except Exception as e:
            logger.error(f"❌ Error saving vector store: {e}")
    
    def add_document(
        self,
        document_id: str,
        content: str,
        embedding: List[float],
        metadata: Dict[str, Any]
    ):
        """
        Add document to vector store
        
        Args:
            document_id: Unique document identifier
            content: Document text content
            embedding: Vector embedding of the content
            metadata: Additional metadata (filename, type, category, etc.)
        """
        document = {
            "id": document_id,
            "content": content,
            "embedding": embedding,
            "metadata": metadata
        }
        
        # Check if document already exists
        existing_index = next((i for i, doc in enumerate(self.documents) if doc["id"] == document_id), None)
        
        if existing_index is not None:
            self.documents[existing_index] = document
            logger.info(f"📝 Updated document: {document_id}")
        else:
            self.documents.append(document)
            logger.info(f"➕ Added new document: {document_id}")
        
        self.save_store()
    
    def add_documents_batch(self, documents: List[Dict[str, Any]]):
        """
        Add multiple documents at once (more efficient)
        
        Args:
            documents: List of document dicts with id, content, embedding, metadata
        """
        for doc in documents:
            existing_index = next((i for i, d in enumerate(self.documents) if d["id"] == doc["id"]), None)
            if existing_index is not None:
                self.documents[existing_index] = doc
            else:
                self.documents.append(doc)
        
        self.save_store()
        logger.info(f"➕ Added/updated {len(documents)} documents in batch")
    
    def search(
        self,
        query_embedding: List[float],
        top_k: int = 5,
        filter_metadata: Optional[Dict[str, Any]] = None,
        min_similarity: float = 0.0
    ) -> List[Dict[str, Any]]:
        """
        Search for similar documents using cosine similarity
        
        Args:
            query_embedding: Vector embedding of the query
            top_k: Number of results to return
            filter_metadata: Optional metadata filters (e.g., {"category": "documentation"})
            min_similarity: Minimum similarity score (0.0 to 1.0)
            
        Returns:
            List of matching documents with similarity scores
        """
        if not self.documents:
            logger.warning("⚠️ Vector store is empty - no documents to search")
            return []
        
        # Filter documents by metadata if provided
        filtered_docs = self.documents
        if filter_metadata:
            filtered_docs = [
                doc for doc in self.documents
                if all(doc["metadata"].get(k) == v for k, v in filter_metadata.items())
            ]
        
        if not filtered_docs:
            logger.warning(f"⚠️ No documents match filter: {filter_metadata}")
            return []
        
        # Calculate cosine similarity for each document
        query_vec = np.array(query_embedding)
        query_dim = len(query_vec)
        similarities = []
        
        # Detect embedding dimension mismatch
        if filtered_docs:
            first_doc_dim = len(filtered_docs[0]["embedding"])
            if first_doc_dim != query_dim:
                logger.error(
                    f"❌ EMBEDDING DIMENSION MISMATCH: Query has {query_dim} dimensions, "
                    f"but documents have {first_doc_dim} dimensions. "
                    f"This indicates documents were ingested with a different embedding model. "
                    f"Please re-ingest documents using the current embedding model."
                )
                # Return empty results instead of crashing
                return []
        
        for doc in filtered_docs:
            try:
                doc_vec = np.array(doc["embedding"])
                doc_dim = len(doc_vec)
                
                # Skip documents with mismatched dimensions
                if doc_dim != query_dim:
                    logger.warning(
                        f"⚠️ Skipping doc {doc.get('id', 'unknown')}: "
                        f"dimension mismatch (query: {query_dim}, doc: {doc_dim})"
                    )
                    continue
                
                # Cosine similarity
                similarity = np.dot(query_vec, doc_vec) / (np.linalg.norm(query_vec) * np.linalg.norm(doc_vec))
                
                # Only include if above minimum threshold
                if similarity >= min_similarity:
                    similarities.append({
                        "document": doc,
                        "similarity": float(similarity)
                    })
            except Exception as e:
                logger.error(f"❌ Error calculating similarity for doc {doc.get('id', 'unknown')}: {e}")
                continue
        
        # Sort by similarity (highest first)
        similarities.sort(key=lambda x: x["similarity"], reverse=True)
        
        # Return top K results
        return similarities[:top_k]
    
    def search_balanced(
        self,
        query_embedding: List[float],
        top_k: int = 5,
        filter_metadata: Optional[Dict[str, Any]] = None,
        min_similarity: float = 0.0,
        diversify: bool = True
    ) -> List[Dict[str, Any]]:
        """
        Balanced search that reduces category bias
        
        Args:
            query_embedding: Vector embedding of the query
            top_k: Number of results to return
            filter_metadata: Optional metadata filters
            min_similarity: Minimum similarity score
            diversify: If True, ensures diverse categories in results
            
        Returns:
            List of matching documents with balanced category representation
        """
        if not self.documents:
            logger.warning("⚠️ Vector store is empty - no documents to search")
            return []
        
        # Get all results first
        all_results = self.search(
            query_embedding=query_embedding,
            top_k=top_k * 3,  # Get more results for diversity
            filter_metadata=filter_metadata,
            min_similarity=min_similarity
        )
        
        if not all_results or not diversify:
            return all_results[:top_k]
        
        # Group by category
        category_buckets = {}
        for result in all_results:
            category = result["document"]["metadata"].get("category", "unknown")
            if category not in category_buckets:
                category_buckets[category] = []
            category_buckets[category].append(result)
        
        # Prioritize non-proposal documents
        priority_categories = [
            "training_materials",
            "technical_support", 
            "technical_manuals",
            "standard_operating_procedures",
            "general_documentation"
        ]
        proposal_categories = [
            "proposals_sorting_conveyor",
            "proposals_warehouse_automation", 
            "proposals_specialized_systems"
        ]
        
        balanced_results = []
        categories_used = set()
        
        # Phase 1: Get top result from each priority category
        for category in priority_categories:
            if category in category_buckets and len(balanced_results) < top_k:
                balanced_results.append(category_buckets[category][0])
                categories_used.add(category)
        
        # Phase 2: Add diverse results from remaining categories
        remaining_results = [
            r for r in all_results 
            if r["document"]["metadata"].get("category") not in categories_used
        ]
        
        for result in remaining_results:
            if len(balanced_results) >= top_k:
                break
            category = result["document"]["metadata"].get("category", "unknown")
            # Limit proposals to max 40% of results
            proposal_count = sum(1 for r in balanced_results 
                               if r["document"]["metadata"].get("category") in proposal_categories)
            if category in proposal_categories and proposal_count >= max(1, int(top_k * 0.4)):
                continue
            balanced_results.append(result)
            categories_used.add(category)
        
        # Phase 3: Fill remaining slots with best matches
        if len(balanced_results) < top_k:
            for result in all_results:
                if len(balanced_results) >= top_k:
                    break
                if result not in balanced_results:
                    balanced_results.append(result)
        
        logger.info(f"📊 Balanced search: {len(balanced_results)} results from {len(categories_used)} categories")
        return balanced_results[:top_k]
    
    def delete_document(self, document_id: str) -> bool:
        """Delete document from vector store"""
        initial_count = len(self.documents)
        self.documents = [doc for doc in self.documents if doc["id"] != document_id]
        
        if len(self.documents) < initial_count:
            self.save_store()
            logger.info(f"🗑️ Deleted document: {document_id}")
            return True
        else:
            logger.warning(f"⚠️ Document not found: {document_id}")
            return False
    
    def clear_store(self):
        """Clear all documents from vector store"""
        self.documents = []
        self.save_store()
        logger.info("🗑️ Cleared all documents from vector store")
    
    def get_document(self, document_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific document by ID"""
        for doc in self.documents:
            if doc["id"] == document_id:
                return doc
        return None
    
    def get_all_documents(self, category: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get all documents, optionally filtered by category"""
        if category:
            return [doc for doc in self.documents if doc["metadata"].get("category") == category]
        return self.documents.copy()
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get vector store statistics"""
        categories = {}
        for doc in self.documents:
            category = doc["metadata"].get("category", "unknown")
            categories[category] = categories.get(category, 0) + 1
        
        return {
            "total_documents": len(self.documents),
            "categories": categories,
            "storage_path": self.storage_path,
            "storage_size_bytes": os.path.getsize(self.storage_path) if os.path.exists(self.storage_path) else 0
        }

