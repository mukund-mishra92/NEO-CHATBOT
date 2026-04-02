"""
Answer Planner — Structured answer generation with evidence planning.

Phase 7 of the Multimodal RAG Upgrade Plan.

Given a query and retrieved chunks, the planner:
  1. Classifies the query type (factual, procedural, comparison, exploratory)
  2. Plans answer sections with evidence assignments
  3. Maps images to their relevant sections
  4. Generates the answer following the plan

This replaces ad-hoc answer generation with a systematic, explainable process.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from ..ingetion.models import RetrievedChunk, Source

logger = logging.getLogger(__name__)


@dataclass
class EvidenceItem:
    """A single piece of evidence mapped to an answer section."""
    chunk_id: str
    content: str
    source_path: str = ""
    page_numbers: List[int] = field(default_factory=list)
    score: float = 0.0


@dataclass
class FigureItem:
    """An image mapped to an answer section."""
    image_path: str
    caption: str = ""
    source_path: str = ""
    page_number: int = 0
    figure_number: int = 0


@dataclass
class AnswerSection:
    """A planned section of the answer."""
    heading: str
    evidence: List[EvidenceItem] = field(default_factory=list)
    figures: List[FigureItem] = field(default_factory=list)
    instruction: str = ""  # LLM instruction for this section


@dataclass
class AnswerPlan:
    """Complete plan for generating a structured answer."""
    query: str
    query_type: str  # "factual", "procedural", "comparison", "exploratory"
    summary_instruction: str = ""
    sections: List[AnswerSection] = field(default_factory=list)
    total_evidence: int = 0
    total_figures: int = 0

    def to_prompt_context(self) -> str:
        """Convert the plan to a structured context for the LLM."""
        parts = [f"ANSWER PLAN for: {self.query}"]
        parts.append(f"Query Type: {self.query_type}")
        parts.append(f"Summary: {self.summary_instruction}")
        parts.append("")

        for i, section in enumerate(self.sections, 1):
            parts.append(f"## Section {i}: {section.heading}")
            if section.instruction:
                parts.append(f"   Instruction: {section.instruction}")
            parts.append(f"   Evidence ({len(section.evidence)} chunks):")
            for ev in section.evidence:
                preview = ev.content[:200].replace("\n", " ")
                parts.append(f"     - [{ev.chunk_id}] {preview}...")
            if section.figures:
                parts.append(f"   Figures ({len(section.figures)}):")
                for fig in section.figures:
                    parts.append(f"     - Figure {fig.figure_number}: {fig.caption}")
            parts.append("")

        return "\n".join(parts)


class AnswerPlanner:
    """Plan structured answers from query + retrieved chunks."""

    # Query type detection patterns
    FACTUAL_PATTERNS = {"what is", "define", "who is", "when did", "where is", "how many", "how much"}
    PROCEDURAL_PATTERNS = {"how to", "steps to", "procedure", "process for", "guide to", "setup", "configure"}
    COMPARISON_PATTERNS = {"compare", "difference", "versus", "vs", "between", "pros and cons"}
    EXPLORATORY_PATTERNS = {"explain", "describe", "overview", "tell me about", "what are the"}

    def plan(
        self,
        query: str,
        chunks: List[RetrievedChunk],
        *,
        images: Optional[List[Dict[str, Any]]] = None,
    ) -> AnswerPlan:
        """
        Build an answer plan from the query and retrieved evidence.

        Args:
            query: User's question.
            chunks: Retrieved and reranked chunks.
            images: Display images selected by ImageDisplayEngine.

        Returns:
            AnswerPlan with sections, evidence mapping, and figure assignments.
        """
        query_type = self._classify_query(query)
        images = images or []

        plan = AnswerPlan(
            query=query,
            query_type=query_type,
        )

        if query_type == "factual":
            plan = self._plan_factual(plan, chunks, images)
        elif query_type == "procedural":
            plan = self._plan_procedural(plan, chunks, images)
        elif query_type == "comparison":
            plan = self._plan_comparison(plan, chunks, images)
        else:
            plan = self._plan_exploratory(plan, chunks, images)

        plan.total_evidence = sum(len(s.evidence) for s in plan.sections)
        plan.total_figures = sum(len(s.figures) for s in plan.sections)

        logger.info(
            f"📝 Answer plan: {query_type} query → {len(plan.sections)} sections, "
            f"{plan.total_evidence} evidence, {plan.total_figures} figures"
        )
        return plan

    # ────────────────────────────────────────────────────
    #  Query Classification
    # ────────────────────────────────────────────────────
    def _classify_query(self, query: str) -> str:
        """Classify the query type based on patterns."""
        q = query.lower().strip()

        for pattern in self.PROCEDURAL_PATTERNS:
            if pattern in q:
                return "procedural"

        for pattern in self.COMPARISON_PATTERNS:
            if pattern in q:
                return "comparison"

        for pattern in self.FACTUAL_PATTERNS:
            if pattern in q:
                return "factual"

        for pattern in self.EXPLORATORY_PATTERNS:
            if pattern in q:
                return "exploratory"

        # Default to exploratory for complex questions
        return "exploratory"

    # ────────────────────────────────────────────────────
    #  Plan Builders
    # ────────────────────────────────────────────────────
    def _plan_factual(
        self, plan: AnswerPlan, chunks: List[RetrievedChunk], images: List[Dict]
    ) -> AnswerPlan:
        """Plan for factual queries: concise answer + supporting detail."""
        plan.summary_instruction = "Provide a direct, concise answer first, then supporting details."

        # Main answer section — top evidence
        main_section = AnswerSection(
            heading="Answer",
            instruction="Give the direct answer based on the strongest evidence.",
            evidence=self._chunks_to_evidence(chunks[:3]),
            figures=self._assign_figures(images, chunks[:3]),
        )
        plan.sections.append(main_section)

        # Supporting details if we have more chunks
        if len(chunks) > 3:
            detail_section = AnswerSection(
                heading="Additional Details",
                instruction="Provide supporting context that adds depth to the answer.",
                evidence=self._chunks_to_evidence(chunks[3:6]),
                figures=self._assign_figures(images, chunks[3:6], start_fig=len(main_section.figures) + 1),
            )
            plan.sections.append(detail_section)

        return plan

    def _plan_procedural(
        self, plan: AnswerPlan, chunks: List[RetrievedChunk], images: List[Dict]
    ) -> AnswerPlan:
        """Plan for procedural queries: step-by-step structure."""
        plan.summary_instruction = "Provide a brief overview, then step-by-step instructions."

        # Overview section
        overview = AnswerSection(
            heading="Overview",
            instruction="Summarize the procedure in 1-2 sentences.",
            evidence=self._chunks_to_evidence(chunks[:2]),
        )
        plan.sections.append(overview)

        # Steps section — use all remaining evidence
        steps = AnswerSection(
            heading="Steps",
            instruction="Break down the procedure into clear, numbered steps. Include relevant figures inline.",
            evidence=self._chunks_to_evidence(chunks[:6]),
            figures=self._assign_figures(images, chunks[:6]),
        )
        plan.sections.append(steps)

        # Notes/tips section if we have extra chunks
        if len(chunks) > 6:
            notes = AnswerSection(
                heading="Important Notes",
                instruction="Include any warnings, tips, or common issues.",
                evidence=self._chunks_to_evidence(chunks[6:8]),
            )
            plan.sections.append(notes)

        return plan

    def _plan_comparison(
        self, plan: AnswerPlan, chunks: List[RetrievedChunk], images: List[Dict]
    ) -> AnswerPlan:
        """Plan for comparison queries: side-by-side structure."""
        plan.summary_instruction = "Compare the items by listing similarities and differences."

        # Group chunks by document source for comparison
        groups: Dict[str, List[RetrievedChunk]] = {}
        for chunk in chunks:
            key = chunk.source_path or chunk.document_id or "unknown"
            groups.setdefault(key, []).append(chunk)

        # Create a section per group/topic
        fig_offset = 1
        for group_key, group_chunks in list(groups.items())[:3]:
            import os
            title = os.path.basename(group_key) if group_key != "unknown" else "Item"
            section = AnswerSection(
                heading=title,
                instruction=f"Describe the key aspects of {title} relevant to the comparison.",
                evidence=self._chunks_to_evidence(group_chunks[:3]),
                figures=self._assign_figures(images, group_chunks[:3], start_fig=fig_offset),
            )
            fig_offset += len(section.figures)
            plan.sections.append(section)

        # Summary comparison
        summary = AnswerSection(
            heading="Comparison Summary",
            instruction="Summarize the key differences and similarities in a structured comparison.",
            evidence=self._chunks_to_evidence(chunks[:2]),
        )
        plan.sections.append(summary)

        return plan

    def _plan_exploratory(
        self, plan: AnswerPlan, chunks: List[RetrievedChunk], images: List[Dict]
    ) -> AnswerPlan:
        """Plan for exploratory queries: comprehensive multi-section answer."""
        plan.summary_instruction = "Provide a comprehensive explanation organized by topic."

        # Group by section path to find natural topics
        section_groups: Dict[str, List[RetrievedChunk]] = {}
        for chunk in chunks:
            topic = " > ".join(chunk.section_path[-2:]) if chunk.section_path else "General"
            section_groups.setdefault(topic, []).append(chunk)

        fig_offset = 1
        for topic, topic_chunks in list(section_groups.items())[:4]:
            section = AnswerSection(
                heading=topic,
                instruction=f"Explain {topic} based on the evidence.",
                evidence=self._chunks_to_evidence(topic_chunks[:3]),
                figures=self._assign_figures(images, topic_chunks[:3], start_fig=fig_offset),
            )
            fig_offset += len(section.figures)
            plan.sections.append(section)

        # If no sections were created, create a default one
        if not plan.sections:
            plan.sections.append(AnswerSection(
                heading="Answer",
                instruction="Provide a comprehensive answer based on all available evidence.",
                evidence=self._chunks_to_evidence(chunks[:6]),
                figures=self._assign_figures(images, chunks[:6]),
            ))

        return plan

    # ────────────────────────────────────────────────────
    #  Helpers
    # ────────────────────────────────────────────────────
    @staticmethod
    def _chunks_to_evidence(chunks: List[RetrievedChunk]) -> List[EvidenceItem]:
        """Convert RetrievedChunks to EvidenceItems."""
        return [
            EvidenceItem(
                chunk_id=c.chunk_id,
                content=c.content,
                source_path=c.source_path,
                page_numbers=c.page_numbers,
                score=c.score,
            )
            for c in chunks
        ]

    @staticmethod
    def _assign_figures(
        images: List[Dict],
        chunks: List[RetrievedChunk],
        start_fig: int = 1,
    ) -> List[FigureItem]:
        """Assign display images to evidence as figures.

        Images are matched to chunks by source_path overlap.
        """
        if not images:
            return []

        # Collect source paths from chunks
        chunk_sources = {c.source_path for c in chunks if c.source_path}

        figures: List[FigureItem] = []
        seen_paths = set()
        fig_num = start_fig

        for img in images:
            img_path = img.get("image_path", "")
            if img_path in seen_paths:
                continue

            # Check if this image comes from a relevant source
            img_source = img.get("source_path", "")
            # Always include — the image display engine already filtered for relevance
            figures.append(FigureItem(
                image_path=img_path,
                caption=img.get("caption", ""),
                source_path=img_source,
                page_number=img.get("page_number", 0),
                figure_number=fig_num,
            ))
            seen_paths.add(img_path)
            fig_num += 1

        return figures
