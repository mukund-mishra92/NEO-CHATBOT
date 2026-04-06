"""
Answer Planner — Production-grade structured answer generation.

Given the user query and retrieved evidence, the planner:
  1. Classifies query type with rich multi-label detection
  2. Extracts user intent (what they specifically want to achieve)
  3. Ranks evidence by relevance to assign to sections
  4. Builds a minimal but complete plan with content-driven section names
  5. Emits a structured briefing that tells the LLM EXACTLY what to write,
     in what order, at what depth — like a professional editor's note

Design philosophy: the plan should read like a senior analyst briefing
a junior writer before they answer a customer question. Every instruction
should be specific, not generic.
"""

from __future__ import annotations

import logging
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

from ..ingetion.models import RetrievedChunk, Source  # noqa: F401

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────
#  Data Models
# ─────────────────────────────────────────────────────────────────

@dataclass
class EvidenceItem:
    """A ranked piece of evidence for an answer section."""
    chunk_id: str
    content: str
    source_path: str = ""
    source_name: str = ""          # human-readable filename
    page_numbers: List[int] = field(default_factory=list)
    score: float = 0.0
    contains_warning: bool = False  # True if chunk has safety/caution/warning content
    contains_steps: bool = False    # True if chunk has numbered steps
    contains_table: bool = False    # True if chunk has tabular data


@dataclass
class FigureItem:
    """An image assigned to an answer section."""
    image_path: str
    caption: str = ""
    source_path: str = ""
    page_number: int = 0
    figure_number: int = 0
    relevance_score: float = 0.0


@dataclass
class AnswerSection:
    """One planned section of the final answer."""
    heading: str                                    # content-driven heading
    instruction: str                                # precise LLM instruction
    evidence: List[EvidenceItem] = field(default_factory=list)
    figures: List[FigureItem] = field(default_factory=list)
    is_optional: bool = False                       # skip if no supporting evidence


@dataclass
class AnswerPlan:
    """Complete answer plan emitted by AnswerPlanner."""
    query: str
    query_type: str
    intent: str = ""                                # brief sentence: what the user wants
    summary_instruction: str = ""
    sections: List[AnswerSection] = field(default_factory=list)
    total_evidence: int = 0
    total_figures: int = 0
    has_warnings: bool = False

    def to_prompt_context(self) -> str:
        """
        Emit a structured briefing for the LLM.

        This reads like an analyst note — it tells the LLM:
        - What the user wants (intent)
        - How to structure the answer
        - What each section must contain, based on actual evidence
        - Where figures go
        - Critical warnings to surface
        It is NOT a raw data dump.
        """
        lines: List[str] = []

        lines.append("━━━ ANSWER BRIEF ━━━")
        lines.append(f"USER INTENT: {self.intent}")
        lines.append(f"ANSWER TYPE: {self.query_type}")
        lines.append(f"APPROACH: {self.summary_instruction}")
        if self.has_warnings:
            lines.append("⚠️  SAFETY: This answer contains warnings/cautions — surface them prominently.")
        lines.append("")

        for i, section in enumerate(self.sections, 1):
            ev_count = len(section.evidence)

            if ev_count == 0 and section.is_optional:
                continue  # skip empty optional sections

            lines.append(f"── SECTION {i}: {section.heading} ──")
            lines.append(f"   Write: {section.instruction}")

            if section.evidence:
                key_terms = _extract_key_terms(
                    " ".join(e.content[:300] for e in section.evidence)
                )
                lines.append(f"   Key evidence terms: {', '.join(key_terms[:8])}")
                sources = sorted({e.source_name for e in section.evidence if e.source_name})
                if sources:
                    lines.append(f"   Sources: {', '.join(sources)}")

            if any(e.contains_steps for e in section.evidence):
                lines.append("   → Evidence contains numbered steps — present them as a numbered list.")

            if any(e.contains_table for e in section.evidence):
                lines.append("   → Evidence contains tabular data — use a markdown table.")

            if section.figures:
                for fig in section.figures:
                    cap = fig.caption[:80] if fig.caption else "no caption"
                    lines.append(f"   📷 Figure {fig.figure_number}: {cap} (page {fig.page_number})")
                lines.append("   → Reference the figure(s) by number where relevant in this section.")
            lines.append("")

        lines.append("━━━ END OF BRIEF ━━━")
        return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────
#  Planner
# ─────────────────────────────────────────────────────────────────

class AnswerPlanner:
    """Build a production-grade answer plan from query + retrieved evidence."""

    # ── Query type signals (order matters: checked highest-priority first) ─
    _DIAGNOSTIC = {
        "error", "alarm", "fault", "issue", "problem", "stuck", "failed",
        "not working", "not achieved", "not reached", "stopped", "what to do",
        "how to fix", "how to resolve", "troubleshoot", "recovery", "recover",
    }
    _PROCEDURAL = {
        "how to", "steps to", "step by step", "procedure", "process for",
        "guide to", "setup", "configure", "installation", "install",
        "how do i", "how can i", "walk me through",
    }
    _COMPARISON = {
        "compare", "difference", "versus", "vs ", " vs.", "between",
        "pros and cons", "benefits of", "advantages of", "better than",
    }
    _FACTUAL = {
        "what is", "what are", "define", "definition", "who is",
        "when did", "where is", "how many", "how much", "which",
    }
    _EXPLORATORY = {
        "explain", "describe", "overview", "tell me about",
        "how does", "how do", "architecture", "design", "structure",
    }
    _CODE = {
        "code", "class", "method", "function", "implementation",
        "source", ".cs", "c#", "csharp", "api", "endpoint", "controller",
    }

    def plan(
        self,
        query: str,
        chunks: List[RetrievedChunk],
        *,
        images: Optional[List[Dict[str, Any]]] = None,
        query_type_hint: Optional[str] = None,
    ) -> AnswerPlan:
        """Build the answer plan.

        Args:
            query: User's question.
            chunks: Retrieved and reranked chunks.
            images: Display images selected upstream.
            query_type_hint: KB-service query type (e.g. "TROUBLESHOOTING").
                When provided, it takes precedence over the planner's own
                classification for routing to the correct plan builder.
        """
        images = images or []
        q = query.lower().strip()

        # ── Honour the KB-service classification when supplied ──────
        # Map KB type names → planner type names
        _hint_map: Dict[str, str] = {
            "TROUBLESHOOTING": "diagnostic",
            "PROCEDURAL":      "procedural",
            "COMPARISON":      "comparison",
            "SIMPLE_FACT":     "factual",
            "DEFINITION":      "factual",
            "CODE_QUERY":      "code",
            "EXPLORATORY":     "exploratory",
            "GENERATIVE":      "exploratory",
        }
        if query_type_hint and query_type_hint in _hint_map:
            query_type = _hint_map[query_type_hint]
        else:
            query_type = self._classify(q)

        intent = self._extract_intent(query, q, query_type)

        plan = AnswerPlan(
            query=query,
            query_type=query_type,
            intent=intent,
        )

        evidence_pool = [self._to_evidence(c) for c in chunks]
        plan.has_warnings = any(e.contains_warning for e in evidence_pool)

        if query_type == "diagnostic":
            plan = self._plan_diagnostic(plan, evidence_pool, images, q)
        elif query_type == "procedural":
            plan = self._plan_procedural(plan, evidence_pool, images, q)
        elif query_type == "comparison":
            plan = self._plan_comparison(plan, evidence_pool, images)
        elif query_type == "factual":
            plan = self._plan_factual(plan, evidence_pool, images)
        elif query_type == "code":
            plan = self._plan_code(plan, evidence_pool, images)
        else:
            plan = self._plan_exploratory(plan, evidence_pool, images, q)

        plan.total_evidence = sum(len(s.evidence) for s in plan.sections)
        plan.total_figures = sum(len(s.figures) for s in plan.sections)

        logger.info(
            f"📝 AnswerPlan [{query_type}] → {len(plan.sections)} sections, "
            f"{plan.total_evidence} evidence items, {plan.total_figures} figures"
        )
        return plan

    # ────────────────────────────────────────────────────
    #  Classification + Intent
    # ────────────────────────────────────────────────────

    def _classify(self, q: str) -> str:
        """Multi-signal classification — returns the dominant type."""
        scores: Dict[str, int] = {
            "diagnostic": 0, "procedural": 0, "comparison": 0,
            "factual": 0, "code": 0, "exploratory": 0,
        }
        for kw in self._DIAGNOSTIC:
            if kw in q:
                scores["diagnostic"] += 2
        for kw in self._PROCEDURAL:
            if kw in q:
                scores["procedural"] += 2
        for kw in self._COMPARISON:
            if kw in q:
                scores["comparison"] += 2
        for kw in self._FACTUAL:
            if kw in q:
                scores["factual"] += 1
        for kw in self._CODE:
            if kw in q:
                scores["code"] += 2
        for kw in self._EXPLORATORY:
            if kw in q:
                scores["exploratory"] += 1

        # Boost exploratory for longer questions with no strong signal
        if len(q.split()) > 8 and max(scores.values()) <= 1:
            scores["exploratory"] += 2

        best = max(scores, key=lambda k: scores[k])
        if scores[best] == 0:
            best = "exploratory"
        return best

    def _extract_intent(self, query: str, q: str, query_type: str) -> str:
        """Produce a one-sentence intent summary."""
        if query_type == "diagnostic":
            match = re.search(
                r"(?:in case of|case of|for|about|with|regarding)\s+(.+?)(?:\s+error|\s+alarm|\s+fault)?$",
                q, re.IGNORECASE,
            )
            subj = match.group(1).strip() if match else query
            return f"Diagnose and resolve: {subj.strip('?. ')}"

        if query_type == "procedural":
            match = re.search(r"(?:how to|steps to|how do i|how can i)\s+(.+)", q, re.IGNORECASE)
            subj = match.group(1).strip() if match else query
            return f"Step-by-step guide to: {subj.strip('?. ')}"

        if query_type == "comparison":
            return f"Compare the options in: {query.strip('?.')}"

        if query_type == "code":
            return f"Show code / implementation for: {query.strip('?.')}"

        if query_type == "factual":
            return f"Fact answer to: {query.strip('?.')}"

        return f"Explain: {query.strip('?.')}"

    # ────────────────────────────────────────────────────
    #  Plan builders
    # ────────────────────────────────────────────────────

    def _plan_diagnostic(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
        q: str,
    ) -> AnswerPlan:
        """Diagnostic plan: immediate actions → root causes → steps → warnings."""
        plan.summary_instruction = (
            "Lead with the most important immediate action. "
            "Then list root causes. "
            "Then give a numbered troubleshooting sequence. "
            "End with safety warnings. "
            "Every line must be actionable."
        )

        warn_ev = [e for e in evidence if e.contains_warning]
        step_ev = [e for e in evidence if e.contains_steps]
        general_ev = [e for e in evidence if not e.contains_warning and not e.contains_steps]
        ordered = _dedup_evidence(step_ev + general_ev + warn_ev)

        figs_1 = self._pick_figures(images, ordered[:3])
        plan.sections.append(AnswerSection(
            heading="Immediate Actions",
            instruction=(
                "State the first 1-2 things to check or do right now. "
                "Be specific — name the component, cable, or UI step. "
                "Do not give background."
            ),
            evidence=ordered[:3],
            figures=figs_1,
        ))

        if len(ordered) > 1:
            plan.sections.append(AnswerSection(
                heading="Common Causes",
                instruction=(
                    "List the documented root causes as bullet points. "
                    "Include alarm codes or error table entries if present."
                ),
                evidence=ordered[:4],
                is_optional=True,
            ))

        all_steps = _dedup_evidence(step_ev + general_ev)
        if all_steps:
            figs_2 = self._pick_figures(images, all_steps, exclude=figs_1)
            plan.sections.append(AnswerSection(
                heading="Troubleshooting Steps",
                instruction=(
                    "Numbered steps. Each step must be one actionable instruction. "
                    "Reference figures inline if available. "
                    "Cover: inspect → test → replace/repair → verify order."
                ),
                evidence=all_steps[:5],
                figures=figs_2,
            ))

        if warn_ev:
            plan.sections.append(AnswerSection(
                heading="⚠️ Safety & Precautions",
                instruction=(
                    "List any safety warnings, accident risks, or precautions exactly as stated. "
                    "Do NOT soften or reword safety language."
                ),
                evidence=warn_ev[:2],
                is_optional=False,
            ))

        return plan

    def _plan_procedural(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
        q: str,
    ) -> AnswerPlan:
        plan.summary_instruction = (
            "Brief one-line overview, then numbered steps. "
            "Include prerequisites if the evidence mentions them. "
            "End with a verification step if available."
        )

        step_ev = [e for e in evidence if e.contains_steps]
        other_ev = [e for e in evidence if not e.contains_steps]
        warn_ev = [e for e in evidence if e.contains_warning]
        ordered = _dedup_evidence(step_ev + other_ev)

        prereq_ev = [
            e for e in ordered
            if any(w in e.content.lower() for w in (
                "prerequisite", "before you", "ensure first", "require", "must have"
            ))
        ]
        if prereq_ev:
            plan.sections.append(AnswerSection(
                heading="Prerequisites",
                instruction="List what must be in place before starting.",
                evidence=prereq_ev[:2],
                is_optional=True,
            ))

        figs = self._pick_figures(images, ordered[:6])
        plan.sections.append(AnswerSection(
            heading="Steps",
            instruction=(
                "Numbered steps using the evidence. One action per step. "
                "Include verification sub-steps where documented."
            ),
            evidence=ordered[:6],
            figures=figs,
        ))

        if warn_ev:
            plan.sections.append(AnswerSection(
                heading="⚠️ Important Notes",
                instruction="List warnings and precautions. Use the same wording as the source.",
                evidence=warn_ev[:2],
                is_optional=False,
            ))

        return plan

    def _plan_comparison(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
    ) -> AnswerPlan:
        plan.summary_instruction = (
            "Compare on the dimensions that matter. "
            "Use a table if 3+ attributes, bullets if fewer. "
            "End with a clear recommendation or summary."
        )

        groups: Dict[str, List[EvidenceItem]] = {}
        for ev in evidence:
            groups.setdefault(ev.source_name or "General", []).append(ev)

        fig_offset = 1
        for source, evs in list(groups.items())[:3]:
            figs = self._pick_figures(images, evs[:3], start_fig=fig_offset)
            fig_offset += len(figs)
            plan.sections.append(AnswerSection(
                heading=source,
                instruction=f"Describe the key aspects of {source} relevant to the comparison.",
                evidence=evs[:3],
                figures=figs,
                is_optional=True,
            ))

        plan.sections.append(AnswerSection(
            heading="Comparison Summary",
            instruction="Summarise differences in a table or structured bullets. Give a recommendation.",
            evidence=evidence[:3],
        ))
        return plan

    def _plan_factual(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
    ) -> AnswerPlan:
        plan.summary_instruction = (
            "Direct answer first (1-3 sentences). "
            "Supporting detail only if it adds meaning."
        )

        figs = self._pick_figures(images, evidence[:3])
        plan.sections.append(AnswerSection(
            heading="Answer",
            instruction=(
                "State the fact directly. If a number/spec, give the exact value. "
                "If a concept, define it clearly. Cite source."
            ),
            evidence=evidence[:3],
            figures=figs,
        ))

        if len(evidence) > 3:
            plan.sections.append(AnswerSection(
                heading="Additional Context",
                instruction="Add supporting context only if it materially changes the answer.",
                evidence=evidence[3:5],
                is_optional=True,
            ))
        return plan

    def _plan_code(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
    ) -> AnswerPlan:
        plan.summary_instruction = (
            "Show the relevant code with file path and purpose. "
            "Follow with key design notes. No prose padding."
        )

        plan.sections.append(AnswerSection(
            heading="Implementation",
            instruction=(
                "File: [path]. Purpose: [1 sentence]. "
                "Show the relevant code snippet — complete logic, not truncated. "
                "Then bullet the key design decisions or usage notes."
            ),
            evidence=evidence[:4],
            figures=self._pick_figures(images, evidence[:4]),
        ))
        return plan

    def _plan_exploratory(
        self,
        plan: AnswerPlan,
        evidence: List[EvidenceItem],
        images: List[Dict],
        q: str,
    ) -> AnswerPlan:
        plan.summary_instruction = (
            "Organise into logical sections based on the evidence topics. "
            "Each section should cover a distinct aspect. "
            "Use figures where they illustrate a point. "
            "Match depth to what the evidence actually contains."
        )

        groups: Dict[str, List[EvidenceItem]] = {}
        for ev in evidence:
            groups.setdefault(ev.source_name or "Details", []).append(ev)

        fig_offset = 1
        for i, (group_name, evs) in enumerate(list(groups.items())[:4]):
            figs = self._pick_figures(images, evs[:3], start_fig=fig_offset)
            fig_offset += len(figs)
            heading = _infer_heading(evs, fallback=group_name)
            plan.sections.append(AnswerSection(
                heading=heading,
                instruction=(
                    f"Explain {heading} using the evidence. "
                    "Bullets for lists/specs, paragraphs for explanation. "
                    "Reference figures inline if assigned."
                ),
                evidence=evs[:3],
                figures=figs,
                is_optional=(i > 0),
            ))

        if not plan.sections:
            figs = self._pick_figures(images, evidence[:5])
            plan.sections.append(AnswerSection(
                heading="Answer",
                instruction="Explain based on available evidence. Structure dynamically.",
                evidence=evidence[:5],
                figures=figs,
            ))

        return plan

    # ────────────────────────────────────────────────────
    #  Helpers
    # ────────────────────────────────────────────────────

    def _to_evidence(self, chunk: RetrievedChunk) -> EvidenceItem:
        """Convert a RetrievedChunk to an enriched EvidenceItem."""
        content = chunk.content or ""
        cl = content.lower()
        has_warning = any(w in cl for w in (
            "warning", "caution", "danger", "do not", "must not",
            "accident", "risk", "hazard", "safety"
        ))
        has_steps = bool(re.search(r"^\s*\d+[\.\)]\s", content, re.MULTILINE))
        has_table = any(w in cl for w in ("| ", "\t", "column", "row", "table"))
        source_name = ""
        if chunk.source_path:
            source_name = Path(chunk.source_path).name
        elif chunk.metadata and chunk.metadata.get("filename"):
            source_name = chunk.metadata["filename"]

        return EvidenceItem(
            chunk_id=chunk.chunk_id,
            content=content,
            source_path=chunk.source_path or "",
            source_name=source_name,
            page_numbers=chunk.page_numbers or [],
            score=chunk.score,
            contains_warning=has_warning,
            contains_steps=has_steps,
            contains_table=has_table,
        )

    def _pick_figures(
        self,
        images: List[Dict],
        evidence: List[EvidenceItem],
        *,
        start_fig: int = 1,
        exclude: Optional[List[FigureItem]] = None,
    ) -> List[FigureItem]:
        """Assign relevant images to evidence items."""
        if not images:
            return []

        exclude_paths = {f.image_path for f in (exclude or [])}
        ev_sources = {e.source_path for e in evidence if e.source_path}

        figures: List[FigureItem] = []
        seen: Set[str] = set()
        fig_num = start_fig

        for img in images:
            path = img.get("image_path", "")
            if not path or path in seen or path in exclude_paths:
                continue
            img_source = img.get("source_path", img.get("source_document", ""))
            if ev_sources and img_source and not any(
                img_source in s or s in img_source for s in ev_sources
            ):
                continue
            figures.append(FigureItem(
                image_path=path,
                caption=img.get("caption", ""),
                source_path=img_source,
                page_number=img.get("page_number", 0),
                figure_number=fig_num,
                relevance_score=img.get("relevance_score", 0.0),
            ))
            seen.add(path)
            fig_num += 1

        return figures


# ─────────────────────────────────────────────────────────────────
#  Module-level utilities
# ─────────────────────────────────────────────────────────────────

def _dedup_evidence(items: List[EvidenceItem]) -> List[EvidenceItem]:
    """Remove duplicate evidence items by chunk_id, preserving order."""
    seen: Set[str] = set()
    result: List[EvidenceItem] = []
    for item in items:
        if item.chunk_id not in seen:
            seen.add(item.chunk_id)
            result.append(item)
    return result


def _extract_key_terms(text: str) -> List[str]:
    """Pull meaningful multi-char words for the evidence summary."""
    stop = {
        "the", "and", "for", "that", "this", "with", "from", "are", "was",
        "not", "have", "has", "will", "can", "may", "its", "any", "all",
        "been", "into", "when", "which", "they", "their", "more", "also",
    }
    words = re.findall(r"\b[A-Za-z][A-Za-z0-9_/-]{3,}\b", text)
    seen: Set[str] = set()
    result: List[str] = []
    for w in words:
        wl = w.lower()
        if wl not in stop and wl not in seen:
            seen.add(wl)
            result.append(w)
    return result


def _infer_heading(evidence: List[EvidenceItem], fallback: str = "") -> str:
    """Infer a content-driven section heading from evidence content."""
    all_text = " ".join(e.content[:200] for e in evidence)
    noun_phrases = re.findall(r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b", all_text)
    if noun_phrases:
        counts = Counter(noun_phrases)
        best = counts.most_common(1)[0][0]
        if best.lower() not in {"the system", "the device", "the unit", "the bot"}:
            return best
    return fallback or "Details"
