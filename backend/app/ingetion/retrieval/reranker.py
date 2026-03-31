"""
Reranker — Cross-encoder or simple heuristic reranking of retrieved chunks.

Uses cross-encoder model if available, otherwise falls back to
keyword-overlap and element-type-priority heuristics.
"""

from __future__ import annotations

import logging
import re
from typing import List, Optional

from ..models import RetrievedChunk

logger = logging.getLogger(__name__)


class Reranker:
    """Rerank retrieved chunks for a query."""

    def __init__(self, *, use_cross_encoder: bool = False, model_name: str = "cross-encoder/ms-marco-MiniLM-L-6-v2"):
        """
        Args:
            use_cross_encoder: Attempt to load a cross-encoder model.
            model_name: HuggingFace model name for cross-encoder.
        """
        self.cross_encoder = None
        if use_cross_encoder:
            self._load_cross_encoder(model_name)

    def _load_cross_encoder(self, model_name: str):
        """Try to load a sentence-transformers cross-encoder."""
        try:
            from sentence_transformers import CrossEncoder
            self.cross_encoder = CrossEncoder(model_name)
            logger.info(f"✅ Cross-encoder loaded: {model_name}")
        except ImportError:
            logger.info("sentence-transformers not available — using heuristic reranker")
        except Exception as exc:
            logger.warning(f"Cross-encoder load failed: {exc} — using heuristic reranker")

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def rerank(
        self,
        query: str,
        chunks: List[RetrievedChunk],
        top_k: int = 8,
    ) -> List[RetrievedChunk]:
        """
        Rerank chunks for relevance to query.

        Returns:
            Top-k reranked chunks (highest relevance first).
        """
        if not chunks:
            return []

        if self.cross_encoder:
            return self._rerank_cross_encoder(query, chunks, top_k)
        return self._rerank_heuristic(query, chunks, top_k)

    # ────────────────────────────────────────────────────
    #  Cross-encoder reranking
    # ────────────────────────────────────────────────────
    def _rerank_cross_encoder(
        self, query: str, chunks: List[RetrievedChunk], top_k: int
    ) -> List[RetrievedChunk]:
        """Rerank using cross-encoder scores."""
        pairs = [(query, c.content) for c in chunks]
        try:
            scores = self.cross_encoder.predict(pairs)
            for chunk, score in zip(chunks, scores):
                chunk.score = float(score)
            chunks.sort(key=lambda c: c.score, reverse=True)
            return chunks[:top_k]
        except Exception as exc:
            logger.warning(f"Cross-encoder failed: {exc} — falling back to heuristic")
            return self._rerank_heuristic(query, chunks, top_k)

    # ────────────────────────────────────────────────────
    #  Heuristic reranking
    # ────────────────────────────────────────────────────
    def _rerank_heuristic(
        self, query: str, chunks: List[RetrievedChunk], top_k: int
    ) -> List[RetrievedChunk]:
        """
        Heuristic reranker based on:
          • Keyword overlap with query
          • Element type priority (tables & headings boost)
          • Content length penalty (too short = low info)
          • Section path match
        """
        query_tokens = set(self._tokenize(query))

        for chunk in chunks:
            bonus = 0.0
            content_tokens = set(self._tokenize(chunk.content))

            # 1. Keyword overlap (Jaccard-ish)
            if query_tokens:
                overlap = len(query_tokens & content_tokens)
                bonus += (overlap / len(query_tokens)) * 0.3

            # 2. Element type boost
            types = set(chunk.element_types)
            if "table" in types:
                bonus += 0.1
            if "heading" in types:
                bonus += 0.05
            if "image" in types:
                bonus += 0.05

            # 3. Content length: penalize very short chunks
            if len(chunk.content) < 100:
                bonus -= 0.1
            elif len(chunk.content) > 300:
                bonus += 0.05

            # 4. Section path keyword match
            section_text = " ".join(chunk.section_path).lower()
            for qt in query_tokens:
                if qt in section_text:
                    bonus += 0.05

            # 5. Level preference: prefer Level-2 (detailed) over Level-0 (summary)
            if chunk.level == 2:
                bonus += 0.05
            elif chunk.level == 0:
                bonus -= 0.05

            chunk.score = chunk.score + bonus

        chunks.sort(key=lambda c: c.score, reverse=True)
        return chunks[:top_k]

    @staticmethod
    def _tokenize(text: str) -> List[str]:
        stopwords = {
            "the", "a", "an", "is", "are", "was", "were", "in", "on", "at",
            "to", "for", "of", "with", "by", "from", "and", "or", "not",
            "what", "how", "which", "who", "when", "where", "why",
        }
        return [t for t in re.findall(r"\w+", text.lower()) if t not in stopwords and len(t) > 1]
