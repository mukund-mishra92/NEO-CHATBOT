"""
Image Describer — Uses OpenAI Vision API to describe images.

Converts image bytes to a text description that can be embedded
and searched alongside regular text content.
"""

from __future__ import annotations

import base64
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)


class ImageDescriber:
    """Describe images using OpenAI gpt-4o-mini Vision API."""

    def __init__(self, *, model: str = "gpt-4o-mini", max_tokens: int = 200):
        self.model = model
        self.max_tokens = max_tokens
        self._client = None
        self._init_client()

    def _init_client(self):
        """Initialize OpenAI client."""
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            logger.warning("⚠️ OPENAI_API_KEY not set — image descriptions disabled")
            return
        try:
            from openai import OpenAI
            self._client = OpenAI(api_key=api_key)
            logger.info("✅ ImageDescriber initialized with Vision API")
        except ImportError:
            logger.warning("openai package not installed — image descriptions disabled")
        except Exception as exc:
            logger.warning(f"Failed to init OpenAI client: {exc}")

    @property
    def is_available(self) -> bool:
        return self._client is not None

    def describe(self, image_bytes: bytes, context: str = "") -> str:
        """
        Generate a text description of an image.

        Args:
            image_bytes: Raw bytes of the image (PNG/JPEG).
            context: Optional context (e.g., "Slide 5 of Training.pptx").

        Returns:
            Text description or empty string on failure.
        """
        if not self._client:
            return ""

        try:
            b64 = base64.b64encode(image_bytes).decode("utf-8")
            # Detect content type
            content_type = "image/png"
            if image_bytes[:3] == b"\xff\xd8\xff":
                content_type = "image/jpeg"

            prompt = (
                "Describe this image concisely in 1-3 sentences. "
                "Focus on: what it shows, key data/labels, and any text visible. "
                "If it's a diagram or flowchart, describe the main components and flow. "
                "If it's a chart/graph, mention the type, axes, and key trends."
            )
            if context:
                prompt += f"\nContext: {context}"

            response = self._client.chat.completions.create(
                model=self.model,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{content_type};base64,{b64}",
                                "detail": "low",  # Cheaper, sufficient for descriptions
                            },
                        },
                    ],
                }],
                max_tokens=self.max_tokens,
            )
            description = response.choices[0].message.content.strip()
            logger.debug(f"🖼️ Image described: {description[:80]}…")
            return description

        except Exception as exc:
            logger.warning(f"Vision API description failed: {exc}")
            return ""
