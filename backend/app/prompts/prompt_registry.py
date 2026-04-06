"""
Prompt Registry — Central loader and assembler for all NEO Assistant prompts.

All prompt text lives in the sibling directories:
  system/          → base_prompt.txt, brevity_prompt.txt
  query_types/     → one .txt file per query type
  message_templates/ → user message skeletons

Usage
-----
from backend.app.prompts.prompt_registry import registry

# System prompt for a query type
system_prompt = registry.get_system_prompt("TROUBLESHOOTING")
system_prompt = registry.get_system_prompt("SIMPLE_FACT", brevity_mode=True)

# User message
user_msg = registry.render_user_message(
    query_type="TROUBLESHOOTING",
    context=kb_context,
    question=user_question,
    image_context=image_block,
    plan_context=plan_block,
)

# Conversation context block
conv_block = registry.render_conversation_context(history_parts)

# Attached-document prefix
doc_prefix = registry.render_attached_doc_prefix(attached_name="manual.pdf")

Hot reload (development only)
------------------------------
registry.reload()
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# Root of this package
_PROMPTS_DIR = Path(__file__).parent

# ── File locations ────────────────────────────────────────────────────────────
_SYSTEM_DIR    = _PROMPTS_DIR / "system"
_QTYPES_DIR    = _PROMPTS_DIR / "query_types"
_TEMPLATES_DIR = _PROMPTS_DIR / "message_templates"

# Map KB-service query type names → query_types/*.txt filenames
_QTYPE_FILES: Dict[str, str] = {
    "SIMPLE_FACT":     "simple_fact.txt",
    "DEFINITION":      "definition.txt",
    "PROCEDURAL":      "procedural.txt",
    "COMPARISON":      "comparison.txt",
    "TROUBLESHOOTING": "troubleshooting.txt",
    "EXPLORATORY":     "exploratory.txt",
    "CODE_QUERY":      "code_query.txt",
    "GENERATIVE":      "generative.txt",
}

_NO_FIGURES_NOTE = (
    '\n[NO FIGURES AVAILABLE — do NOT reference "Figure X" '
    'or any page-based image]\n'
)


class PromptRegistry:
    """Load, cache, and assemble all prompts used by KnowledgeBaseService.

    The registry is a lightweight singleton; all heavy work (file I/O) happens
    once at construction time.  Call ``reload()`` to pick up edited .txt files
    without restarting the server.
    """

    def __init__(self) -> None:
        self._cache: Dict[str, str] = {}
        self._load_all()

    # ── Public API ────────────────────────────────────────────────────────────

    def get_system_prompt(
        self,
        query_type: str,
        *,
        brevity_mode: bool = False,
    ) -> str:
        """Return the complete system prompt for a query type.

        In brevity mode the entire prompt is replaced by the brevity variant —
        query-type-specific additions are suppressed.

        Args:
            query_type: One of the KB-service type strings (e.g. "TROUBLESHOOTING").
            brevity_mode: When True, return the strict brevity system prompt.

        Returns:
            Complete system prompt string ready to pass to the LLM.
        """
        if brevity_mode:
            return self._get("system/brevity_prompt.txt")

        base = self._get("system/base_prompt.txt")
        qtype_file = _QTYPE_FILES.get(query_type, "exploratory.txt")
        qtype_addition = self._get(f"query_types/{qtype_file}")
        return base + "\n" + qtype_addition

    def render_user_message(
        self,
        query_type: str,
        *,
        context: str = "",
        question: str = "",
        image_context: str = "",
        plan_context: str = "",
        doc_prefix: str = "",
        has_attached_doc: bool = False,
        brevity_mode: bool = False,
        brevity_context_limit: int = 1500,
    ) -> str:
        """Build the user-turn message for the LLM.

        Selects the correct template based on query type and flags, then
        renders it with the provided values.

        Args:
            query_type:           KB-service query type string.
            context:              Retrieved/assembled context text.
            question:             The user's original question.
            image_context:        Formatted AVAILABLE FIGURES block (or empty).
            plan_context:         Formatted AnswerPlan brief (or empty).
            doc_prefix:           Pre-rendered attached-document prefix (or empty).
            has_attached_doc:     Whether the attached_doc_prefix applies.
            brevity_mode:         When True, render the brevity user message.
            brevity_context_limit: Max chars of context in brevity mode.

        Returns:
            Rendered user message string.
        """
        if brevity_mode:
            tmpl = self._get("message_templates/brevity_user_message.txt")
            return tmpl.format(
                context=context[:brevity_context_limit],
                question=question,
            )

        if query_type == "SIMPLE_FACT":
            tmpl = self._get("message_templates/simple_fact_user_message.txt")
            return tmpl.format(
                doc_prefix=doc_prefix,
                context=context,
                question=question,
            )

        if query_type == "GENERATIVE":
            if has_attached_doc:
                tmpl = self._get("message_templates/generative_doc_user_message.txt")
                return tmpl.format(
                    doc_prefix=doc_prefix,
                    context=context,
                    question=question,
                )
            tmpl = self._get("message_templates/generative_user_message.txt")
            return tmpl.format(context=context, question=question)

        # ── Default template (all other query types incl. TROUBLESHOOTING) ───
        # Ensure image_context has a value — empty means explicitly no figures
        resolved_image_context = image_context if image_context else _NO_FIGURES_NOTE
        # Wrap plan_context with newlines only if non-empty
        resolved_plan_context = f"\n{plan_context}\n" if plan_context.strip() else ""

        tmpl = self._get("message_templates/user_message.txt")
        return tmpl.format(
            doc_prefix=doc_prefix,
            context=context,
            image_context=resolved_image_context,
            plan_context=resolved_plan_context,
            question=question,
        )

    def render_conversation_context(self, history_parts: list[str]) -> str:
        """Render the conversation-history context block injected before the query.

        Args:
            history_parts: List of "[ROLE]: content" strings (already formatted).

        Returns:
            Rendered conversation context string.
        """
        if not history_parts:
            return ""
        tmpl = self._get("message_templates/conversation_context.txt")
        return tmpl.format(history_block="\n".join(history_parts))

    def render_attached_doc_prefix(self, attached_name: str) -> str:
        """Render the attached-document priority notice.

        Args:
            attached_name: Display name of the uploaded document.

        Returns:
            Rendered prefix string (ends with newline).
        """
        tmpl = self._get("message_templates/attached_doc_prefix.txt")
        return tmpl.format(attached_name=attached_name)

    def reload(self) -> None:
        """Hot-reload all prompt files from disk.

        Safe to call at runtime without restarting the server.
        Useful during prompt iteration in development.
        """
        logger.info("🔄 PromptRegistry: reloading all prompt files from disk…")
        self._cache.clear()
        self._load_all()
        logger.info(f"✅ PromptRegistry: {len(self._cache)} prompt files loaded.")

    def list_loaded(self) -> list[str]:
        """Return the relative paths of all currently cached prompt files."""
        return sorted(self._cache.keys())

    # ── Internal ──────────────────────────────────────────────────────────────

    def _load_all(self) -> None:
        """Load every .txt file under the prompts directory into the cache."""
        for path in _PROMPTS_DIR.rglob("*.txt"):
            rel = path.relative_to(_PROMPTS_DIR).as_posix()
            try:
                self._cache[rel] = path.read_text(encoding="utf-8")
            except Exception as exc:  # noqa: BLE001
                logger.error(f"PromptRegistry: failed to load {rel}: {exc}")

        loaded = len(self._cache)
        expected = 2 + len(_QTYPE_FILES) + 7  # system + qtypes + templates
        if loaded < expected:
            logger.warning(
                f"PromptRegistry: only {loaded}/{expected} prompt files loaded — "
                "some prompts may be missing."
            )
        else:
            logger.info(f"✅ PromptRegistry: {loaded} prompt files loaded.")

    def _get(self, rel_path: str) -> str:
        """Retrieve a cached prompt by relative path.

        Falls back to an empty string and logs a warning if the file was not
        loaded, so a missing prompt degrades gracefully rather than crashing.
        """
        text = self._cache.get(rel_path, "")
        if not text:
            logger.warning(
                f"PromptRegistry: prompt not found or empty: {rel_path!r}. "
                "Check the prompts/ directory."
            )
        return text


# ── Module-level singleton ────────────────────────────────────────────────────
# Import this wherever you need prompts:
#   from backend.app.prompts.prompt_registry import registry
registry = PromptRegistry()
