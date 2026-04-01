"""
Ingestion Manifest — Track ingested files to enable incremental ingestion.

Stores a JSON manifest with file hash, timestamp, and chunk count for each
ingested file. On subsequent runs, files with unchanged hashes are skipped
automatically, making re-ingestion fast and duplicate-free.

Phase 4 of the Multimodal RAG Upgrade Plan.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

DEFAULT_MANIFEST_PATH = str(
    Path(__file__).resolve().parents[3] / "data" / "ingestion_manifest.json"
)


@dataclass
class FileEntry:
    """Record of a single ingested file."""
    file_path: str
    file_hash: str
    timestamp: float               # epoch seconds
    chunk_count: int = 0
    category: str = ""
    file_size: int = 0
    file_type: str = ""


@dataclass
class IngestionManifest:
    """Persistent manifest tracking every ingested file.

    Usage:
        manifest = IngestionManifest()
        if manifest.needs_ingestion(path):
            # … ingest file …
            manifest.record(path, chunk_count=42, category="training")
        manifest.save()
    """
    manifest_path: str = DEFAULT_MANIFEST_PATH
    entries: Dict[str, FileEntry] = field(default_factory=dict)

    def __post_init__(self):
        self._load()

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def needs_ingestion(self, file_path: str) -> bool:
        """Return True if the file is new or has changed since last ingestion."""
        resolved = str(Path(file_path).resolve())
        current_hash = self._hash_file(resolved)
        if not current_hash:
            return True  # file unreadable → try ingesting anyway

        entry = self.entries.get(resolved)
        if entry is None:
            return True  # never ingested
        return entry.file_hash != current_hash  # changed

    def record(
        self,
        file_path: str,
        *,
        chunk_count: int = 0,
        category: str = "",
    ) -> None:
        """Record a successfully ingested file."""
        resolved = str(Path(file_path).resolve())
        file_hash = self._hash_file(resolved) or ""
        try:
            file_size = os.path.getsize(resolved)
        except OSError:
            file_size = 0
        self.entries[resolved] = FileEntry(
            file_path=resolved,
            file_hash=file_hash,
            timestamp=time.time(),
            chunk_count=chunk_count,
            category=category,
            file_size=file_size,
            file_type=Path(resolved).suffix.lower(),
        )

    def remove(self, file_path: str) -> None:
        """Remove a file from the manifest (e.g. after deletion)."""
        resolved = str(Path(file_path).resolve())
        self.entries.pop(resolved, None)

    def save(self) -> None:
        """Persist manifest to disk."""
        os.makedirs(os.path.dirname(self.manifest_path), exist_ok=True)
        data = {k: asdict(v) for k, v in self.entries.items()}
        try:
            with open(self.manifest_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            logger.info(f"💾 Manifest saved: {len(self.entries)} entries → {self.manifest_path}")
        except Exception as exc:
            logger.error(f"Failed to save manifest: {exc}")

    def get_stats(self) -> Dict[str, int]:
        """Return summary statistics."""
        return {
            "total_files": len(self.entries),
            "total_chunks": sum(e.chunk_count for e in self.entries.values()),
            "categories": len(set(e.category for e in self.entries.values() if e.category)),
        }

    # ────────────────────────────────────────────────────
    #  Internal
    # ────────────────────────────────────────────────────
    def _load(self) -> None:
        """Load manifest from disk if it exists."""
        if not os.path.exists(self.manifest_path):
            return
        try:
            with open(self.manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for key, val in data.items():
                self.entries[key] = FileEntry(**val)
            logger.info(f"📋 Loaded manifest: {len(self.entries)} entries")
        except Exception as exc:
            logger.warning(f"Failed to load manifest: {exc}")

    @staticmethod
    def _hash_file(file_path: str, chunk_size: int = 65536) -> Optional[str]:
        """Compute SHA-256 hash of a file."""
        try:
            h = hashlib.sha256()
            with open(file_path, "rb") as f:
                while True:
                    data = f.read(chunk_size)
                    if not data:
                        break
                    h.update(data)
            return h.hexdigest()
        except OSError:
            return None
