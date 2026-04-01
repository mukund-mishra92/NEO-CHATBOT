"""
Response Structurer — Convert flat LLM text into StructuredResponse.

Phase 8 of the Multimodal RAG Upgrade Plan.

Parses the LLM's markdown text along with the AnswerPlan to produce:
  - summary: first-sentence / first-paragraph summary
  - sections: heading + content blocks
  - figures: figure metadata with section assignments
  - citations: source documents referenced
"""

from __future__ import annotations

import logging
import re
from typing import Any, Dict, List, Optional

from ..models.schemas import ResponseSection, StructuredResponse, SourceDocument

logger = logging.getLogger(__name__)

# Regex for markdown headings (##, ###, **Heading**)
_HEADING_RE = re.compile(
    r"^(?:"
    r"#{2,4}\s+(.+)"          # ## Heading
    r"|"
    r"\*\*([^*]{3,80})\*\*$"  # **Bold line** used as heading
    r")",
    re.MULTILINE,
)

# Regex to detect figure references in text
_FIGURE_REF_RE = re.compile(r"\bFigure\s+(\d+)\b", re.IGNORECASE)


class ResponseStructurer:
    """Parse LLM output + plan into a StructuredResponse."""

    def structure(
        self,
        response_text: str,
        *,
        answer_plan=None,
        source_documents: Optional[List[SourceDocument]] = None,
        images: Optional[List[Dict[str, Any]]] = None,
    ) -> StructuredResponse:
        """
        Build a StructuredResponse from raw LLM text.

        Args:
            response_text: Flat markdown text from the LLM.
            answer_plan: Optional AnswerPlan from Phase 7.
            source_documents: Source citation objects.
            images: Display image dicts from the pipeline.

        Returns:
            StructuredResponse with summary, sections, figures, citations.
        """
        if not response_text or not response_text.strip():
            return StructuredResponse()

        # 1. Split text into heading-delimited sections
        sections = self._split_into_sections(response_text)

        # 2. Extract summary (first section or first paragraph)
        summary = self._extract_summary(sections)

        # 3. Map figure references per section
        for sec in sections:
            sec.figures = self._find_figure_refs(sec.content)

        # 4. Build figures list
        figures = self._build_figures(images or [])

        # 5. Build citations list
        citations = self._build_citations(source_documents or [])

        structured = StructuredResponse(
            summary=summary,
            sections=sections,
            figures=figures,
            citations=citations,
        )

        logger.debug(
            f"📄 Structured response: {len(sections)} sections, "
            f"{len(figures)} figures, {len(citations)} citations"
        )
        return structured

    # ────────────────────────────────────────
    #  Section Splitting
    # ────────────────────────────────────────
    def _split_into_sections(self, text: str) -> List[ResponseSection]:
        """Split markdown text into sections by headings."""
        lines = text.split("\n")
        sections: List[ResponseSection] = []
        current_heading = ""
        current_lines: List[str] = []

        for line in lines:
            m = _HEADING_RE.match(line.strip())
            if m:
                # Save previous section
                if current_lines:
                    content = "\n".join(current_lines).strip()
                    if content:
                        sections.append(ResponseSection(
                            heading=current_heading,
                            content=content,
                        ))
                current_heading = (m.group(1) or m.group(2) or "").strip()
                current_lines = []
            else:
                current_lines.append(line)

        # Flush last section
        if current_lines:
            content = "\n".join(current_lines).strip()
            if content:
                sections.append(ResponseSection(
                    heading=current_heading,
                    content=content,
                ))

        # If no headings were found, treat entire text as one section
        if not sections:
            sections.append(ResponseSection(
                heading="",
                content=text.strip(),
            ))

        return sections

    # ────────────────────────────────────────
    #  Summary Extraction
    # ────────────────────────────────────────
    @staticmethod
    def _extract_summary(sections: List[ResponseSection]) -> str:
        """Extract a summary from the first section or first paragraph."""
        if not sections:
            return ""

        first = sections[0].content
        # Use first paragraph as summary
        paragraphs = first.split("\n\n")
        if paragraphs:
            summary = paragraphs[0].strip()
            # Clean markdown formatting from summary
            summary = re.sub(r"\*\*(.+?)\*\*", r"\1", summary)
            summary = re.sub(r"__(.+?)__", r"\1", summary)
            # Limit length
            if len(summary) > 400:
                # Truncate at last sentence boundary
                cut = summary[:400].rfind(".")
                if cut > 100:
                    summary = summary[: cut + 1]
                else:
                    summary = summary[:397] + "..."
            return summary
        return first[:300]

    # ────────────────────────────────────────
    #  Figure References
    # ────────────────────────────────────────
    @staticmethod
    def _find_figure_refs(text: str) -> List[int]:
        """Extract figure numbers referenced in text."""
        return sorted(set(int(m.group(1)) for m in _FIGURE_REF_RE.finditer(text)))

    # ────────────────────────────────────────
    #  Figures
    # ────────────────────────────────────────
    @staticmethod
    def _build_figures(images: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Build structured figure list from display images."""
        figures = []
        for idx, img in enumerate(images, 1):
            figures.append({
                "figure_number": idx,
                "image_path": img.get("image_path", ""),
                "caption": img.get("caption", ""),
                "source_document": img.get("source_document", ""),
                "page_number": img.get("page_number"),
            })
        return figures

    # ────────────────────────────────────────
    #  Citations
    # ────────────────────────────────────────
    @staticmethod
    def _build_citations(sources: List[SourceDocument]) -> List[Dict[str, str]]:
        """Build citation list from source documents."""
        citations = []
        seen = set()
        for src in sources:
            key = (src.document_name, src.page_number)
            if key in seen:
                continue
            seen.add(key)
            citations.append({
                "document": src.document_name,
                "page": str(src.page_number) if src.page_number else "",
                "snippet": src.content_snippet[:150] if src.content_snippet else "",
                "relevance": f"{src.relevance_score:.0%}" if src.relevance_score else "",
            })
        return citations
