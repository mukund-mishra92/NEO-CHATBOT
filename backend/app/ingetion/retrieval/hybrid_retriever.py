"""
Hybrid Retriever — Vector search + BM25 + Reciprocal Rank Fusion.

Search flow:
  1. Dense vector search (ChromaDB) across all relevant collections
  2. Sparse BM25 keyword search on stored documents
  3. Reciprocal Rank Fusion (RRF) to merge rankings
  4. Parent / sibling chunk expansion for context
"""

from __future__ import annotations

import logging
import math
import re
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

from ..models import RetrievedChunk
from ..store.chroma_store import ChromaStore

logger = logging.getLogger(__name__)

# RRF constant (standard value from literature)
RRF_K = 60


class HybridRetriever:
    """Combine dense + sparse retrieval with rank fusion."""

    def __init__(
        self,
        store: ChromaStore,
        *,
        vector_top_k: int = 15,
        bm25_top_k: int = 15,
        final_top_k: int = 10,
        use_parent_expansion: bool = True,
    ):
        self.store = store
        self.vector_top_k = vector_top_k
        self.bm25_top_k = bm25_top_k
        self.final_top_k = final_top_k
        self.use_parent_expansion = use_parent_expansion
        self._bm25_index = None  # Lazy-built

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def retrieve(
        self,
        query: str,
        query_embedding: List[float],
        collections: Optional[List[str]] = None,
        filter_metadata: Optional[Dict] = None,
    ) -> List[RetrievedChunk]:
        """
        Retrieve the most relevant chunks using hybrid search.

        Args:
            query: Natural language question.
            query_embedding: Pre-computed embedding of the query.
            collections: Which ChromaDB collections to search (default: all).
            filter_metadata: Optional ChromaDB where filter.

        Returns:
            Merged, re-ranked list of RetrievedChunk.
        """
        collections = collections or list(ChromaStore.COLLECTION_NAMES)

        # ── 1. Dense vector search ──
        vector_results: List[RetrievedChunk] = []
        for col_name in collections:
            results = self.store.search(
                query_embedding=query_embedding,
                collection_name=col_name,
                top_k=self.vector_top_k,
                where=filter_metadata,
            )
            vector_results.extend(results)

        # ── 2. BM25 sparse search ──
        bm25_results = self._bm25_search(query, collections)

        # ── 3. Reciprocal Rank Fusion ──
        fused = self._reciprocal_rank_fusion(vector_results, bm25_results)

        # ── 4. Parent / sibling expansion ──
        if self.use_parent_expansion:
            fused = self._expand_context(fused)

        # ── 5. Deduplicate & truncate ──
        fused = self._deduplicate(fused)
        fused = fused[: self.final_top_k]

        logger.info(
            f"🔍 Hybrid retrieval: {len(vector_results)} vector + "
            f"{len(bm25_results)} BM25 → {len(fused)} fused results"
        )
        return fused

    # ────────────────────────────────────────────────────
    #  BM25 sparse search
    # ────────────────────────────────────────────────────
    def _bm25_search(
        self, query: str, collections: List[str]
    ) -> List[RetrievedChunk]:
        """Keyword search using BM25 over ChromaDB full-text."""
        # Use ChromaDB's where_document contains filter as a lightweight BM25 proxy
        # For true BM25, we'd need rank_bm25 with a local corpus index
        try:
            from rank_bm25 import BM25Okapi
        except ImportError:
            logger.debug("rank_bm25 not installed — falling back to keyword filter")
            return self._keyword_fallback(query, collections)

        # Build BM25 index lazily from ChromaDB contents
        if self._bm25_index is None:
            self._build_bm25_index(collections)

        if self._bm25_index is None:
            return []

        bm25, corpus_ids, corpus_chunks = self._bm25_index
        tokens = self._tokenize(query)
        if not tokens:
            return []

        scores = bm25.get_scores(tokens)
        # Get top-k
        ranked = sorted(enumerate(scores), key=lambda x: x[1], reverse=True)
        results: List[RetrievedChunk] = []
        for idx, score in ranked[: self.bm25_top_k]:
            if score <= 0:
                break
            chunk = corpus_chunks[idx]
            chunk.score = float(score)
            results.append(chunk)

        return results

    def _build_bm25_index(self, collections: List[str]):
        """Build BM25 index from all chunks in the specified collections."""
        try:
            from rank_bm25 import BM25Okapi
        except ImportError:
            return

        all_ids: List[str] = []
        all_chunks: List[RetrievedChunk] = []
        all_tokenized: List[List[str]] = []

        for col_name in collections:
            col = self.store._collections.get(col_name)
            if col is None:
                continue
            count = col.count()
            if count == 0:
                continue
            try:
                # Fetch all documents from collection for BM25 indexing
                data = col.get(include=["documents", "metadatas"])
                if not data or not data.get("ids"):
                    continue
                for cid, doc, meta in zip(
                    data["ids"],
                    data.get("documents", []),
                    data.get("metadatas", []),
                ):
                    if not doc:
                        continue
                    all_ids.append(cid)
                    all_tokenized.append(self._tokenize(doc))
                    all_chunks.append(RetrievedChunk(
                        chunk_id=cid,
                        content=doc,
                        score=0.0,
                        level=int(meta.get("level", 2)) if meta else 2,
                        parent_id=(meta.get("parent_id") or None) if meta else None,
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
                    ))
            except Exception as exc:
                logger.warning(f"Failed to load collection '{col_name}' for BM25: {exc}")

        if all_tokenized:
            bm25 = BM25Okapi(all_tokenized)
            self._bm25_index = (bm25, all_ids, all_chunks)
            logger.info(f"📇 Built BM25 index: {len(all_ids)} documents")
        else:
            logger.warning("No documents found for BM25 index")

    def _keyword_fallback(
        self, query: str, collections: List[str]
    ) -> List[RetrievedChunk]:
        """Simple keyword-contains fallback when rank_bm25 isn't available."""
        keywords = self._tokenize(query)
        if not keywords:
            return []

        results: List[RetrievedChunk] = []
        for col_name in collections:
            for kw in keywords[:3]:  # Limit to avoid too many queries
                try:
                    hits = self.store.search(
                        query_embedding=[0.0] * 384,  # Dummy; won't be used with where_document
                        collection_name=col_name,
                        top_k=5,
                        where_document={"$contains": kw},
                    )
                    results.extend(hits)
                except Exception:
                    pass

        return results

    # ────────────────────────────────────────────────────
    #  Reciprocal Rank Fusion
    # ────────────────────────────────────────────────────
    def _reciprocal_rank_fusion(
        self,
        vector_results: List[RetrievedChunk],
        bm25_results: List[RetrievedChunk],
    ) -> List[RetrievedChunk]:
        """Merge two ranked lists using RRF."""
        scores: Dict[str, float] = defaultdict(float)
        chunk_map: Dict[str, RetrievedChunk] = {}

        # Vector ranking
        for rank, chunk in enumerate(
            sorted(vector_results, key=lambda c: c.score, reverse=True)
        ):
            scores[chunk.chunk_id] += 1.0 / (RRF_K + rank + 1)
            if chunk.chunk_id not in chunk_map:
                chunk_map[chunk.chunk_id] = chunk

        # BM25 ranking
        for rank, chunk in enumerate(
            sorted(bm25_results, key=lambda c: c.score, reverse=True)
        ):
            scores[chunk.chunk_id] += 1.0 / (RRF_K + rank + 1)
            if chunk.chunk_id not in chunk_map:
                chunk_map[chunk.chunk_id] = chunk

        # Sort by fused score
        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        result: List[RetrievedChunk] = []
        for cid, score in ranked:
            chunk = chunk_map[cid]
            chunk.score = score
            result.append(chunk)

        return result

    # ────────────────────────────────────────────────────
    #  Parent / sibling expansion
    # ────────────────────────────────────────────────────
    def _expand_context(
        self, chunks: List[RetrievedChunk]
    ) -> List[RetrievedChunk]:
        """Fetch parent chunks for Level-2 hits to provide broader context."""
        parent_ids_needed = set()
        existing_ids = {c.chunk_id for c in chunks}

        for chunk in chunks:
            if chunk.level == 2 and chunk.parent_id and chunk.parent_id not in existing_ids:
                parent_ids_needed.add(chunk.parent_id)

        if not parent_ids_needed:
            return chunks

        # Fetch parents from store
        parents = self.store.get_by_ids(list(parent_ids_needed))
        if parents:
            # Assign a slightly lower score than child
            min_score = min(c.score for c in chunks) if chunks else 0.0
            for parent in parents:
                parent.score = min_score * 0.9
            chunks.extend(parents)
            logger.debug(f"Expanded context: added {len(parents)} parent chunks")

        return chunks

    # ────────────────────────────────────────────────────
    #  Deduplication
    # ────────────────────────────────────────────────────
    @staticmethod
    def _deduplicate(chunks: List[RetrievedChunk]) -> List[RetrievedChunk]:
        """Remove duplicates, keeping highest score."""
        seen: Dict[str, RetrievedChunk] = {}
        for chunk in chunks:
            if chunk.chunk_id not in seen or chunk.score > seen[chunk.chunk_id].score:
                seen[chunk.chunk_id] = chunk
        return sorted(seen.values(), key=lambda c: c.score, reverse=True)

    # ────────────────────────────────────────────────────
    #  Tokenizer
    # ────────────────────────────────────────────────────
    @staticmethod
    def _tokenize(text: str) -> List[str]:
        """Simple whitespace + lowercase tokenizer with stopword removal."""
        stopwords = {
            "the", "a", "an", "is", "are", "was", "were", "in", "on", "at",
            "to", "for", "of", "with", "by", "from", "and", "or", "not",
            "it", "this", "that", "be", "as", "do", "does", "did", "has",
            "have", "had", "will", "would", "can", "could", "should",
            "what", "how", "which", "who", "when", "where", "why",
            "i", "me", "my", "we", "our", "you", "your", "he", "she",
        }
        tokens = re.findall(r"\w+", text.lower())
        return [t for t in tokens if t not in stopwords and len(t) > 1]

    def invalidate_bm25_index(self):
        """Force BM25 index to be rebuilt on next search."""
        self._bm25_index = None
