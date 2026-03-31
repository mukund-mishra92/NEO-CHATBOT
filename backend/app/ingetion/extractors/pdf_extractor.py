"""
PDF Extractor — Multi-modal content extraction from PDFs.

Extracts:
  • Structured text with heading detection
  • Tables as markdown (pdfplumber)
  • Images via PyMuPDF (fitz), optionally described by Vision API
"""

from __future__ import annotations

import io
import logging
import os
import re
from pathlib import Path
from typing import List, Optional

from ..models import ExtractedDocument, ExtractedElement, ExtractedPage, ImageReference

logger = logging.getLogger(__name__)


class PDFExtractor:
    """Extract text, tables, and images from PDF files."""

    def __init__(self, *, enable_ocr: bool = True, enable_images: bool = True,
                 image_describer=None, image_store=None):
        """
        Args:
            enable_ocr: Use OCR fallback for scanned pages.
            enable_images: Extract embedded images.
            image_describer: Optional ImageDescriber instance for Vision API captions.
            image_store: Optional ImageStore for saving extracted images to disk.
        """
        self.enable_ocr = enable_ocr
        self.enable_images = enable_images
        self.image_describer = image_describer
        self.image_store = image_store

    # ────────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────────
    def extract(self, file_path: str) -> ExtractedDocument:
        """Extract all content from a PDF file."""
        path = Path(file_path)
        doc = ExtractedDocument(
            source_path=str(path),
            file_type="pdf",
            title=path.stem,
            metadata={"filename": path.name},
        )

        try:
            pages = self._extract_with_pdfplumber(file_path)
            if not pages:
                logger.warning(f"pdfplumber returned nothing for {path.name}, trying PyMuPDF…")
                pages = self._extract_with_pymupdf(file_path)

            # If pdfplumber returned only blank pages, fall back to PyMuPDF
            if pages and not any(p.raw_text for p in pages):
                logger.warning(f"pdfplumber returned blank pages for {path.name}, trying PyMuPDF…")
                pymupdf_pages = self._extract_with_pymupdf(file_path)
                if pymupdf_pages and any(p.raw_text for p in pymupdf_pages):
                    pages = pymupdf_pages
                    doc.metadata["extraction_fallback"] = "pymupdf"

            doc.pages = pages
            doc.metadata["total_pages"] = len(pages)

            # Attempt image extraction with PyMuPDF
            if self.enable_images:
                try:
                    self._extract_images(file_path, doc)
                except Exception as img_exc:
                    logger.warning(f"Image extraction failed for {path.name}: {img_exc}")

        except BaseException as exc:
            logger.error(f"PDF extraction failed for {path.name}: {exc}", exc_info=True)
            # Fallback: try basic PyPDF2
            try:
                doc.pages = self._extract_with_pypdf2(file_path)
            except Exception:
                doc.pages = []
            doc.metadata["total_pages"] = len(doc.pages)
            doc.metadata["extraction_fallback"] = "pypdf2"

        logger.info(f"✅ Extracted {len(doc.pages)} pages from {path.name}")
        return doc

    # ────────────────────────────────────────────────────────
    #  pdfplumber  (best text + tables)
    # ────────────────────────────────────────────────────────
    def _extract_with_pdfplumber(self, file_path: str) -> List[ExtractedPage]:
        """Use pdfplumber for precise text blocks + table detection."""
        try:
            import pdfplumber
        except ImportError:
            logger.warning("pdfplumber not installed – skipping")
            return []

        pages: List[ExtractedPage] = []
        try:
            with pdfplumber.open(file_path) as pdf:
                total_pages = len(pdf.pages)
                for page_num, page in enumerate(pdf.pages, start=1):
                    try:
                        ep = self._extract_pdfplumber_page(page, page_num, file_path)
                        pages.append(ep)
                    except Exception as page_exc:
                        logger.warning(
                            f"⚠️ pdfplumber page {page_num}/{total_pages} failed "
                            f"in {Path(file_path).name}: {page_exc}"
                        )
                        # Append an empty page placeholder so numbering stays correct
                        pages.append(ExtractedPage(page_number=page_num))
        except Exception as exc:
            logger.error(f"pdfplumber extraction error for {Path(file_path).name}: {exc}", exc_info=True)

        return pages

    def _extract_pdfplumber_page(
        self, page, page_num: int, file_path: str
    ) -> ExtractedPage:
        """Extract content from a single pdfplumber page (isolated for safety)."""
        ep = ExtractedPage(page_number=page_num)

        # ── Tables ──
        tables = page.extract_tables() or []
        table_bboxes = []
        for tbl in tables:
            if not tbl:
                continue
            md = self._table_to_markdown(tbl)
            if md.strip():
                ep.elements.append(ExtractedElement(
                    content=md,
                    element_type="table",
                    page_number=page_num,
                    metadata={"rows": len(tbl), "cols": len(tbl[0]) if tbl else 0},
                ))
        # Collect table bounding boxes for exclusion
        for t in (page.find_tables() or []):
            table_bboxes.append(t.bbox)

        # ── Text (excluding table regions) ──
        text_page = page
        if table_bboxes:
            for bbox in table_bboxes:
                try:
                    text_page = text_page.outside_bbox(bbox)
                except Exception:
                    pass  # sometimes crop fails on overlapping boxes
        raw_text = (text_page.extract_text() or "").strip()

        if raw_text:
            text_elements = self._parse_text_blocks(raw_text, page_num)
            ep.elements.extend(text_elements)
            ep.raw_text = raw_text

        # ── OCR fallback for scanned / image-only pages ──
        if not raw_text and not tables and self.enable_ocr:
            ocr_text = self._ocr_page(file_path, page_num - 1)  # 0-indexed
            if ocr_text:
                ep.elements.append(ExtractedElement(
                    content=ocr_text,
                    element_type="text",
                    page_number=page_num,
                    metadata={"ocr": True},
                ))
                ep.raw_text = ocr_text

        # composite
        ep.composite_text = "\n\n".join(
            e.content for e in ep.elements
        )
        return ep

    # ────────────────────────────────────────────────────────
    #  PyMuPDF fallback
    # ────────────────────────────────────────────────────────
    def _extract_with_pymupdf(self, file_path: str) -> List[ExtractedPage]:
        """Use PyMuPDF (fitz) as a secondary extractor."""
        try:
            import fitz  # PyMuPDF
        except ImportError:
            logger.warning("PyMuPDF not installed – skipping")
            return []

        pages: List[ExtractedPage] = []
        try:
            pdf = fitz.open(file_path)
            for page_num in range(len(pdf)):
                fitz_page = pdf[page_num]
                text = fitz_page.get_text("text").strip()
                ep = ExtractedPage(page_number=page_num + 1, raw_text=text)

                if text:
                    text_elements = self._parse_text_blocks(text, page_num + 1)
                    ep.elements.extend(text_elements)
                elif self.enable_ocr:
                    ocr_text = self._ocr_page(file_path, page_num)
                    if ocr_text:
                        ep.elements.append(ExtractedElement(
                            content=ocr_text,
                            element_type="text",
                            page_number=page_num + 1,
                            metadata={"ocr": True},
                        ))
                        ep.raw_text = ocr_text

                ep.composite_text = "\n\n".join(e.content for e in ep.elements)
                pages.append(ep)
            pdf.close()
        except Exception as exc:
            logger.error(f"PyMuPDF extraction error: {exc}", exc_info=True)
        return pages

    # ────────────────────────────────────────────────────────
    #  PyPDF2 last-resort fallback
    # ────────────────────────────────────────────────────────
    def _extract_with_pypdf2(self, file_path: str) -> List[ExtractedPage]:
        """Ultra-simple text extraction as last resort."""
        try:
            from PyPDF2 import PdfReader
        except ImportError:
            return []
        pages: List[ExtractedPage] = []
        try:
            reader = PdfReader(file_path)
            for i, page in enumerate(reader.pages):
                text = (page.extract_text() or "").strip()
                ep = ExtractedPage(
                    page_number=i + 1,
                    raw_text=text,
                    composite_text=text,
                    elements=[ExtractedElement(content=text, element_type="text", page_number=i + 1)]
                    if text else [],
                )
                pages.append(ep)
        except Exception as exc:
            logger.error(f"PyPDF2 extraction error: {exc}", exc_info=True)
        return pages

    # ────────────────────────────────────────────────────────
    #  Image extraction (PyMuPDF)
    # ────────────────────────────────────────────────────────
    def _extract_images(self, file_path: str, doc: ExtractedDocument):
        """Extract embedded images, save to disk, and create ImageReferences."""
        try:
            import fitz
        except ImportError:
            return

        try:
            pdf = fitz.open(file_path)
            for page_idx in range(len(pdf)):
                fitz_page = pdf[page_idx]
                images = fitz_page.get_images(full=True)
                for img_idx, img in enumerate(images):
                    try:
                        xref = img[0]
                        pix = fitz.Pixmap(pdf, xref)

                        # Skip tiny images (icons, bullets, etc.)
                        if pix.width < 100 or pix.height < 100:
                            if pix.n > 4:
                                pix = fitz.Pixmap(fitz.csRGB, pix)  # type: ignore[arg-type]
                            pix = None
                            continue

                        # Convert to PNG bytes
                        if pix.n > 4:
                            pix = fitz.Pixmap(fitz.csRGB, pix)  # type: ignore[arg-type]
                        img_bytes = pix.tobytes("png")
                        img_width = pix.width
                        img_height = pix.height
                        pix = None

                        page_num = page_idx + 1

                        # ── Save image to disk ──
                        image_path = ""
                        if self.image_store:
                            image_path = self.image_store.save(
                                img_bytes, file_path, page_num, img_idx,
                            )

                        # ── Vision API description ──
                        description = ""
                        if self.image_describer:
                            description = self.image_describer.describe(
                                img_bytes,
                                context=f"Page {page_num} of {Path(file_path).name}"
                            )

                        # ── Find the target page ──
                        target_page = None
                        for p in doc.pages:
                            if p.page_number == page_num:
                                target_page = p
                                break
                        if target_page is None:
                            target_page = ExtractedPage(page_number=page_num)
                            doc.pages.append(target_page)

                        # ── Build contextual caption from page content ──
                        context_parts = []
                        # Page headings
                        page_headings = [
                            e.content for e in target_page.elements
                            if e.element_type == "heading"
                        ]
                        if page_headings:
                            context_parts.append(" > ".join(page_headings))
                        # Page text (first 300 chars)
                        page_text = (target_page.raw_text or "").strip()
                        if page_text:
                            context_parts.append(page_text[:300])
                        if not context_parts:
                            context_parts.append(
                                f"Page {page_num} of {Path(file_path).name}"
                            )
                        caption = " | ".join(context_parts)

                        # ── Build ImageReference ──
                        img_ref = ImageReference(
                            image_path=image_path,
                            page_number=page_num,
                            caption=caption,
                            ocr_text="",
                            description=description,
                            width=img_width,
                            height=img_height,
                        )

                        # ── Add element to page ──
                        display_text = description or caption
                        target_page.elements.append(ExtractedElement(
                            content=f"[Image: {display_text}]",
                            element_type="image",
                            page_number=page_num,
                            metadata={
                                "image_index": img_idx,
                                "width": img_width,
                                "height": img_height,
                                "description": description,
                                "caption": caption,
                                "image_path": image_path,
                                "image_ref": img_ref.to_dict(),
                            },
                        ))
                    except Exception as exc:
                        logger.debug(f"Skipping image {img_idx} on page {page_idx + 1}: {exc}")
            pdf.close()
        except Exception as exc:
            logger.warning(f"Image extraction failed: {exc}")

    # ────────────────────────────────────────────────────────
    #  OCR helper
    # ────────────────────────────────────────────────────────
    def _ocr_page(self, file_path: str, page_index: int) -> str:
        """OCR a single page using PyMuPDF + pytesseract."""
        try:
            import fitz
            from PIL import Image
            import pytesseract

            pdf = fitz.open(file_path)
            page = pdf[page_index]
            pix = page.get_pixmap(dpi=300)
            img = Image.open(io.BytesIO(pix.tobytes("png")))
            pdf.close()

            text = pytesseract.image_to_string(img).strip()
            if len(text) > 20:  # Only return meaningful OCR results
                return text
        except Exception as exc:
            logger.debug(f"OCR failed for page {page_index}: {exc}")
        return ""

    # ────────────────────────────────────────────────────────
    #  Text block parsing (heading detection)
    # ────────────────────────────────────────────────────────
    def _parse_text_blocks(self, text: str, page_number: int) -> List[ExtractedElement]:
        """Split raw text into headings + paragraphs."""
        elements: List[ExtractedElement] = []
        lines = text.split("\n")
        current_block: List[str] = []

        heading_pattern = re.compile(
            r"^(\d+\.?\s+|[A-Z][A-Z\s]{3,}$|[A-Z][a-z].*:$|#{1,4}\s)"
        )

        for line in lines:
            stripped = line.strip()
            if not stripped:
                # Flush block
                if current_block:
                    block_text = "\n".join(current_block).strip()
                    if block_text:
                        elements.append(ExtractedElement(
                            content=block_text,
                            element_type="text",
                            page_number=page_number,
                        ))
                    current_block = []
                continue

            # Check if this looks like a heading
            if heading_pattern.match(stripped) and len(stripped) < 120:
                # Flush previous block
                if current_block:
                    block_text = "\n".join(current_block).strip()
                    if block_text:
                        elements.append(ExtractedElement(
                            content=block_text,
                            element_type="text",
                            page_number=page_number,
                        ))
                    current_block = []
                # Add heading
                level = 1 if stripped.isupper() else 2
                elements.append(ExtractedElement(
                    content=stripped,
                    element_type="heading",
                    page_number=page_number,
                    metadata={"heading_level": level},
                ))
            else:
                current_block.append(stripped)

        # Flush remaining
        if current_block:
            block_text = "\n".join(current_block).strip()
            if block_text:
                elements.append(ExtractedElement(
                    content=block_text,
                    element_type="text",
                    page_number=page_number,
                ))

        return elements

    # ────────────────────────────────────────────────────────
    #  Table → Markdown
    # ────────────────────────────────────────────────────────
    @staticmethod
    def _table_to_markdown(table: list) -> str:
        """Convert a pdfplumber table (list of rows) to Markdown."""
        if not table:
            return ""

        def clean(cell):
            if cell is None:
                return ""
            return str(cell).replace("\n", " ").strip()

        rows = [[clean(c) for c in row] for row in table]
        if not rows:
            return ""

        # Header
        header = rows[0]
        md = "| " + " | ".join(header) + " |\n"
        md += "| " + " | ".join("---" for _ in header) + " |\n"
        for row in rows[1:]:
            # Pad / truncate row to match header width
            padded = row + [""] * (len(header) - len(row)) if len(row) < len(header) else row[:len(header)]
            md += "| " + " | ".join(padded) + " |\n"
        return md.strip()
