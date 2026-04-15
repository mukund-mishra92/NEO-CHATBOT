"""
RAG Pipeline Evaluation Framework
==================================

Phase 10 of the Multimodal RAG Upgrade Plan.

Evaluates the RAG pipeline across 4 quality dimensions:
  1. Retrieval Quality   — recall@k, precision@k, MRR
  2. Image Relevance     — Were images returned when expected? Were they relevant?
  3. Answer Quality      — Topic coverage, structure, answer completeness
  4. Latency             — End-to-end response time

Usage:
  cd Neo-Chatbot
  python -m evaluation.rag_evaluation                        # Full run
  python -m evaluation.rag_evaluation --dry-run              # Offline mode
  python -m evaluation.rag_evaluation --category procedural  # Filter by category
  python -m evaluation.rag_evaluation --ids 1,2,10           # Specific cases
"""

import sys
import json
import time
import re
import argparse
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional
from datetime import datetime
from dataclasses import dataclass, field, asdict

# Add project root to path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend"))

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("rag_evaluation")


# ============================================================
# Data classes
# ============================================================

@dataclass
class EvalCase:
    """A single evaluation case from the dataset."""
    id: int
    query: str
    category: str
    expected_topics: List[str]
    expected_sources: List[str]
    expects_images: bool
    difficulty: str
    notes: str = ""


@dataclass
class RetrievalMetrics:
    """Retrieval quality metrics for a single case."""
    recall_at_k: float = 0.0       # Fraction of expected topics found in top-k chunks
    precision_at_k: float = 0.0    # Fraction of top-k chunks that are relevant
    mrr: float = 0.0               # Mean Reciprocal Rank of first relevant chunk
    num_chunks: int = 0


@dataclass
class ImageMetrics:
    """Image relevance metrics for a single case."""
    images_expected: bool = False
    images_returned: int = 0
    image_recall: float = 0.0      # 1.0 if images expected and returned, else 0.0
    image_precision: float = 0.0   # 1.0 if returned images are relevant (keyword match)


@dataclass
class AnswerMetrics:
    """Answer quality metrics for a single case."""
    topic_coverage: float = 0.0    # Fraction of expected topics found in answer
    has_structure: bool = False     # Whether answer has headings / sections
    has_citations: bool = False     # Whether answer references source documents
    word_count: int = 0
    structured_sections: int = 0   # Number of sections in structured_response


@dataclass
class EvalResult:
    """Complete evaluation result for one case."""
    case_id: int
    query: str
    category: str
    difficulty: str
    retrieval: RetrievalMetrics = field(default_factory=RetrievalMetrics)
    image: ImageMetrics = field(default_factory=ImageMetrics)
    answer: AnswerMetrics = field(default_factory=AnswerMetrics)
    latency_ms: float = 0.0
    error: Optional[str] = None


@dataclass
class EvalSummary:
    """Aggregated evaluation summary."""
    total_cases: int = 0
    successful: int = 0
    failed: int = 0
    avg_recall_at_k: float = 0.0
    avg_precision_at_k: float = 0.0
    avg_mrr: float = 0.0
    avg_topic_coverage: float = 0.0
    avg_image_recall: float = 0.0
    avg_image_precision: float = 0.0
    avg_latency_ms: float = 0.0
    p95_latency_ms: float = 0.0
    by_category: Dict[str, Dict[str, float]] = field(default_factory=dict)
    by_difficulty: Dict[str, Dict[str, float]] = field(default_factory=dict)


# ============================================================
# Evaluation Engine
# ============================================================

class RAGEvaluator:
    """Evaluate the RAG pipeline against a test dataset."""

    def __init__(self, dataset_path: Optional[str] = None, dry_run: bool = False):
        self.dataset_path = Path(dataset_path or ROOT / "data" / "rag_evaluation_dataset.json")
        self.dry_run = dry_run
        self.cases: List[EvalCase] = []
        self.results: List[EvalResult] = []
        self.pipeline = None
        self.kb_service = None

    def load_dataset(self) -> int:
        """Load evaluation cases from JSON file."""
        with open(self.dataset_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        self.cases = [EvalCase(**c) for c in raw]
        return len(self.cases)

    def init_pipeline(self):
        """Initialize the RAG pipeline for evaluation."""
        if self.dry_run:
            return

        try:
            from app.ingetion.pipeline import RAGPipeline
            chroma_dir = str(ROOT / "data" / "chroma_db")
            self.pipeline = RAGPipeline(
                chroma_persist_dir=chroma_dir,
                enable_images=True,
                enable_ocr=False,
            )
            status = self.pipeline.get_status()
            print(f"  Pipeline ready: {status['total_chunks']} chunks in ChromaDB")
        except Exception as e:
            print(f"  [WARN] Pipeline init failed: {e}")
            self.dry_run = True

    def evaluate(
        self,
        *,
        category: Optional[str] = None,
        difficulty: Optional[str] = None,
        case_ids: Optional[List[int]] = None,
        top_k: int = 8,
    ) -> EvalSummary:
        """Run evaluation on selected cases."""
        # Filter cases
        cases = self.cases
        if category:
            cases = [c for c in cases if c.category == category]
        if difficulty:
            cases = [c for c in cases if c.difficulty == difficulty]
        if case_ids:
            cases = [c for c in cases if c.id in case_ids]

        print(f"\n{'='*70}")
        print(f"  RAG Pipeline Evaluation — {len(cases)} cases")
        print(f"  Mode: {'DRY RUN (no pipeline)' if self.dry_run else 'LIVE'}")
        print(f"{'='*70}\n")

        self.results = []
        for case in cases:
            result = self._evaluate_case(case, top_k=top_k)
            self.results.append(result)

            status = "OK" if result.error is None else "FAIL"
            print(
                f"  {status} [{result.case_id:>3}] {result.query[:50]:<50} "
                f"recall={result.retrieval.recall_at_k:.2f} "
                f"topics={result.answer.topic_coverage:.2f} "
                f"latency={result.latency_ms:.0f}ms"
            )

        summary = self._compute_summary()
        self._print_summary(summary)
        return summary

    def _evaluate_case(self, case: EvalCase, top_k: int = 8) -> EvalResult:
        """Evaluate a single case."""
        result = EvalResult(
            case_id=case.id,
            query=case.query,
            category=case.category,
            difficulty=case.difficulty,
        )

        if self.dry_run:
            # In dry-run mode, generate synthetic metrics
            result.retrieval = RetrievalMetrics(recall_at_k=0.0, precision_at_k=0.0, mrr=0.0)
            result.answer = AnswerMetrics(topic_coverage=0.0, word_count=0)
            result.image = ImageMetrics(images_expected=case.expects_images)
            return result

        try:
            start = time.perf_counter()
            rag_result = self.pipeline.retrieve_context(case.query, top_k=top_k)
            elapsed = (time.perf_counter() - start) * 1000
            result.latency_ms = round(elapsed, 1)

            # Retrieval metrics
            result.retrieval = self._compute_retrieval_metrics(
                case, rag_result.get("retrieved_chunks", []), top_k
            )

            # Image metrics
            result.image = self._compute_image_metrics(
                case, rag_result.get("images", [])
            )

            # Answer metrics (from context text)
            result.answer = self._compute_answer_metrics(
                case, rag_result.get("context", "")
            )

        except Exception as e:
            result.error = str(e)
            logger.error(f"Case {case.id} failed: {e}")

        return result

    # ────────────────────────────────────────
    #  Metric Computations
    # ────────────────────────────────────────

    def _compute_retrieval_metrics(
        self, case: EvalCase, chunks: list, top_k: int
    ) -> RetrievalMetrics:
        """Compute recall@k, precision@k, MRR from retrieved chunks."""
        if not chunks:
            return RetrievalMetrics()

        topics = [t.lower() for t in case.expected_topics]
        k = min(top_k, len(chunks))

        # Check which topics appear in chunk content
        topics_found = set()
        first_relevant_rank = None

        for rank, chunk in enumerate(chunks[:k], 1):
            content_lower = chunk.content.lower()
            chunk_has_topic = False
            for topic in topics:
                if topic in content_lower:
                    topics_found.add(topic)
                    chunk_has_topic = True
            if chunk_has_topic and first_relevant_rank is None:
                first_relevant_rank = rank

        recall = len(topics_found) / max(len(topics), 1)
        # Precision: fraction of chunks that contain at least one expected topic
        relevant_chunks = sum(
            1 for c in chunks[:k]
            if any(t in c.content.lower() for t in topics)
        )
        precision = relevant_chunks / k if k > 0 else 0.0
        mrr = 1.0 / first_relevant_rank if first_relevant_rank else 0.0

        return RetrievalMetrics(
            recall_at_k=round(recall, 3),
            precision_at_k=round(precision, 3),
            mrr=round(mrr, 3),
            num_chunks=len(chunks),
        )

    def _compute_image_metrics(
        self, case: EvalCase, images: list
    ) -> ImageMetrics:
        """Compute image relevance metrics."""
        metrics = ImageMetrics(
            images_expected=case.expects_images,
            images_returned=len(images),
        )

        if case.expects_images:
            metrics.image_recall = 1.0 if len(images) > 0 else 0.0
        else:
            metrics.image_recall = 1.0  # Not expecting images = always "recalled"

        # Precision: do returned images relate to query topics?
        if images:
            topics = [t.lower() for t in case.expected_topics]
            relevant = 0
            for img in images:
                caption = (img.get("caption", "") or "").lower()
                source = (img.get("source_document", "") or "").lower()
                text = f"{caption} {source}"
                if any(t in text for t in topics):
                    relevant += 1
            metrics.image_precision = round(relevant / len(images), 3) if images else 0.0
        else:
            metrics.image_precision = 1.0 if not case.expects_images else 0.0

        return metrics

    def _compute_answer_metrics(
        self, case: EvalCase, context: str
    ) -> AnswerMetrics:
        """Compute answer quality metrics from assembled context."""
        if not context:
            return AnswerMetrics()

        context_lower = context.lower()
        topics = [t.lower() for t in case.expected_topics]

        # Topic coverage
        found = sum(1 for t in topics if t in context_lower)
        coverage = found / max(len(topics), 1)

        # Structure detection
        has_structure = bool(re.search(r"(?:^|\n)#{1,4}\s+|(?:^|\n)\*\*[^*]+\*\*", context))

        # Citation detection
        has_citations = bool(re.search(r"\[(?:Document|Source|Page)\s*\d", context, re.IGNORECASE))

        return AnswerMetrics(
            topic_coverage=round(coverage, 3),
            has_structure=has_structure,
            has_citations=has_citations,
            word_count=len(context.split()),
        )

    # ────────────────────────────────────────
    #  Summary
    # ────────────────────────────────────────

    def _compute_summary(self) -> EvalSummary:
        """Aggregate results into a summary."""
        successful = [r for r in self.results if r.error is None]
        summary = EvalSummary(
            total_cases=len(self.results),
            successful=len(successful),
            failed=len(self.results) - len(successful),
        )

        if not successful:
            return summary

        # Averages
        summary.avg_recall_at_k = _avg([r.retrieval.recall_at_k for r in successful])
        summary.avg_precision_at_k = _avg([r.retrieval.precision_at_k for r in successful])
        summary.avg_mrr = _avg([r.retrieval.mrr for r in successful])
        summary.avg_topic_coverage = _avg([r.answer.topic_coverage for r in successful])

        # Image metrics (only for cases that expect images)
        img_cases = [r for r in successful if r.image.images_expected]
        if img_cases:
            summary.avg_image_recall = _avg([r.image.image_recall for r in img_cases])
            summary.avg_image_precision = _avg([r.image.image_precision for r in img_cases])

        # Latency
        latencies = sorted([r.latency_ms for r in successful if r.latency_ms > 0])
        if latencies:
            summary.avg_latency_ms = round(_avg(latencies), 1)
            p95_idx = max(0, int(len(latencies) * 0.95) - 1)
            summary.p95_latency_ms = round(latencies[p95_idx], 1)

        # By category
        for cat in {r.category for r in successful}:
            cat_results = [r for r in successful if r.category == cat]
            summary.by_category[cat] = {
                "count": len(cat_results),
                "avg_recall": _avg([r.retrieval.recall_at_k for r in cat_results]),
                "avg_topic_coverage": _avg([r.answer.topic_coverage for r in cat_results]),
            }

        # By difficulty
        for diff in {r.difficulty for r in successful}:
            diff_results = [r for r in successful if r.difficulty == diff]
            summary.by_difficulty[diff] = {
                "count": len(diff_results),
                "avg_recall": _avg([r.retrieval.recall_at_k for r in diff_results]),
                "avg_topic_coverage": _avg([r.answer.topic_coverage for r in diff_results]),
            }

        return summary

    def _print_summary(self, summary: EvalSummary):
        """Print a formatted summary report."""
        print(f"\n{'='*70}")
        print("  EVALUATION SUMMARY")
        print(f"{'='*70}")
        print(f"  Total cases:  {summary.total_cases}")
        print(f"  Successful:   {summary.successful}")
        print(f"  Failed:       {summary.failed}")
        print()
        print(f"  [Retrieval Quality]")
        print(f"     Recall@k:       {summary.avg_recall_at_k:.1%}")
        print(f"     Precision@k:    {summary.avg_precision_at_k:.1%}")
        print(f"     MRR:            {summary.avg_mrr:.3f}")
        print()
        print(f"  [Answer Quality]")
        print(f"     Topic Coverage: {summary.avg_topic_coverage:.1%}")
        print()
        print(f"  [Image Relevance]")
        print(f"     Image Recall:   {summary.avg_image_recall:.1%}")
        print(f"     Image Precision:{summary.avg_image_precision:.1%}")
        print()
        print(f"  [Latency]")
        print(f"     Average:        {summary.avg_latency_ms:.0f} ms")
        print(f"     P95:            {summary.p95_latency_ms:.0f} ms")

        if summary.by_category:
            print(f"\n  [By Category]:")
            for cat, metrics in sorted(summary.by_category.items()):
                print(
                    f"     {cat:<15} n={metrics['count']:<3} "
                    f"recall={metrics['avg_recall']:.1%} "
                    f"topics={metrics['avg_topic_coverage']:.1%}"
                )

        if summary.by_difficulty:
            print(f"\n  [By Difficulty]:")
            for diff, metrics in sorted(summary.by_difficulty.items()):
                print(
                    f"     {diff:<10} n={metrics['count']:<3} "
                    f"recall={metrics['avg_recall']:.1%} "
                    f"topics={metrics['avg_topic_coverage']:.1%}"
                )

        print(f"\n{'='*70}")

    def save_results(self, output_path: Optional[str] = None):
        """Save detailed results to JSON."""
        path = Path(output_path or ROOT / "data" / "rag_evaluation_results.json")
        data = {
            "timestamp": datetime.now().isoformat(),
            "total_cases": len(self.results),
            "results": [asdict(r) for r in self.results],
            "summary": asdict(self._compute_summary()),
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, default=str)
        print(f"\n  Results saved to {path}")


def _avg(values: List[float]) -> float:
    """Safe average."""
    return round(sum(values) / max(len(values), 1), 3)


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="RAG Pipeline Evaluation")
    parser.add_argument("--dry-run", action="store_true", help="Run without pipeline (offline)")
    parser.add_argument("--category", type=str, help="Filter by category (factual/procedural/comparison/exploratory)")
    parser.add_argument("--difficulty", type=str, help="Filter by difficulty (easy/medium/hard)")
    parser.add_argument("--ids", type=str, help="Comma-separated case IDs (e.g., 1,2,10)")
    parser.add_argument("--top-k", type=int, default=8, help="Number of chunks to retrieve")
    parser.add_argument("--output", type=str, help="Output JSON path")
    parser.add_argument("--dataset", type=str, help="Dataset JSON path")
    args = parser.parse_args()

    evaluator = RAGEvaluator(dataset_path=args.dataset, dry_run=args.dry_run)

    print("\n>> Loading evaluation dataset...")
    count = evaluator.load_dataset()
    print(f"  Loaded {count} cases")

    print("\n>> Initializing RAG pipeline...")
    evaluator.init_pipeline()

    case_ids = None
    if args.ids:
        case_ids = [int(x.strip()) for x in args.ids.split(",")]

    evaluator.evaluate(
        category=args.category,
        difficulty=args.difficulty,
        case_ids=case_ids,
        top_k=args.top_k,
    )

    evaluator.save_results(args.output)


if __name__ == "__main__":
    main()
