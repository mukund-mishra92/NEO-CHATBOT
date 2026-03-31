"""
Context Assembler — Organise retrieved chunks into a structured context
string suitable for LLM consumption, with citations.
"""

from __future__ import annotations

import logging
from typing import Dict, List, Tuple

from ..models import RetrievedChunk, Source

logger = logging.getLogger(__name__)

# Max total characters for assembled context (fits within LLM context window)
MAX_CONTEXT_CHARS = 30_000


class ContextAssembler:
    """Assemble retrieved chunks into a coherent prompt context."""

    def __init__(self, *, max_context_chars: int = MAX_CONTEXT_CHARS):
        self.max_chars = max_context_chars

    def assemble(
        self,
        chunks: List[RetrievedChunk],
    ) -> Tuple[str, List[Source]]:
        """
        Build a structured context block and extract sources/citations.

        Returns:
            (context_text, sources) — ready to inject into an LLM prompt.
        """
        if not chunks:
            return "", []

        # Group by document
        doc_groups: Dict[str, List[RetrievedChunk]] = {}
        for chunk in chunks:
            key = chunk.source_path or chunk.document_id or "unknown"
            doc_groups.setdefault(key, []).append(chunk)

        parts: List[str] = []
        sources: List[Source] = []
        char_count = 0
        source_idx = 1

        for doc_key, doc_chunks in doc_groups.items():
            # Sort within document: level ascending, then page
            doc_chunks.sort(key=lambda c: (c.level, min(c.page_numbers) if c.page_numbers else 0))

            # Document header
            title = self._extract_title(doc_chunks)
            section = " > ".join(doc_chunks[0].section_path) if doc_chunks[0].section_path else ""
            pages = sorted({p for c in doc_chunks for p in c.page_numbers})
            pages_str = f"Pages {pages[0]}-{pages[-1]}" if pages else ""

            header = f"[Source {source_idx}] {title}"
            if section:
                header += f" — {section}"
            if pages_str:
                header += f" ({pages_str})"
            parts.append(f"\n{'═' * 60}")
            parts.append(header)
            parts.append(f"{'─' * 60}")

            # Source citation
            sources.append(Source(
                document_title=title,
                source_path=doc_key,
                page_numbers=pages,
                section=section,
                relevance_score=max(c.score for c in doc_chunks),
            ))

            # Chunk content
            for chunk in doc_chunks:
                label = ""
                if chunk.level == 0:
                    label = "[Document Overview]\n"
                elif chunk.level == 1:
                    label = f"[Section: {' > '.join(chunk.section_path[-2:])}]\n" if len(chunk.section_path) > 1 else ""

                text = f"{label}{chunk.content}"
                if char_count + len(text) > self.max_chars:
                    # Truncate last chunk to fit
                    remaining = self.max_chars - char_count
                    if remaining > 100:
                        parts.append(text[:remaining] + "…[truncated]")
                    break
                parts.append(text)
                char_count += len(text)

            source_idx += 1
            if char_count >= self.max_chars:
                break

        context = "\n".join(parts)
        logger.info(
            f"📋 Assembled context: {len(context)} chars, "
            f"{len(sources)} sources from {len(chunks)} chunks"
        )
        return context, sources

    @staticmethod
    def _extract_title(chunks: List[RetrievedChunk]) -> str:
        """Best-effort document title extraction."""
        for c in chunks:
            fn = c.metadata.get("filename", "")
            if fn:
                return fn
        for c in chunks:
            if c.source_path:
                import os
                return os.path.basename(c.source_path)
        return "Unknown Document"
