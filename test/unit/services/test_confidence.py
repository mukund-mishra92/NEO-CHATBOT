"""
Unit Tests — ConfidenceEvaluator
Target: backend/app/services/sql_assistant/confidence.py

Tests:
  - Weighted formula: 0.7 * llm_conf + 0.3 * exec_conf
  - exec_conf = 1.0 if rows > 0 else 0.4
  - Edge cases: 0.0 confidence, perfect confidence
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.confidence import ConfidenceEvaluator


@pytest.fixture
def evaluator():
    return ConfidenceEvaluator()


class FakeGenResult:
    def __init__(self, confidence):
        self.confidence = confidence

class FakeExecResult:
    def __init__(self, row_count):
        self.row_count = row_count


# ===================================================================
# FORMULA VERIFICATION
# ===================================================================
class TestConfidenceFormula:

    def test_high_confidence_with_rows(self, evaluator):
        """0.9 * 0.7 + 1.0 * 0.3 = 0.63 + 0.30 = 0.93"""
        score = evaluator.compute(FakeGenResult(0.9), FakeExecResult(10))
        assert abs(score - 0.93) < 1e-6

    def test_high_confidence_no_rows(self, evaluator):
        """0.9 * 0.7 + 0.4 * 0.3 = 0.63 + 0.12 = 0.75"""
        score = evaluator.compute(FakeGenResult(0.9), FakeExecResult(0))
        assert abs(score - 0.75) < 1e-6

    def test_low_confidence_with_rows(self, evaluator):
        """0.3 * 0.7 + 1.0 * 0.3 = 0.21 + 0.30 = 0.51"""
        score = evaluator.compute(FakeGenResult(0.3), FakeExecResult(5))
        assert abs(score - 0.51) < 1e-6

    def test_zero_confidence_no_rows(self, evaluator):
        """0.0 * 0.7 + 0.4 * 0.3 = 0.0 + 0.12 = 0.12"""
        score = evaluator.compute(FakeGenResult(0.0), FakeExecResult(0))
        assert abs(score - 0.12) < 1e-6

    def test_perfect_confidence_with_rows(self, evaluator):
        """1.0 * 0.7 + 1.0 * 0.3 = 1.0"""
        score = evaluator.compute(FakeGenResult(1.0), FakeExecResult(100))
        assert abs(score - 1.0) < 1e-6

    def test_single_row_counts_as_data(self, evaluator):
        """Even 1 row → exec_conf = 1.0"""
        score = evaluator.compute(FakeGenResult(0.5), FakeExecResult(1))
        expected = 0.5 * 0.7 + 1.0 * 0.3
        assert abs(score - expected) < 1e-6
