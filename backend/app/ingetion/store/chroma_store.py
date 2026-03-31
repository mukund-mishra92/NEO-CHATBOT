"""
ChromaDB Vector Store — Typed collections for hierarchical chunks.

Collections:
  • documents  — Level-0 summaries + Level-1 sections + Level-2 paragraphs
  • tables     — Extracted table content
  • images     — Image descriptions
  • slides     — PPT slide content

Each entry stores the chunk content, its embedding, and rich metadata
for parent/child traversal and citation generation.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..models import HierarchicalChunk, ImageReference, RetrievedChunk

logger = logging.getLogger(__name__)

# Defaults
DEFAULT_PERSIST_DIR = str(Path(__file__).resolve().parents[4] / "data" / "chroma_db")
EMBEDDING_DIM = 384  # bge-small-en-v1.5 / HuggingFace default


class ChromaStore:
    """Manage ChromaDB collections for the RAG pipeline."""

    COLLECTION_NAMES = ("documents", "tables", "images", "slides")

    def __init__(
        self,
        persist_directory: Optional[str] = None,
        embedding_function=None,
    ):
        """
        Args:
            persist_directory: Where ChromaDB stores data on disk.
            embedding_function: A chromadb-compatible embedding function.
                                If None, we create one from LLMService.
        """
        self.persist_dir = persist_directory or DEFAULT_PERSIST_DIR
        os.makedirs(self.persist_dir, exist_ok=True)

        self._client = None
        self._collections: Dict[str, Any] = {}
        self._embedding_fn = embedding_function
        self._init_chroma()

    # ────────────────────────────────────────────────────
    #  Initialization
    # ────────────────────────────────────────────────────
    def _init_chroma(self):
        """Initialize ChromaDB client and collections."""
        try:
            import chromadb
        except ImportError:
            logger.error("chromadb not installed — run: pip install chromadb")
            raise

        # chromadb >= 1.x uses PersistentClient directly
        try:
            self._client = chromadb.PersistentClient(
                path=self.persist_dir,
            )
        except Exception:
            # Fallback for even newer or older APIs
            self._client = chromadb.Client()

        # Create / get collections
        for name in self.COLLECTION_NAMES:
            try:
                if self._embedding_fn:
                    self._collections[name] = self._client.get_or_create_collection(
                        name=name,
                        embedding_function=self._embedding_fn,
                        metadata={"hnsw:space": "cosine"},
                    )
                else:
                    self._collections[name] = self._client.get_or_create_collection(
                        name=name,
                        metadata={"hnsw:space": "cosine"},
                    )
            except Exception as exc:
                logger.error(f"Failed to create collection '{name}': {exc}")
                raise

        counts = {n: c.count() for n, c in self._collections.items()}
        logger.info(f"✅ ChromaDB initialized at {self.persist_dir} — counts: {counts}")

    # ────────────────────────────────────────────────────
    #  Cleanup
    # ────────────────────────────────────────────────────
    def close(self):
        """Release ChromaDB resources (file handles / SQLite locks)."""
        try:
            if self._client is not None:
                # PersistentClient may expose a close or _close method
                if hasattr(self._client, 'close'):
                    self._client.close()
                # Reset references so GC can collect
                self._client = None
                self._collections.clear()
                logger.info("ChromaDB client closed.")
        except Exception as exc:
            logger.warning(f"Error closing ChromaDB client: {exc}")

    # ────────────────────────────────────────────────────
    #  Add chunks
    # ────────────────────────────────────────────────────
    def add_chunks(
        self,
        chunks: List[HierarchicalChunk],
        embeddings: List[List[float]],
        collection_name: str = "documents",
    ) -> int:
        """
        Upsert a batch of chunks with their pre-computed embeddings.

        Returns:
            Number of chunks added.
        """
        col = self._collections.get(collection_name)
        if col is None:
            logger.error(f"Collection '{collection_name}' not found")
            return 0

        if len(chunks) != len(embeddings):
            logger.error("chunks / embeddings length mismatch")
            return 0

        ids = []
        documents = []
        metadatas = []
        embs = []

        for chunk, emb in zip(chunks, embeddings):
            ids.append(chunk.chunk_id)
            documents.append(chunk.content)
            embs.append(emb)

            meta = {
                "level": chunk.level,
                "parent_id": chunk.parent_id or "",
                "children_ids": "|".join(chunk.children_ids),
                "document_id": chunk.document_id,
                "source_path": chunk.source_path,
                "section_path": " > ".join(chunk.section_path),
                "page_numbers": ",".join(str(p) for p in chunk.page_numbers),
                "element_types": ",".join(chunk.element_types),
            }
            # Multimodal: serialise image references as JSON string
            if chunk.images:
                meta["images_json"] = chunk.serialise_images_json()
                meta["image_count"] = chunk.image_count or len(chunk.images)
            else:
                meta["image_count"] = 0

            # Flatten chunk.metadata (ChromaDB only supports str/int/float/bool)
            for k, v in chunk.metadata.items():
                if isinstance(v, (str, int, float, bool)):
                    meta[k] = v
            metadatas.append(meta)

        # Batch upsert (ChromaDB limits ~5000 per call)
        batch_size = 4000
        added = 0
        for i in range(0, len(ids), batch_size):
            end = min(i + batch_size, len(ids))
            try:
                col.upsert(
                    ids=ids[i:end],
                    documents=documents[i:end],
                    embeddings=embs[i:end],
                    metadatas=metadatas[i:end],
                )
                added += end - i
            except Exception as exc:
                logger.error(f"ChromaDB upsert failed (batch {i}-{end}): {exc}")

        logger.info(f"📥 Upserted {added} chunks into '{collection_name}'")
        return added

    # ────────────────────────────────────────────────────
    #  Search
    # ────────────────────────────────────────────────────
    def search(
        self,
        query_embedding: List[float],
        collection_name: str = "documents",
        top_k: int = 10,
        where: Optional[Dict] = None,
        where_document: Optional[Dict] = None,
    ) -> List[RetrievedChunk]:
        """
        Vector similarity search.

        Returns sorted list of RetrievedChunk (highest score first).
        """
        col = self._collections.get(collection_name)
        if col is None:
            return []

        try:
            kwargs: Dict[str, Any] = {
                "query_embeddings": [query_embedding],
                "n_results": top_k,
            }
            if where:
                kwargs["where"] = where
            if where_document:
                kwargs["where_document"] = where_document

            results = col.query(**kwargs)
        except Exception as exc:
            logger.error(f"ChromaDB query failed: {exc}")
            return []

        chunks: List[RetrievedChunk] = []
        if not results or not results.get("ids"):
            return chunks

        ids = results["ids"][0]
        docs = results["documents"][0] if results.get("documents") else [""] * len(ids)
        distances = results["distances"][0] if results.get("distances") else [1.0] * len(ids)
        metas = results["metadatas"][0] if results.get("metadatas") else [{}] * len(ids)

        for cid, doc, dist, meta in zip(ids, docs, distances, metas):
            # ChromaDB returns distance; convert to similarity (cosine: sim = 1 - dist)
            score = max(0.0, 1.0 - dist)
            # Deserialise image references
            images = HierarchicalChunk.deserialise_images_json(
                meta.get("images_json", "")
            ) if meta else []
            image_count = int(meta.get("image_count", 0)) if meta else 0

            chunks.append(RetrievedChunk(
                chunk_id=cid,
                content=doc,
                score=score,
                level=int(meta.get("level", 2)),
                parent_id=meta.get("parent_id", "") or None,
                document_id=meta.get("document_id", ""),
                source_path=meta.get("source_path", ""),
                section_path=meta.get("section_path", "").split(" > ") if meta.get("section_path") else [],
                page_numbers=[int(p) for p in meta.get("page_numbers", "").split(",") if p],
                element_types=meta.get("element_types", "").split(",") if meta.get("element_types") else [],
                metadata=meta,
                images=images,
                image_count=image_count,
            ))

        return chunks

    # ────────────────────────────────────────────────────
    #  Get by ID (for parent/sibling expansion)
    # ────────────────────────────────────────────────────
    def get_by_ids(
        self,
        chunk_ids: List[str],
        collection_name: str = "documents",
    ) -> List[RetrievedChunk]:
        """Retrieve chunks by their IDs."""
        col = self._collections.get(collection_name)
        if col is None or not chunk_ids:
            return []

        try:
            results = col.get(ids=chunk_ids, include=["documents", "metadatas"])
        except Exception as exc:
            logger.error(f"ChromaDB get failed: {exc}")
            return []

        chunks: List[RetrievedChunk] = []
        if not results or not results.get("ids"):
            return chunks

        for cid, doc, meta in zip(
            results["ids"],
            results.get("documents", []),
            results.get("metadatas", []),
        ):
            images = HierarchicalChunk.deserialise_images_json(
                meta.get("images_json", "")
            ) if meta else []
            image_count = int(meta.get("image_count", 0)) if meta else 0

            chunks.append(RetrievedChunk(
                chunk_id=cid,
                content=doc or "",
                score=1.0,  # Fetched by ID, not by similarity
                level=int(meta.get("level", 2)) if meta else 2,
                parent_id=(meta.get("parent_id", "") or None) if meta else None,
                document_id=meta.get("document_id", "") if meta else "",
                source_path=meta.get("source_path", "") if meta else "",
                section_path=(
                    meta.get("section_path", "").split(" > ")
                    if meta and meta.get("section_path") else []
                ),
                page_numbers=[
                    int(p) for p in meta.get("page_numbers", "").split(",") if p
                ] if meta else [],
                element_types=(
                    meta.get("element_types", "").split(",")
                    if meta and meta.get("element_types") else []
                ),
                metadata=meta or {},
                images=images,
                image_count=image_count,
            ))

        return chunks

    # ────────────────────────────────────────────────────
    #  Utilities
    # ────────────────────────────────────────────────────
    def get_collection_counts(self) -> Dict[str, int]:
        """Return item counts for all collections."""
        return {name: col.count() for name, col in self._collections.items()}

    def delete_document(self, document_id: str, collection_name: str = "documents"):
        """Delete all chunks belonging to a document."""
        col = self._collections.get(collection_name)
        if col is None:
            return
        try:
            col.delete(where={"document_id": document_id})
            logger.info(f"🗑️ Deleted document {document_id} from '{collection_name}'")
        except Exception as exc:
            logger.warning(f"Delete failed: {exc}")

    def clear_collection(self, collection_name: str):
        """Clear an entire collection."""
        if collection_name in self._collections and self._client:
            try:
                self._client.delete_collection(collection_name)
                # Re-create empty
                self._collections[collection_name] = self._client.get_or_create_collection(
                    name=collection_name,
                    metadata={"hnsw:space": "cosine"},
                )
                logger.info(f"🗑️ Cleared collection '{collection_name}'")
            except Exception as exc:
                logger.warning(f"Clear collection failed: {exc}")

    def persist(self):
        """Explicitly persist data to disk (older chromadb versions)."""
        try:
            if hasattr(self._client, "persist"):
                self._client.persist()
                logger.info("💾 ChromaDB persisted to disk")
        except Exception as exc:
            logger.warning(f"Persist failed: {exc}")
