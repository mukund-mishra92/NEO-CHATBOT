"""
Hierarchical Chunker — 3-level document chunking with parent-child references.

Levels:
  0 — Document summary (auto-generated)
  1 — Section  (bounded by headings & page breaks)
  2 — Paragraph / leaf chunk (sentence-boundary-aware, max ~800 tokens)

Each chunk carries:
  • parent_id / children_ids for context expansion
  • section_path breadcrumb  (e.g. ["Ch1", "Architecture", "Overview"])
  • page_numbers
  • element_types present in the chunk
"""

from __future__ import annotations

import hashlib
import logging
import re
import uuid
from typing import Dict, List, Optional, Tuple

from ..models import (
    ExtractedDocument,
    ExtractedElement,
    ExtractedPage,
    HierarchicalChunk,
    ImageReference,
)

logger = logging.getLogger(__name__)

# ════════════════════════════════════════════════════════════════
#  Defaults
# ════════════════════════════════════════════════════════════════
DEFAULT_SECTION_MAX_CHARS = 3000    # Level-1 section chunk
DEFAULT_PARAGRAPH_MAX_CHARS = 1200  # Level-2 leaf chunk
DEFAULT_OVERLAP_CHARS = 150         # Overlap between consecutive leaf chunks
MIN_CHUNK_CHARS = 60                # Ignore tiny fragments


class HierarchicalChunker:
    """Split an ExtractedDocument into a tree of HierarchicalChunks."""

    def __init__(
        self,
        *,
        section_max_chars: int = DEFAULT_SECTION_MAX_CHARS,
        paragraph_max_chars: int = DEFAULT_PARAGRAPH_MAX_CHARS,
        overlap_chars: int = DEFAULT_OVERLAP_CHARS,
    ):
        self.section_max = section_max_chars
        self.para_max = paragraph_max_chars
        self.overlap = overlap_chars

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def chunk(self, doc: ExtractedDocument) -> List[HierarchicalChunk]:
        """
        Chunk a document into hierarchical pieces.

        Returns list of HierarchicalChunk ordered: [doc_summary, sections…, paras…]
        """
        document_id = self._doc_id(doc)
        all_chunks: List[HierarchicalChunk] = []

        # ── Level 0: Document summary ──
        summary_text = self._build_doc_summary(doc)
        doc_chunk = HierarchicalChunk(
            chunk_id=f"{document_id}__L0",
            content=summary_text,
            level=0,
            document_id=document_id,
            source_path=doc.source_path,
            section_path=[doc.title or doc.metadata.get("filename", "unknown")],
            page_numbers=list(range(1, len(doc.pages) + 1)),
            element_types=["summary"],
            metadata={
                **doc.metadata,
                "category": doc.metadata.get("category", ""),
                "file_type": doc.file_type,
            },
        )
        all_chunks.append(doc_chunk)

        # ── Level 1: Sections (bounded by headings) ──
        sections = self._split_into_sections(doc)
        for sec_idx, section in enumerate(sections):
            sec_id = f"{document_id}__L1_S{sec_idx}"
            sec_text = section["text"]
            sec_pages = section["pages"]
            sec_path = section["path"]
            sec_types = section["element_types"]
            sec_images: List[ImageReference] = section.get("images", [])

            # Truncate oversized sections
            if len(sec_text) > self.section_max:
                sec_text = sec_text[: self.section_max]

            sec_chunk = HierarchicalChunk(
                chunk_id=sec_id,
                content=sec_text,
                level=1,
                parent_id=doc_chunk.chunk_id,
                document_id=document_id,
                source_path=doc.source_path,
                section_path=sec_path,
                page_numbers=sec_pages,
                element_types=sec_types,
                metadata={
                    **doc.metadata,
                    "section_index": sec_idx,
                    "file_type": doc.file_type,
                },
                images=sec_images,
                image_count=len(sec_images),
            )
            # Build combined_content for richer embeddings
            if sec_images:
                img_texts = [img.get_searchable_text() for img in sec_images]
                combined_parts = [sec_text] + [f"[Image: {t}]" for t in img_texts if t]
                sec_chunk.combined_content = "\n".join(combined_parts)

            doc_chunk.children_ids.append(sec_id)
            all_chunks.append(sec_chunk)

            # ── Level 2: Paragraph / leaf chunks ──
            leaves = self._split_section_into_leaves(section["text"])
            # Distribute images across leaves (assign to first leaf, or spread by page)
            leaf_images = self._distribute_images_to_leaves(
                sec_images, leaves, len(leaves)
            )
            for leaf_idx, leaf_text in enumerate(leaves):
                leaf_id = f"{document_id}__L2_S{sec_idx}_P{leaf_idx}"
                l2_images = leaf_images.get(leaf_idx, [])
                leaf_chunk = HierarchicalChunk(
                    chunk_id=leaf_id,
                    content=leaf_text,
                    level=2,
                    parent_id=sec_id,
                    document_id=document_id,
                    source_path=doc.source_path,
                    section_path=sec_path,
                    page_numbers=sec_pages,
                    element_types=sec_types,
                    metadata={
                        **doc.metadata,
                        "section_index": sec_idx,
                        "paragraph_index": leaf_idx,
                        "file_type": doc.file_type,
                    },
                    images=l2_images,
                    image_count=len(l2_images),
                )
                if l2_images:
                    img_texts = [img.get_searchable_text() for img in l2_images]
                    combined = [leaf_text] + [f"[Image: {t}]" for t in img_texts if t]
                    leaf_chunk.combined_content = "\n".join(combined)

                sec_chunk.children_ids.append(leaf_id)
                all_chunks.append(leaf_chunk)

        logger.info(
            f"✅ Chunked {doc.metadata.get('filename', '?')}: "
            f"1 summary + {len(sections)} sections + "
            f"{sum(1 for c in all_chunks if c.level == 2)} paragraphs"
        )
        return all_chunks

    # ────────────────────────────────────────────────────
    #  Doc summary (Level 0)
    # ────────────────────────────────────────────────────
    def _build_doc_summary(self, doc: ExtractedDocument) -> str:
        """Build a compact document-level summary from headings + first paragraphs."""
        parts = [f"Document: {doc.title or doc.metadata.get('filename', 'unknown')}"]
        if doc.metadata.get("category"):
            parts.append(f"Category: {doc.metadata['category']}")
        parts.append(f"Type: {doc.file_type.upper()}, Pages: {len(doc.pages)}")
        parts.append("")

        # Collect headings + first 200 chars of each section
        heading_texts = []
        for page in doc.pages:
            for elem in page.elements:
                if elem.element_type == "heading":
                    heading_texts.append(elem.content)
                    # First paragraph after heading
                elif elem.element_type == "text" and len(heading_texts) > len(parts) - 4:
                    parts.append(f"  {elem.content[:200]}")

        if heading_texts:
            parts.append("Sections: " + " | ".join(heading_texts[:20]))

        summary = "\n".join(parts)
        # Cap at 1500 chars
        return summary[:1500] if len(summary) > 1500 else summary

    # ────────────────────────────────────────────────────
    #  Section splitting (Level 1)
    # ────────────────────────────────────────────────────
    def _split_into_sections(self, doc: ExtractedDocument) -> List[Dict]:
        """
        Split document into sections bounded by headings.

        Each section = {text, pages, path, element_types, images}
        """
        sections: List[Dict] = []
        current_section: Dict = {
            "text": "",
            "pages": [],
            "path": [doc.title or "untitled"],
            "element_types": [],
            "images": [],
        }

        for page in doc.pages:
            for elem in page.elements:
                # Collect ImageReference from image elements
                if elem.element_type == "image":
                    img_ref = self._image_ref_from_element(elem)
                    if img_ref:
                        current_section["images"].append(img_ref)

                if elem.element_type == "heading":
                    level = elem.metadata.get("heading_level", 2)
                    # Flush current section (if it has enough text or images)
                    orphan_images: List[ImageReference] = []
                    if len(current_section["text"].strip()) > MIN_CHUNK_CHARS:
                        sections.append(current_section)
                    elif current_section.get("images"):
                        # Section too short but has images — carry them forward
                        orphan_images = current_section["images"]

                    # Start new section
                    base_path = current_section["path"][:level]  # trim to parent heading level
                    new_path = base_path + [elem.content]

                    current_section = {
                        "text": elem.content + "\n\n",
                        "pages": [page.page_number],
                        "path": new_path,
                        "element_types": ["heading"],
                        "images": orphan_images,  # inherit orphaned images
                    }
                else:
                    # Append to current section
                    sep = "\n\n" if elem.element_type == "table" else "\n"
                    current_section["text"] += elem.content + sep
                    if page.page_number not in current_section["pages"]:
                        current_section["pages"].append(page.page_number)
                    if elem.element_type not in current_section["element_types"]:
                        current_section["element_types"].append(elem.element_type)

        # Flush last section (also keep if it has images, even with short text)
        if len(current_section["text"].strip()) > MIN_CHUNK_CHARS or current_section.get("images"):
            sections.append(current_section)

        # If no sections found (no headings), create one big section
        if not sections:
            all_text = "\n".join(
                p.composite_text for p in doc.pages if p.composite_text
            )
            all_images = []
            for p in doc.pages:
                for e in p.elements:
                    if e.element_type == "image":
                        img_ref = self._image_ref_from_element(e)
                        if img_ref:
                            all_images.append(img_ref)
            sections.append({
                "text": all_text,
                "pages": [p.page_number for p in doc.pages],
                "path": [doc.title or "untitled"],
                "element_types": list({
                    e.element_type for p in doc.pages for e in p.elements
                }),
                "images": all_images,
            })

        return sections

    # ────────────────────────────────────────────────────
    #  Leaf splitting (Level 2) — sentence-boundary aware
    # ────────────────────────────────────────────────────
    def _split_section_into_leaves(self, text: str) -> List[str]:
        """Split section text into paragraph-sized leaf chunks with overlap."""
        if len(text) <= self.para_max:
            return [text.strip()] if text.strip() else []

        # Split on sentence boundaries
        sentences = re.split(r'(?<=[.!?])\s+', text)
        chunks: List[str] = []
        current: List[str] = []
        current_len = 0

        for sent in sentences:
            sent = sent.strip()
            if not sent:
                continue

            if current_len + len(sent) + 1 > self.para_max and current:
                # Flush
                chunk_text = " ".join(current).strip()
                if len(chunk_text) >= MIN_CHUNK_CHARS:
                    chunks.append(chunk_text)

                # Overlap: keep last few sentences
                overlap_sents: List[str] = []
                overlap_len = 0
                for s in reversed(current):
                    if overlap_len + len(s) > self.overlap:
                        break
                    overlap_sents.insert(0, s)
                    overlap_len += len(s) + 1

                current = overlap_sents
                current_len = overlap_len

            current.append(sent)
            current_len += len(sent) + 1

        # Flush remaining
        if current:
            chunk_text = " ".join(current).strip()
            if len(chunk_text) >= MIN_CHUNK_CHARS:
                chunks.append(chunk_text)

        return chunks if chunks else ([text.strip()] if text.strip() else [])

    # ────────────────────────────────────────────────────
    #  Helpers
    # ────────────────────────────────────────────────────
    @staticmethod
    def _image_ref_from_element(elem: ExtractedElement) -> Optional[ImageReference]:
        """Extract an ImageReference from an image ExtractedElement's metadata."""
        meta = elem.metadata
        if not meta:
            return None

        # Prefer pre-built dict stored by the extractor
        ref_dict = meta.get("image_ref")
        if ref_dict and isinstance(ref_dict, dict):
            return ImageReference.from_dict(ref_dict)

        # Fallback: reconstruct from individual metadata fields
        image_path = meta.get("image_path", "")
        if not image_path:
            return None

        return ImageReference(
            image_path=image_path,
            page_number=elem.page_number,
            description=meta.get("description", ""),
            width=meta.get("width", 0),
            height=meta.get("height", 0),
        )

    @staticmethod
    def _distribute_images_to_leaves(
        images: List[ImageReference],
        leaves: List[str],
        num_leaves: int,
    ) -> Dict[int, List[ImageReference]]:
        """
        Assign section-level images to leaf chunks.

        Simple heuristic: all images go to the first leaf (index 0)
        since we don't have fine-grained positional data.
        If the section has only one leaf, all images are on that leaf.
        """
        if not images or num_leaves == 0:
            return {}
        # Assign all to first leaf (keeps text+image together for retrieval)
        return {0: images}

    @staticmethod
    def _doc_id(doc: ExtractedDocument) -> str:
        """Generate a stable document ID from path."""
        raw = doc.source_path or doc.metadata.get("filename", str(uuid.uuid4()))
        return hashlib.sha256(raw.encode()).hexdigest()[:16]
