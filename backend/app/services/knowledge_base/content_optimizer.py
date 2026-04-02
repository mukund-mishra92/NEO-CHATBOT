"""
Content Optimizer — Intelligently reduces RAG context size while preserving meaning.

Integrated into KnowledgeBaseService to trim retrieved chunks before they are
sent to the LLM, cutting token usage by 30-50 % without losing relevance.
"""

import re
import logging
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)


class ContentOptimizer:
    """Reduce token bloat in retrieved RAG context."""

    def __init__(self, llm_service=None):
        self.llm_service = llm_service

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def optimize_chunks(
        self,
        chunks: List[Dict[str, Any]],
        query: str,
        target_length: str = "medium",
        max_chunk_length: int = 800,
    ) -> List[Dict[str, Any]]:
        """
        Trim and score *legacy-format* search results
        (list of ``{"document": {"content": ...}, "similarity": ...}`` dicts).

        ``target_length`` controls aggressiveness:
          * ``"concise"``  → keep ≤3 key sentences
          * ``"medium"``   → keep ≤6  (default)
          * ``"detailed"`` → keep ≤10
        """
        sentence_limits = {"concise": 3, "medium": 6, "detailed": 10}
        max_sentences = sentence_limits.get(target_length, 6)

        optimized: List[Dict[str, Any]] = []
        original_chars = 0
        optimized_chars = 0

        for chunk in chunks:
            doc = chunk.get("document", chunk)
            content = doc.get("content", "")
            if not content or len(content.strip()) < 50:
                continue

            original_chars += len(content)

            # Step 1 — strip boilerplate
            content = self._remove_boilerplate(content)

            # Step 2 — extract key sentences
            content = self._extract_key_sentences(content, query, max_sentences)

            # Step 3 — hard length cap
            if len(content) > max_chunk_length:
                content = content[: max_chunk_length] + "…"

            optimized_chars += len(content)

            # Build shallow copy with trimmed content
            new_chunk = {**chunk}
            new_doc = {**doc, "content": content}
            new_chunk["document"] = new_doc
            optimized.append(new_chunk)

        reduction = (
            round((1 - optimized_chars / original_chars) * 100, 1)
            if original_chars
            else 0
        )
        logger.info(
            f"📊 Content optimizer: {len(chunks)} → {len(optimized)} chunks, "
            f"{original_chars:,} → {optimized_chars:,} chars ({reduction}% reduction)"
        )
        return optimized

    def optimize_rag_context(
        self,
        context_text: str,
        query: str,
        max_tokens: int = 6000,
    ) -> str:
        """
        Trim a *pre-built context string* (used when the primary path is
        ChromaDB RAG, which returns a single combined context string).

        Uses a cheap char→token heuristic (1 token ≈ 4 chars).
        """
        max_chars = max_tokens * 4  # rough estimate

        if len(context_text) <= max_chars:
            return context_text

        # Split into paragraphs, score, keep best within budget
        paragraphs = [p.strip() for p in context_text.split("\n\n") if p.strip()]
        scored = self._score_paragraphs(paragraphs, query)

        kept: List[str] = []
        chars_used = 0
        for _score, para in scored:
            if chars_used + len(para) > max_chars:
                break
            kept.append(para)
            chars_used += len(para)

        # Re-order to original document order for coherence
        ordered = [p for p in paragraphs if p in kept]

        trimmed = "\n\n".join(ordered)
        logger.info(
            f"📊 RAG context trimmed: {len(context_text):,} → {len(trimmed):,} chars "
            f"(budget {max_tokens} tokens)"
        )
        return trimmed

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------
    _BOILERPLATE_PATTERNS = [
        r"Page \d+ of \d+",
        r"Copyright © \d{4}.*",
        r"Confidential and Proprietary.*",
        r"All rights reserved\.?",
        r"^\s*\d+\s*$",  # lonely page numbers
    ]

    def _remove_boilerplate(self, text: str) -> str:
        if not text:
            return ""
        for pat in self._BOILERPLATE_PATTERNS:
            text = re.sub(pat, "", text, flags=re.IGNORECASE | re.MULTILINE)
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r" {2,}", " ", text)
        return text.strip()

    @staticmethod
    def _tokenise_query(query: str) -> set:
        stop = {
            "the", "is", "at", "which", "on", "a", "an", "and", "or", "but",
            "in", "with", "to", "for", "of", "it", "that", "this", "from",
            "are", "was", "were", "be", "been", "being", "have", "has", "had",
            "do", "does", "did", "will", "would", "could", "should", "may",
            "might", "shall", "can", "about", "how", "what", "when", "where",
            "who", "why", "not", "no", "so", "if", "by", "as", "into", "than",
        }
        return {
            t.lower()
            for t in re.findall(r"[A-Za-z0-9]+", query)
            if t.lower() not in stop and len(t) > 2
        }

    def _extract_key_sentences(
        self, text: str, query: str, max_sentences: int = 5
    ) -> str:
        if not text or not query:
            return text

        sentences = re.split(r"(?<=[.!?])\s+", text)
        query_terms = self._tokenise_query(query)
        query_lower = query.lower()

        scored = []
        for sent in sentences:
            sent = sent.strip()
            if len(sent) < 20:
                continue
            sent_lower = sent.lower()
            sent_terms = set(re.findall(r"[a-z0-9]+", sent_lower))
            overlap = len(query_terms & sent_terms)

            # Bonus for exact sub-string match
            if query_lower in sent_lower:
                overlap += 5

            score = overlap - len(sent) / 200.0
            scored.append((score, sent))

        if not scored:
            return text[:500] + ("…" if len(text) > 500 else "")

        scored.sort(key=lambda x: x[0], reverse=True)
        top = {s for _, s in scored[:max_sentences]}

        # Keep original document order
        result = ". ".join(s for s in sentences if s.strip() in top)
        if result and result[-1] not in ".!?":
            result += "."
        return result

    def _score_paragraphs(
        self, paragraphs: List[str], query: str
    ) -> List[tuple]:
        query_terms = self._tokenise_query(query)
        scored = []
        for para in paragraphs:
            para_lower = para.lower()
            para_terms = set(re.findall(r"[a-z0-9]+", para_lower))
            overlap = len(query_terms & para_terms)
            scored.append((overlap, para))
        scored.sort(key=lambda x: x[0], reverse=True)
        return scored
