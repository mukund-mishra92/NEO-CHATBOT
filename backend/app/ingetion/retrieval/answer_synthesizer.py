"""
Answer Synthesizer — Generate final answers from retrieved context using LLM.

Features:
  • Map-reduce for large contexts
  • Citation injection ([Source N])
  • Confidence estimation
  • "I don't know" handling when evidence is insufficient
  • Follow-up question suggestions
"""

from __future__ import annotations

import logging
import re
from typing import List, Optional

from ..models import RetrievedChunk, Source, SynthesizedAnswer

logger = logging.getLogger(__name__)


# ════════════════════════════════════════════════════════════════
#  System prompt template
# ════════════════════════════════════════════════════════════════
SYNTHESIS_SYSTEM_PROMPT = """You are NEO Assistant, an expert on the NEO Warehouse Management System.

Answer the user's question using ONLY the provided context. Follow these rules:

1. **Cite your sources** — reference with [Source N] for each fact.
2. **Be specific** — include numbers, names, specs from the context.
3. **Structure your answer** — use headings, bullet points, tables as appropriate.
4. **If insufficient evidence** — say "Based on the available documentation, I could not find specific information about…" and suggest what to look for.
5. **Never make up information** that isn't in the context.
6. At the end, suggest 1-2 follow-up questions the user might want to ask.

CONTEXT:
{context}
"""

CONFIDENCE_PROMPT = """Rate your confidence in the answer on a scale of 0.0 to 1.0.
Consider: How well does the context cover the question? Were multiple sources consistent?
Reply with ONLY a number between 0.0 and 1.0."""


class AnswerSynthesizer:
    """Generate answers with citations from retrieved context."""

    def __init__(self, llm_service=None):
        """
        Args:
            llm_service: An existing LLMService instance.
                         If None, creates a new one.
        """
        self._llm = llm_service

    @property
    def llm(self):
        if self._llm is None:
            from app.services.llm_service import LLMService
            self._llm = LLMService()
        return self._llm

    # ────────────────────────────────────────────────────
    #  Public API
    # ────────────────────────────────────────────────────
    def synthesize(
        self,
        query: str,
        context: str,
        sources: List[Source],
        retrieved_chunks: Optional[List[RetrievedChunk]] = None,
    ) -> SynthesizedAnswer:
        """
        Generate a synthesized answer with citations.

        Args:
            query: User's question.
            context: Assembled context string (from ContextAssembler).
            sources: Source citations.
            retrieved_chunks: Optional list of retrieved chunks for metadata.

        Returns:
            SynthesizedAnswer with answer text, confidence, and sources.
        """
        if not context.strip():
            return SynthesizedAnswer(
                answer="I couldn't find any relevant information in the knowledge base to answer your question. "
                       "Could you rephrase or ask about a specific NEO system topic?",
                confidence=0.0,
                sources=[],
                has_sufficient_evidence=False,
                suggested_followups=[
                    "What documents are available in the knowledge base?",
                    "Can you list the topics I can ask about?",
                ],
                retrieved_chunks=retrieved_chunks or [],
            )

        # ── Generate answer ──
        system_prompt = SYNTHESIS_SYSTEM_PROMPT.format(context=context)
        try:
            answer = self.llm.generate_response(
                system_prompt=system_prompt,
                user_message=query,
            )
        except Exception as exc:
            logger.error(f"LLM answer generation failed: {exc}", exc_info=True)
            answer = self._fallback_answer(context, query)

        # ── Estimate confidence ──
        confidence = self._estimate_confidence(answer, sources, context)

        # ── Extract follow-ups ──
        followups = self._extract_followups(answer)

        # ── Check evidence sufficiency ──
        has_evidence = confidence > 0.3 and not any(
            phrase in answer.lower()
            for phrase in [
                "could not find",
                "no information",
                "not mentioned",
                "i don't have",
                "cannot determine",
            ]
        )

        return SynthesizedAnswer(
            answer=answer.strip(),
            confidence=confidence,
            sources=sources,
            has_sufficient_evidence=has_evidence,
            suggested_followups=followups,
            retrieved_chunks=retrieved_chunks or [],
        )

    # ────────────────────────────────────────────────────
    #  Confidence estimation
    # ────────────────────────────────────────────────────
    def _estimate_confidence(
        self, answer: str, sources: List[Source], context: str
    ) -> float:
        """Estimate answer confidence from heuristics."""
        score = 0.5  # Baseline

        # Boost: multiple sources referenced
        source_refs = re.findall(r"\[Source \d+\]", answer)
        if len(source_refs) >= 2:
            score += 0.15
        elif len(source_refs) >= 1:
            score += 0.1

        # Boost: specific data (numbers, names)
        if re.search(r"\d+", answer):
            score += 0.05

        # Boost: structured answer (bullet points, headings)
        if re.search(r"[-•*]\s", answer) or re.search(r"#{1,3}\s", answer):
            score += 0.05

        # Penalty: very short answer
        if len(answer) < 100:
            score -= 0.1

        # Penalty: hedging language
        hedging = ["might", "possibly", "not sure", "unclear", "may or may not"]
        for h in hedging:
            if h in answer.lower():
                score -= 0.05

        # Boost: high source relevance
        if sources:
            avg_relevance = sum(s.relevance_score for s in sources) / len(sources)
            score += avg_relevance * 0.1

        return max(0.0, min(1.0, score))

    # ────────────────────────────────────────────────────
    #  Follow-up extraction
    # ────────────────────────────────────────────────────
    @staticmethod
    def _extract_followups(answer: str) -> List[str]:
        """Extract suggested follow-up questions from the answer."""
        followups: List[str] = []

        # Look for patterns like "You might also want to ask about..."
        # or numbered/bullet follow-ups at the end
        lines = answer.split("\n")
        in_followup_section = False
        for line in reversed(lines):
            stripped = line.strip()
            if not stripped:
                continue
            if any(kw in stripped.lower() for kw in [
                "follow-up", "followup", "you might also",
                "related questions", "you could ask",
            ]):
                in_followup_section = True
                continue
            if in_followup_section and (
                stripped.startswith(("-", "•", "*", "1", "2"))
                or stripped.endswith("?")
            ):
                q = re.sub(r"^[-•*\d.)\s]+", "", stripped).strip()
                if q and q.endswith("?"):
                    followups.insert(0, q)

        return followups[:3]

    # ────────────────────────────────────────────────────
    #  Fallback
    # ────────────────────────────────────────────────────
    @staticmethod
    def _fallback_answer(context: str, query: str) -> str:
        """Simple extractive fallback when LLM is unavailable."""
        # Return the first 500 chars of context as a rough answer
        snippet = context[:500].strip()
        return (
            f"Here's what I found related to your question:\n\n{snippet}\n\n"
            f"(Note: This is a direct excerpt — the AI answer service was temporarily unavailable.)"
        )
