"""
Central AI configuration service.
Stores global provider/model settings applied across the app.
"""

import json
import logging
from copy import deepcopy
from pathlib import Path
from threading import RLock
from typing import Any, Dict, List

from app.core.config import BASE_DIR

logger = logging.getLogger(__name__)


DEFAULT_MODEL_CATALOG: Dict[str, Dict[str, List[str]]] = {
    "openai": {
        "chat": ["gpt-5.2", "gpt-4o"],
        "sql": ["gpt-5.2", "gpt-4o"],
        "agent": ["gpt-5.2", "gpt-4o"],
        "vision": ["gpt-5.2", "gpt-4o"],
        "embedding": ["text-embedding-3-small", "text-embedding-3-large"],
    },
    "groq": {
        "chat": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"],
        "sql": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"],
        "agent": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"],
        "vision": [],
        "embedding": [],
    },
}


DEFAULT_CONFIG: Dict[str, Any] = {
    "active_provider": "openai",
    "chat_model": "gpt-5.2",
    "sql_model": "gpt-5.2",
    "agent_model": "gpt-5.2",
    "vision_model": "gpt-5.2",
    "embedding_model": "text-embedding-3-small",
}


class AIConfigService:
    """Read/write global AI provider and model configuration."""

    def __init__(self):
        self._lock = RLock()
        self._config_path = Path(BASE_DIR) / "config" / "ai_model_config.json"
        self._config_path.parent.mkdir(parents=True, exist_ok=True)

    def get_catalog(self) -> Dict[str, Dict[str, List[str]]]:
        return deepcopy(DEFAULT_MODEL_CATALOG)

    def get_config(self) -> Dict[str, Any]:
        with self._lock:
            if not self._config_path.exists():
                self._write_config(DEFAULT_CONFIG)
                return deepcopy(DEFAULT_CONFIG)

            try:
                raw = json.loads(self._config_path.read_text(encoding="utf-8"))
                normalized = self._normalize_config(raw)

                # Keep file corrected if it had outdated values.
                if normalized != raw:
                    self._write_config(normalized)

                return normalized
            except Exception as exc:
                logger.warning(f"Failed to load AI config, using defaults: {exc}")
                self._write_config(DEFAULT_CONFIG)
                return deepcopy(DEFAULT_CONFIG)

    def update_config(self, new_config: Dict[str, Any]) -> Dict[str, Any]:
        with self._lock:
            current = self.get_config()
            merged = {**current, **new_config}
            normalized = self._normalize_config(merged)
            self._write_config(normalized)
            logger.info(
                "AI config updated: provider=%s, chat=%s, sql=%s",
                normalized["active_provider"],
                normalized["chat_model"],
                normalized["sql_model"],
            )
            return normalized

    def _normalize_config(self, candidate: Dict[str, Any]) -> Dict[str, Any]:
        config = {**DEFAULT_CONFIG, **(candidate or {})}

        provider = str(config.get("active_provider", "openai")).lower().strip()
        if provider not in DEFAULT_MODEL_CATALOG:
            provider = DEFAULT_CONFIG["active_provider"]
        config["active_provider"] = provider

        for key in ["chat_model", "sql_model", "agent_model", "vision_model", "embedding_model"]:
            config[key] = self._normalize_model(provider, key, str(config.get(key, "")).strip())

        return config

    def _normalize_model(self, provider: str, key: str, value: str) -> str:
        functionality = key.replace("_model", "")
        provider_catalog = DEFAULT_MODEL_CATALOG.get(provider, {})
        options = provider_catalog.get(functionality, [])

        # If provider doesn't support this functionality (e.g., Groq vision/embedding),
        # keep OpenAI defaults for that functionality.
        if not options:
            return DEFAULT_CONFIG.get(key, "")

        if value in options:
            return value

        default_for_key = DEFAULT_CONFIG.get(key, "")
        if default_for_key in options:
            return default_for_key

        return options[0]

    def _write_config(self, config: Dict[str, Any]) -> None:
        self._config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")


_ai_config_service = AIConfigService()


def get_ai_config_service() -> AIConfigService:
    return _ai_config_service
