"""
DOCX Extractor — Structured extraction from Word documents.

Extracts:
  • Headings (with levels)
  • Paragraphs preserving structure
  • Tables as markdown
  • Images with optional Vision API descriptions
"""

from __future__ import annotations

import io
import logging
import re
from pathlib import Path
from typing import List, Optional

from ..models import ExtractedDocument, ExtractedElement, ExtractedPage

logger = logging.getLogger(__name__)


class DOCXExtractor:
    """Extract structured content from .docx files."""

    def __init__(self, *, image_describer=None):
        self.image_describer = image_describer

    def extract(self, file_path: str) -> ExtractedDocument:
        """Extract all content from a DOCX file."""
        path = Path(file_path)
        doc = ExtractedDocument(
            source_path=str(path),
            file_type="docx",
            title=path.stem,
            metadata={"filename": path.name},
        )

        try:
            from docx import Document as DocxDocument
        except ImportError:
            logger.error("python-docx not installed — run: pip install python-docx")
            return doc

        try:
            docx = DocxDocument(file_path)
            elements: List[ExtractedElement] = []
            page_num = 1  # DOCX doesn't have real pages; we simulate per major heading

            # ── Core properties ──
            if docx.core_properties:
                if docx.core_properties.title:
                    doc.title = docx.core_properties.title
                if docx.core_properties.author:
                    doc.metadata["author"] = docx.core_properties.author

            # ── Paragraphs & headings ──
            for para in docx.paragraphs:
                text = para.text.strip()
                if not text:
                    continue

                style_name = (para.style.name or "").lower()

                if "heading" in style_name:
                    # Extract heading level
                    level = 1
                    m = re.search(r"heading\s*(\d)", style_name)
                    if m:
                        level = int(m.group(1))
                    if level == 1:
                        page_num += 1  # Simulate page break on major headings
                    elements.append(ExtractedElement(
                        content=text,
                        element_type="heading",
                        page_number=page_num,
                        metadata={"heading_level": level, "style": para.style.name},
                    ))
                elif "list" in style_name or text.startswith(("•", "-", "●", "*")):
                    elements.append(ExtractedElement(
                        content=text,
                        element_type="list",
                        page_number=page_num,
                    ))
                else:
                    elements.append(ExtractedElement(
                        content=text,
                        element_type="text",
                        page_number=page_num,
                    ))

            # ── Tables ──
            for table in docx.tables:
                md = self._table_to_markdown(table)
                if md:
                    elements.append(ExtractedElement(
                        content=md,
                        element_type="table",
                        page_number=page_num,
                        metadata={"rows": len(table.rows), "cols": len(table.columns)},
                    ))

            # ── Images ──
            if self.image_describer:
                self._extract_images(docx, elements, path.name)

            # Group elements into pages (by page_number)
            pages_map: dict[int, ExtractedPage] = {}
            for elem in elements:
                pn = elem.page_number
                if pn not in pages_map:
                    pages_map[pn] = ExtractedPage(page_number=pn)
                pages_map[pn].elements.append(elem)

            for pn in sorted(pages_map):
                ep = pages_map[pn]
                ep.composite_text = "\n\n".join(e.content for e in ep.elements)
                ep.raw_text = ep.composite_text
                doc.pages.append(ep)

            doc.metadata["total_pages"] = len(doc.pages)
            logger.info(f"✅ Extracted {len(elements)} elements from {path.name}")

        except Exception as exc:
            logger.error(f"DOCX extraction failed for {path.name}: {exc}", exc_info=True)

        return doc

    # ────────────────────────────────────────────────────
    #  Images
    # ────────────────────────────────────────────────────
    def _extract_images(self, docx, elements: list, filename: str):
        """Extract images from DOCX relationships."""
        try:
            from docx.opc.constants import RELATIONSHIP_TYPE as RT
            for rel in docx.part.rels.values():
                if "image" in rel.reltype:
                    try:
                        img_part = rel.target_part
                        img_bytes = img_part.blob
                        if len(img_bytes) < 2000:  # Skip tiny images
                            continue
                        desc = self.image_describer.describe(
                            img_bytes, context=f"Document: {filename}"
                        )
                        if desc:
                            elements.append(ExtractedElement(
                                content=f"[Image: {desc}]",
                                element_type="image",
                                page_number=1,
                                metadata={"description": desc},
                            ))
                    except Exception as exc:
                        logger.debug(f"Skipping DOCX image: {exc}")
        except Exception as exc:
            logger.debug(f"DOCX image extraction error: {exc}")

    # ────────────────────────────────────────────────────
    #  Table → Markdown
    # ────────────────────────────────────────────────────
    @staticmethod
    def _table_to_markdown(table) -> str:
        """Convert a python-docx Table to Markdown."""
        rows_data = []
        for row in table.rows:
            cells = [cell.text.replace("\n", " ").strip() for cell in row.cells]
            rows_data.append(cells)
        if not rows_data:
            return ""

        header = rows_data[0]
        md = "| " + " | ".join(header) + " |\n"
        md += "| " + " | ".join("---" for _ in header) + " |\n"
        for row in rows_data[1:]:
            padded = row + [""] * (len(header) - len(row)) if len(row) < len(header) else row[:len(header)]
            md += "| " + " | ".join(padded) + " |\n"
        return md.strip()
