"""
Image Display Decision Engine — Decide which images to show in responses.

Analyses retrieved chunks, collects image references, deduplicates,
ranks by relevance, and returns a prioritised list for the frontend.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from ..models import ImageReference, RetrievedChunk

logger = logging.getLogger(__name__)

# ── Defaults ──
MAX_DISPLAY_IMAGES = 5          # Show at most N images per response
MIN_CHUNK_SCORE = 0.30          # Ignore images from low-relevance chunks
MIN_IMAGE_SIZE = 100             # Skip images smaller than NxN pixels
MIN_BRIGHTNESS = 15             # Average pixel brightness (0-255); below = dark/blank image

# Project-root-relative data directory for resolving image paths
_DATA_ROOT = Path(__file__).resolve().parents[4] / "data"


@dataclass
class DisplayImage:
    """An image recommended for display in the response."""
    image_path: str              # relative path (e.g. extracted_images/hash/p3_0.png)
    page_number: int = 0
    caption: str = ""            # caption or description
    source_document: str = ""    # document filename
    relevance_score: float = 0.0 # inherited from parent chunk's retrieval score
    width: int = 0
    height: int = 0

    def to_dict(self) -> Dict:
        return {
            "image_path": self.image_path,
            "page_number": self.page_number,
            "caption": self.caption,
            "source_document": self.source_document,
            "relevance_score": round(self.relevance_score, 3),
            "width": self.width,
            "height": self.height,
        }


class ImageDisplayEngine:
    """Decide which images from retrieved chunks to show in the response."""

    def __init__(
        self,
        *,
        max_images: int = MAX_DISPLAY_IMAGES,
        min_chunk_score: float = MIN_CHUNK_SCORE,
        min_image_size: int = MIN_IMAGE_SIZE,
        min_brightness: int = MIN_BRIGHTNESS,
        data_root: Optional[Path] = None,
    ):
        self.max_images = max_images
        self.min_chunk_score = min_chunk_score
        self.min_size = min_image_size
        self.min_brightness = min_brightness
        self.data_root = Path(data_root) if data_root else _DATA_ROOT

    def select_images(
        self,
        chunks: List[RetrievedChunk],
        query: str = "",
    ) -> List[DisplayImage]:
        """
        Collect, deduplicate, and rank images from retrieved chunks.

        Args:
            chunks: Reranked retrieved chunks (with images and scores).
            query:  The user's query (reserved for future query-image matching).

        Returns:
            Ordered list of DisplayImage objects (best first), capped at
            ``max_images``.
        """
        candidates: List[DisplayImage] = []
        seen_paths: set = set()

        for chunk in chunks:
            # Skip low-relevance chunks
            if chunk.score < self.min_chunk_score:
                continue

            images = chunk.images or []
            if not images:
                continue

            source_doc = self._source_filename(chunk)

            for img_ref in images:
                # Skip already-seen paths (dedup)
                if img_ref.image_path in seen_paths or not img_ref.image_path:
                    continue

                # Skip tiny images
                if img_ref.width and img_ref.height:
                    if img_ref.width < self.min_size or img_ref.height < self.min_size:
                        continue

                # Skip dark or blank images (renders as solid black in UI)
                if self._is_dark_or_blank(img_ref.image_path):
                    logger.debug(f"🚫 Skipping dark/blank image: {img_ref.image_path}")
                    continue

                seen_paths.add(img_ref.image_path)

                caption = (
                    img_ref.caption
                    or img_ref.description
                    or img_ref.get_searchable_text()
                    or ""
                )

                candidates.append(DisplayImage(
                    image_path=img_ref.image_path,
                    page_number=img_ref.page_number,
                    caption=caption,
                    source_document=source_doc,
                    relevance_score=chunk.score,
                    width=img_ref.width,
                    height=img_ref.height,
                ))

        # ── Caption-based dedup: remove near-duplicate images from the same page ──
        candidates = self._dedup_by_caption(candidates)

        # ── Diversity-aware ranking ──
        # Sort by relevance first, then apply diversity re-ranking
        candidates.sort(key=lambda d: (-d.relevance_score, d.page_number))
        selected = self._select_diverse(candidates, self.max_images)

        logger.info(
            f"🖼️ Image selection: {len(candidates)} candidates → "
            f"{len(selected)} displayed (from {len(chunks)} chunks)"
        )
        return selected

    # ────────────────────────────────────────────────────
    #  Helpers
    # ────────────────────────────────────────────────────

    def _is_dark_or_blank(self, image_path: str) -> bool:
        """
        Return True when an image is mostly dark/blank and not useful to display.

        Tries to open the image from disk and checks average brightness.
        Falls back to False (keep the image) if PIL is unavailable or the
        file cannot be read, so that missing PIL never blocks the pipeline.
        """
        try:
            from PIL import Image
            import numpy as np

            # Resolve absolute path: image_path is relative to data_root's parent
            # Stored as e.g. "extracted_images/abc123/p3_0.png"
            abs_path = self.data_root / image_path
            if not abs_path.exists():
                return False  # Can't check — don't block it

            with Image.open(abs_path) as img:
                # Convert to grayscale for brightness check
                gray = img.convert("L")
                pixels = list(gray.getdata())
                if not pixels:
                    return True  # Empty image
                avg_brightness = sum(pixels) / len(pixels)

            if avg_brightness < self.min_brightness:
                logger.info(
                    f"🖤 Filtered dark image (brightness={avg_brightness:.1f}): {image_path}"
                )
                return True

            # Also check if image is nearly uniform (solid colour — usually blank slides)
            arr = list(gray.getdata())
            pixel_range = max(arr) - min(arr)
            if pixel_range < 10 and avg_brightness < 30:
                logger.info(
                    f"⬛ Filtered uniform/blank image (range={pixel_range}): {image_path}"
                )
                return True

            return False

        except ImportError:
            # PIL not installed — skip brightness check silently
            return False
        except Exception as exc:
            logger.debug(f"Could not brightness-check {image_path}: {exc}")
            return False

    @staticmethod
    def _caption_similarity(a: str, b: str) -> float:
        """Word-overlap ratio between two captions (Jaccard-like)."""
        words_a = set(a.lower().split())
        words_b = set(b.lower().split())
        if not words_a or not words_b:
            return 0.0
        intersection = words_a & words_b
        return len(intersection) / max(len(words_a), len(words_b))

    @classmethod
    def _dedup_by_caption(cls, candidates: List[DisplayImage]) -> List[DisplayImage]:
        """
        Remove images with near-identical captions from the same page/document.
        
        When a slide has 3+ images with the same contextual caption (because
        they share slide title/notes), keep only the largest one.
        """
        if len(candidates) <= 1:
            return candidates

        # Group by (source_document, page_number)
        page_groups: Dict[tuple, List[DisplayImage]] = {}
        for img in candidates:
            key = (img.source_document, img.page_number)
            page_groups.setdefault(key, []).append(img)

        deduped: List[DisplayImage] = []
        for _key, group in page_groups.items():
            if len(group) <= 1:
                deduped.extend(group)
                continue

            # Within the page group, cluster by caption similarity
            kept: List[DisplayImage] = []
            for img in group:
                is_dup = False
                for existing in kept:
                    if cls._caption_similarity(img.caption, existing.caption) > 0.80:
                        # Keep the one with larger area
                        img_area = (img.width or 0) * (img.height or 0)
                        existing_area = (existing.width or 0) * (existing.height or 0)
                        if img_area > existing_area:
                            kept.remove(existing)
                            kept.append(img)
                        is_dup = True
                        break
                if not is_dup:
                    kept.append(img)
            deduped.extend(kept)

        return deduped

    @staticmethod
    def _select_diverse(
        candidates: List[DisplayImage], max_images: int
    ) -> List[DisplayImage]:
        """
        Select up to `max_images` favouring diversity across documents and pages.
        
        Uses a round-robin approach: pick one image per document, then cycle,
        so images from multiple source documents appear before duplicates.
        """
        if len(candidates) <= max_images:
            return candidates

        # Build per-document queues (maintain relevance order within each doc)
        doc_queues: Dict[str, List[DisplayImage]] = {}
        for img in candidates:
            doc_queues.setdefault(img.source_document, []).append(img)

        selected: List[DisplayImage] = []
        selected_pages: set = set()

        # Round-robin across documents
        while len(selected) < max_images and any(doc_queues.values()):
            for doc_name in list(doc_queues.keys()):
                queue = doc_queues[doc_name]
                if not queue:
                    del doc_queues[doc_name]
                    continue
                # Prefer an image from a page we haven't seen
                picked = None
                for i, img in enumerate(queue):
                    page_key = (img.source_document, img.page_number)
                    if page_key not in selected_pages:
                        picked = queue.pop(i)
                        break
                if picked is None:
                    picked = queue.pop(0)
                selected_pages.add((picked.source_document, picked.page_number))
                selected.append(picked)
                if len(selected) >= max_images:
                    break

        return selected

    @staticmethod
    def _source_filename(chunk: RetrievedChunk) -> str:
        """Extract a human-friendly source filename."""
        fn = chunk.metadata.get("filename", "")
        if fn:
            return fn
        if chunk.source_path:
            import os
            return os.path.basename(chunk.source_path)
        return "Unknown"
