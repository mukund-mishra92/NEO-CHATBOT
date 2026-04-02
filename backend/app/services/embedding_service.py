# app/services/embedding_service.py

from typing import List
import logging
import numpy as np
from openai import OpenAI
from app.core.config import settings
from app.services.ai_config_service import get_ai_config_service

logger = logging.getLogger(__name__)

EMBEDDING_MODEL = get_ai_config_service().get_config().get("embedding_model", "text-embedding-3-small")

_client = OpenAI(api_key=settings.OPENAI_API_KEY)


class EmbeddingService:
    """
    Centralized embedding service.
    Single source of truth for embedding model usage.
    """

    def __init__(self):
        self.model = EMBEDDING_MODEL
        self.client = _client

    # ---------------------------------------------------------
    # Batch embedding (used at schema startup)
    # ---------------------------------------------------------
    def embed_batch(self, texts: List[str]) -> List[np.ndarray]:
        if not texts:
            return []

        try:
            response = self.client.embeddings.create(
                model=self.model,
                input=texts
            )

            embeddings = [np.array(item.embedding) for item in response.data]
            return [self._normalize(e) for e in embeddings]

        except Exception as e:
            logger.error(f"Batch embedding failed: {e}")
            raise

    # ---------------------------------------------------------
    # Single embedding (used at query time)
    # ---------------------------------------------------------
    def embed(self, text: str) -> np.ndarray:
        return self.embed_batch([text])[0]

    # ---------------------------------------------------------
    # Normalization (important for cosine stability)
    # ---------------------------------------------------------
    def _normalize(self, vec: np.ndarray) -> np.ndarray:
        norm = np.linalg.norm(vec)
        if norm == 0:
            return vec
        return vec / norm


# Global singleton instance (recommended)
embedding_service = EmbeddingService()