"""
Image Store — Save extracted images to disk for later retrieval.

Images are stored in a deterministic path structure:
  data/extracted_images/{doc_hash}/{page}_{index}.png

This enables the frontend to request images by path after retrieval.
"""

from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Default root for saved images (relative to project root)
DEFAULT_IMAGE_DIR = str(
    Path(__file__).resolve().parents[4] / "data" / "extracted_images"
)


class ImageStore:
    """Persist extracted images to disk and return stable paths."""

    def __init__(self, base_dir: Optional[str] = None):
        self.base_dir = Path(base_dir or DEFAULT_IMAGE_DIR)
        self.base_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"ImageStore root: {self.base_dir}")

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def save(
        self,
        image_bytes: bytes,
        doc_path: str,
        page_number: int,
        image_index: int,
        *,
        ext: str = "png",
    ) -> str:
        """
        Save image bytes and return a *relative* path (from project root).

        Args:
            image_bytes: Raw PNG/JPEG bytes.
            doc_path:    Source document path (used to derive a doc hash).
            page_number: 1-based page number.
            image_index: 0-based index within the page.
            ext:         File extension (default: png).

        Returns:
            Relative path string like ``extracted_images/a1b2c3d4/p3_0.png``.
        """
        doc_hash = self._doc_hash(doc_path)
        doc_dir = self.base_dir / doc_hash
        doc_dir.mkdir(parents=True, exist_ok=True)

        filename = f"p{page_number}_{image_index}.{ext}"
        abs_path = doc_dir / filename

        try:
            abs_path.write_bytes(image_bytes)
            # Return path relative to the project's data/ root
            rel = f"extracted_images/{doc_hash}/{filename}"
            logger.debug(f"💾 Saved image: {rel} ({len(image_bytes)} bytes)")
            return rel
        except Exception as exc:
            logger.warning(f"Failed to save image {filename}: {exc}")
            return ""

    def get_absolute_path(self, relative_path: str) -> Path:
        """Convert a relative image path to an absolute path."""
        # relative_path is like "extracted_images/hash/p3_0.png"
        # base_dir already points to data/extracted_images
        # So strip the prefix and join
        stripped = relative_path.replace("extracted_images/", "", 1)
        return self.base_dir / stripped

    def exists(self, relative_path: str) -> bool:
        """Check if an image file exists."""
        return self.get_absolute_path(relative_path).exists()

    # ────────────────────────────────────────────────────
    #  Helpers
    # ────────────────────────────────────────────────────
    @staticmethod
    def _doc_hash(doc_path: str) -> str:
        """Deterministic 12-char hash for a document path."""
        return hashlib.sha256(doc_path.encode()).hexdigest()[:12]
