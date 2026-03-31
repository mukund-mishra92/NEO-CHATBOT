"""
Data models shared across the ingestion pipeline.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional, Tuple


# ════════════════════════════════════════════════════════════════
#  Extraction Models
# ════════════════════════════════════════════════════════════════

@dataclass
class ExtractedElement:
    """A single piece of content extracted from a page/slide."""
    content: str                             # text / markdown table / image description
    element_type: str                        # "text", "heading", "table", "image", "list", "code"
    page_number: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)
    # metadata may contain: heading_level, table_shape, image_path,
    # table_headers, list_type, code_language, etc.


@dataclass
class ExtractedPage:
    """All content from a single PDF page or PPT slide."""
    page_number: int
    elements: List[ExtractedElement] = field(default_factory=list)
    raw_text: str = ""                       # fallback plain text
    composite_text: str = ""                 # all elements merged as text


@dataclass
class ExtractedDocument:
    """Entire extracted document."""
    source_path: str
    file_type: str                           # "pdf", "docx", "pptx", "sql", "code"
    title: str = ""
    pages: List[ExtractedPage] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    # metadata: category, author, created_date, total_pages, etc.


# ════════════════════════════════════════════════════════════════
#  Multimodal Models
# ════════════════════════════════════════════════════════════════

@dataclass
class ImageReference:
    """
    Metadata for an image extracted from a document.

    Stores the image file path (relative to the project's image store),
    page context, spatial location, and any text derived from OCR or
    captions so the image can be linked back to its surrounding content.
    """
    image_path: str                          # relative path to saved image file
    page_number: int = 0
    bbox: Optional[Tuple[float, float, float, float]] = None  # (x0, y0, x1, y1)
    caption: str = ""                        # caption found near the image
    ocr_text: str = ""                       # OCR-extracted text from the image
    description: str = ""                    # LLM-generated or heuristic description
    width: int = 0
    height: int = 0

    # ── Serialisation helpers (ChromaDB only supports primitives) ──

    def to_dict(self) -> Dict[str, Any]:
        """Serialise to a JSON-friendly dict."""
        return {
            "image_path": self.image_path,
            "page_number": self.page_number,
            "bbox": list(self.bbox) if self.bbox else None,
            "caption": self.caption,
            "ocr_text": self.ocr_text,
            "description": self.description,
            "width": self.width,
            "height": self.height,
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ImageReference":
        """Deserialise from a dict (e.g. loaded from JSON metadata)."""
        bbox = tuple(d["bbox"]) if d.get("bbox") else None
        return cls(
            image_path=d.get("image_path", ""),
            page_number=d.get("page_number", 0),
            bbox=bbox,
            caption=d.get("caption", ""),
            ocr_text=d.get("ocr_text", ""),
            description=d.get("description", ""),
            width=d.get("width", 0),
            height=d.get("height", 0),
        )

    def get_searchable_text(self) -> str:
        """Return all textual content associated with this image."""
        parts = [self.caption, self.ocr_text, self.description]
        return " ".join(p for p in parts if p).strip()


@dataclass
class CompositeBlock:
    """
    A spatially-grouped block of content from a single page/slide
    that may contain both text and images in close proximity.

    The chunker uses these to keep images anchored to the text that
    explains them, rather than treating images as isolated elements.
    """
    text: str = ""
    images: List[ImageReference] = field(default_factory=list)
    page_number: int = 0
    bbox: Optional[Tuple[float, float, float, float]] = None
    block_type: str = "mixed"                # "text", "image", "mixed", "table"

    @property
    def has_images(self) -> bool:
        return len(self.images) > 0

    def get_combined_text(self) -> str:
        """Merge block text with image-derived text for embedding."""
        parts = [self.text]
        for img in self.images:
            img_text = img.get_searchable_text()
            if img_text:
                parts.append(f"[Image: {img_text}]")
        return "\n".join(p for p in parts if p).strip()


# ════════════════════════════════════════════════════════════════
#  Chunking Models
# ════════════════════════════════════════════════════════════════

@dataclass
class HierarchicalChunk:
    """A chunk with parent/child hierarchy and optional image references."""
    chunk_id: str
    content: str
    level: int                               # 0=doc_summary, 1=section, 2=paragraph
    parent_id: Optional[str] = None
    children_ids: List[str] = field(default_factory=list)
    document_id: str = ""
    source_path: str = ""
    section_path: List[str] = field(default_factory=list)   # ["Ch1", "Architecture", "Overview"]
    page_numbers: List[int] = field(default_factory=list)
    element_types: List[str] = field(default_factory=list)  # ["text", "table"]
    metadata: Dict[str, Any] = field(default_factory=dict)
    # metadata: category, file_type, heading, chart_type, etc.

    # ── Multimodal fields ──
    images: List[ImageReference] = field(default_factory=list)
    image_count: int = 0
    combined_content: Optional[str] = None   # text + image-derived text for embedding

    @property
    def has_images(self) -> bool:
        return self.image_count > 0 or len(self.images) > 0

    def get_embeddable_content(self) -> str:
        """Return combined_content if available, else plain content."""
        return self.combined_content or self.content

    def serialise_images_json(self) -> str:
        """Serialise image list to JSON string (for ChromaDB metadata)."""
        if not self.images:
            return "[]"
        return json.dumps([img.to_dict() for img in self.images])

    @staticmethod
    def deserialise_images_json(raw: str) -> List["ImageReference"]:
        """Deserialise image list from JSON string."""
        if not raw or raw == "[]":
            return []
        try:
            items = json.loads(raw)
            return [ImageReference.from_dict(d) for d in items]
        except (json.JSONDecodeError, TypeError):
            return []


# ════════════════════════════════════════════════════════════════
#  Retrieval Models
# ════════════════════════════════════════════════════════════════

@dataclass
class RetrievedChunk:
    """A chunk returned by the retriever, optionally with image refs."""
    chunk_id: str
    content: str
    score: float
    level: int = 2
    parent_id: Optional[str] = None
    document_id: str = ""
    source_path: str = ""
    section_path: List[str] = field(default_factory=list)
    page_numbers: List[int] = field(default_factory=list)
    element_types: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    # ── Multimodal fields ──
    images: List[ImageReference] = field(default_factory=list)
    image_count: int = 0

    @property
    def has_images(self) -> bool:
        return self.image_count > 0 or len(self.images) > 0


@dataclass
class Source:
    """Citation source for answers."""
    document_title: str
    source_path: str
    page_numbers: List[int]
    section: str = ""
    relevance_score: float = 0.0


@dataclass
class SynthesizedAnswer:
    """Final answer with citations."""
    answer: str
    confidence: float
    sources: List[Source] = field(default_factory=list)
    has_sufficient_evidence: bool = True
    suggested_followups: List[str] = field(default_factory=list)
    retrieved_chunks: List[RetrievedChunk] = field(default_factory=list)
