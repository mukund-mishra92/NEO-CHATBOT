"""
Unit tests for the RAG Evaluation Framework (Phase 10).
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from evaluation.rag_evaluation import (
    RAGEvaluator,
    EvalCase,
    RetrievalMetrics,
    ImageMetrics,
    AnswerMetrics,
    EvalResult,
    EvalSummary,
)


# ──────────────────────────────────────────
#  Dataset Loading
# ──────────────────────────────────────────

class TestDatasetLoading:
    """Test evaluation dataset loading."""

    def test_load_dataset(self, tmp_path):
        dataset = [
            {
                "id": 1,
                "query": "What is NEO?",
                "category": "factual",
                "expected_topics": ["NEO"],
                "expected_sources": [],
                "expects_images": False,
                "difficulty": "easy",
            }
        ]
        path = tmp_path / "test_dataset.json"
        path.write_text(json.dumps(dataset))

        evaluator = RAGEvaluator(dataset_path=str(path), dry_run=True)
        count = evaluator.load_dataset()
        assert count == 1
        assert evaluator.cases[0].query == "What is NEO?"

    def test_load_full_dataset(self):
        """Load the real evaluation dataset."""
        ds_path = Path(__file__).parent.parent.parent.parent / "data" / "rag_evaluation_dataset.json"
        if not ds_path.exists():
            pytest.skip("Evaluation dataset not found")
        evaluator = RAGEvaluator(dataset_path=str(ds_path), dry_run=True)
        count = evaluator.load_dataset()
        assert count >= 50


# ──────────────────────────────────────────
#  Metric Computations
# ──────────────────────────────────────────

class TestRetrievalMetrics:
    """Test retrieval quality computation."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.evaluator = RAGEvaluator(dry_run=True)

    def _make_case(self, topics):
        return EvalCase(
            id=1, query="test", category="factual",
            expected_topics=topics, expected_sources=[],
            expects_images=False, difficulty="easy",
        )

    def _make_chunk(self, content, score=0.8):
        """Create a mock chunk with needed attributes."""
        from unittest.mock import MagicMock
        chunk = MagicMock()
        chunk.content = content
        chunk.score = score
        return chunk

    def test_perfect_recall(self):
        case = self._make_case(["NEO", "warehouse"])
        chunks = [
            self._make_chunk("NEO warehouse management system"),
        ]
        metrics = self.evaluator._compute_retrieval_metrics(case, chunks, top_k=5)
        assert metrics.recall_at_k == 1.0

    def test_partial_recall(self):
        case = self._make_case(["NEO", "warehouse", "robot"])
        chunks = [
            self._make_chunk("NEO is a system"),
        ]
        metrics = self.evaluator._compute_retrieval_metrics(case, chunks, top_k=5)
        assert 0.0 < metrics.recall_at_k < 1.0

    def test_zero_recall(self):
        case = self._make_case(["robot", "arm"])
        chunks = [
            self._make_chunk("The weather is nice today"),
        ]
        metrics = self.evaluator._compute_retrieval_metrics(case, chunks, top_k=5)
        assert metrics.recall_at_k == 0.0

    def test_empty_chunks(self):
        case = self._make_case(["NEO"])
        metrics = self.evaluator._compute_retrieval_metrics(case, [], top_k=5)
        assert metrics.recall_at_k == 0.0

    def test_mrr_first_chunk(self):
        case = self._make_case(["NEO"])
        chunks = [self._make_chunk("NEO system overview")]
        metrics = self.evaluator._compute_retrieval_metrics(case, chunks, top_k=5)
        assert metrics.mrr == 1.0

    def test_mrr_second_chunk(self):
        case = self._make_case(["robots"])
        chunks = [
            self._make_chunk("Unrelated content"),
            self._make_chunk("robots in the warehouse"),
        ]
        metrics = self.evaluator._compute_retrieval_metrics(case, chunks, top_k=5)
        assert metrics.mrr == 0.5


class TestImageMetrics:
    """Test image relevance computation."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.evaluator = RAGEvaluator(dry_run=True)

    def _make_case(self, expects_images, topics):
        return EvalCase(
            id=1, query="test", category="factual",
            expected_topics=topics, expected_sources=[],
            expects_images=expects_images, difficulty="easy",
        )

    def test_expected_and_returned(self):
        case = self._make_case(True, ["robot"])
        images = [{"caption": "robot arm in warehouse", "image_path": "img.png"}]
        metrics = self.evaluator._compute_image_metrics(case, images)
        assert metrics.image_recall == 1.0
        assert metrics.image_precision == 1.0

    def test_expected_but_not_returned(self):
        case = self._make_case(True, ["robot"])
        metrics = self.evaluator._compute_image_metrics(case, [])
        assert metrics.image_recall == 0.0

    def test_not_expected_none_returned(self):
        case = self._make_case(False, ["robot"])
        metrics = self.evaluator._compute_image_metrics(case, [])
        assert metrics.image_recall == 1.0  # Not expecting = always "recalled"
        assert metrics.image_precision == 1.0

    def test_irrelevant_images(self):
        case = self._make_case(True, ["robot"])
        images = [{"caption": "sunset photo", "image_path": "sun.png"}]
        metrics = self.evaluator._compute_image_metrics(case, images)
        assert metrics.image_recall == 1.0  # Images were returned
        assert metrics.image_precision == 0.0  # But not relevant


class TestAnswerMetrics:
    """Test answer quality computation."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.evaluator = RAGEvaluator(dry_run=True)

    def _make_case(self, topics):
        return EvalCase(
            id=1, query="test", category="factual",
            expected_topics=topics, expected_sources=[],
            expects_images=False, difficulty="easy",
        )

    def test_full_topic_coverage(self):
        case = self._make_case(["NEO", "warehouse"])
        metrics = self.evaluator._compute_answer_metrics(case, "NEO is a warehouse management system")
        assert metrics.topic_coverage == 1.0

    def test_partial_coverage(self):
        case = self._make_case(["NEO", "warehouse", "robot"])
        metrics = self.evaluator._compute_answer_metrics(case, "NEO is a system")
        assert 0.0 < metrics.topic_coverage < 1.0

    def test_structure_detected(self):
        case = self._make_case(["NEO"])
        context = "## Overview\nNEO is a system\n## Features\nIt has features"
        metrics = self.evaluator._compute_answer_metrics(case, context)
        assert metrics.has_structure is True

    def test_empty_context(self):
        case = self._make_case(["NEO"])
        metrics = self.evaluator._compute_answer_metrics(case, "")
        assert metrics.topic_coverage == 0.0
        assert metrics.word_count == 0


# ──────────────────────────────────────────
#  Summary Computation
# ──────────────────────────────────────────

class TestSummaryComputation:
    """Test summary aggregation."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.evaluator = RAGEvaluator(dry_run=True)

    def test_empty_results(self):
        self.evaluator.results = []
        summary = self.evaluator._compute_summary()
        assert summary.total_cases == 0

    def test_summary_with_results(self):
        self.evaluator.results = [
            EvalResult(
                case_id=1, query="q1", category="factual", difficulty="easy",
                retrieval=RetrievalMetrics(recall_at_k=0.8, precision_at_k=0.6, mrr=1.0),
                answer=AnswerMetrics(topic_coverage=0.9),
                latency_ms=100,
            ),
            EvalResult(
                case_id=2, query="q2", category="factual", difficulty="medium",
                retrieval=RetrievalMetrics(recall_at_k=0.6, precision_at_k=0.4, mrr=0.5),
                answer=AnswerMetrics(topic_coverage=0.7),
                latency_ms=200,
            ),
        ]
        summary = self.evaluator._compute_summary()
        assert summary.total_cases == 2
        assert summary.successful == 2
        assert summary.avg_recall_at_k == 0.7
        assert "factual" in summary.by_category


class TestDryRun:
    """Test dry-run mode."""

    def test_dry_run_evaluation(self, tmp_path):
        dataset = [
            {
                "id": 1,
                "query": "What is NEO?",
                "category": "factual",
                "expected_topics": ["NEO"],
                "expected_sources": [],
                "expects_images": False,
                "difficulty": "easy",
            },
            {
                "id": 2,
                "query": "How to configure bots?",
                "category": "procedural",
                "expected_topics": ["configure", "bot"],
                "expected_sources": [],
                "expects_images": False,
                "difficulty": "medium",
            },
        ]
        path = tmp_path / "test_dataset.json"
        path.write_text(json.dumps(dataset))

        evaluator = RAGEvaluator(dataset_path=str(path), dry_run=True)
        evaluator.load_dataset()
        summary = evaluator.evaluate()
        assert summary.total_cases == 2
        assert summary.successful == 2
