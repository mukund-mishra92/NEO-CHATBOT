"""
NEO Chatbot — KPI Resolver Evaluation Framework
================================================

Evaluates the KPI resolver's ability to match natural-language questions
to the correct dashboard KPI.

Three evaluation sources:
  1. **Registry ground-truth**: Every user_query in kpi_registry.json is an
     exact match — the resolver MUST return the KPI that owns it.
  2. **Production regression**: Real user queries that have been manually
     labelled with the correct kpi_id (from debugging sessions).
  3. **Negative cases**: Queries that should NOT match any KPI (must return None).

Metrics reported:
  - Overall accuracy (correct / total)
  - Per-category accuracy (bot / inventory / orders / station)
  - False-positive rate (non-KPI queries wrongly matched)
  - False-negative rate (KPI queries that returned None)
  - Misroutes (matched wrong KPI)
  - Mean confidence score for correct matches
  - Top-5 recall (correct KPI appears in top-5 candidates)

Usage:
  cd Neo-Chatbot
  python -m evaluation.kpi_resolver_evaluation                  # Full run
  python -m evaluation.kpi_resolver_evaluation --source registry  # Registry only
  python -m evaluation.kpi_resolver_evaluation --source production
  python -m evaluation.kpi_resolver_evaluation --source negative
  python -m evaluation.kpi_resolver_evaluation --category inventory
  python -m evaluation.kpi_resolver_evaluation --verbose
  python -m evaluation.kpi_resolver_evaluation --top-k 5        # Top-5 recall
"""

import sys
import json
import time
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict
from datetime import datetime

# Add project root to path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend"))

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("kpi_evaluation")


# ============================================================
# Data classes
# ============================================================

@dataclass
class KPITestCase:
    """A single evaluation case."""
    id: int
    source: str                     # "registry" | "production" | "negative"
    question: str                   # Raw user question
    expected_kpi_id: Optional[str]  # None for negative cases
    expected_kpi_name: str = ""
    category: str = ""              # bot / inventory / orders / station
    synonym_normalised: str = ""    # If synonym resolver would transform it
    original_question: str = ""     # If different from question (pre-synonym)
    tenant_values: Optional[List[str]] = None
    difficulty: str = "medium"      # easy / medium / hard


@dataclass
class EvalResult:
    """Result of evaluating a single test case."""
    test_id: int
    source: str
    question: str
    expected_kpi_id: Optional[str]
    expected_kpi_name: str
    actual_kpi_id: Optional[str]
    actual_kpi_name: str
    actual_score: float
    correct: bool
    error_type: str  # "" | "false_negative" | "false_positive" | "misroute"
    top5_hit: bool   # True if expected KPI is in top-5
    latency_ms: float


# ============================================================
# Production regression cases (manually labelled)
# ============================================================

PRODUCTION_CASES: List[dict] = [
    # --- Synonym-embedding fixes ---
    {
        "question": "distinct article in blr",
        "original_question": "distinct sku in blr",
        "expected_kpi_id": "kpi_033",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },
    {
        "question": "show total distinct article count in blr",
        "original_question": "Show total distinct SKU count in blr",
        "expected_kpi_id": "kpi_033",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },
    {
        "question": "reserve to put in banglore for last one week",
        "expected_kpi_id": "kpi_035",
        "tenant_values": ["blr"],
        "difficulty": "medium",
    },
    {
        "question": "total reserve to put in banglore for last one week",
        "expected_kpi_id": "kpi_035",
        "tenant_values": ["blr"],
        "difficulty": "medium",
    },
    {
        "question": "total blocked article count in banglore",
        "original_question": "Total blocked SKU count in banglore",
        "expected_kpi_id": "kpi_040",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },

    # --- Bin / volume utilization disambiguation ---
    {
        "question": "volume utilization % in blr",
        "expected_kpi_id": "kpi_021",
        "tenant_values": ["blr"],
        "difficulty": "medium",
    },
    {
        "question": "volume utilization percentage in blr",
        "expected_kpi_id": "kpi_021",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },
    {
        "question": "bin used % in blr",
        "expected_kpi_id": "kpi_015",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },
    {
        "question": "bin used percentage in blr",
        "expected_kpi_id": "kpi_015",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },
    {
        "question": "bin used in blr",
        "expected_kpi_id": "kpi_014",
        "tenant_values": ["blr"],
        "difficulty": "hard",
    },

    # --- Count vs utilisation intent ---
    {
        "question": "total bins in blr",
        "expected_kpi_id": "kpi_013",
        "tenant_values": ["blr"],
        "difficulty": "easy",
    },
    {
        "question": "bin utilisation",
        "expected_kpi_id": "kpi_015",
        "difficulty": "easy",
    },

    # --- Active bots / alarms ---
    {
        "question": "how many bots are active?",
        "expected_kpi_id": "kpi_002",
        "difficulty": "easy",
    },
    {
        "question": "active bots in frk",
        "expected_kpi_id": "kpi_002",
        "tenant_values": ["frk"],
        "difficulty": "easy",
    },
    {
        "question": "total alarms per bot",
        "expected_kpi_id": "kpi_008",
        "difficulty": "medium",
    },

    # --- Wave / order queries ---
    {
        "question": "wave counts by type",
        "expected_kpi_id": "kpi_048",
        "difficulty": "easy",
    },

    # --- Station queries ---
    {
        "question": "station wise active vs inactive hours",
        "expected_kpi_id": "kpi_062",
        "difficulty": "medium",
    },
]

# ============================================================
# Negative cases (should NOT match any KPI)
# ============================================================

NEGATIVE_CASES: List[str] = [
    "what is the weather today?",
    "tell me a joke about databases",
    "how many orders are pending?",
    "show me the list of all tables in database",
    "what is the capital of India?",
    "explain the difference between SQL and NoSQL",
    "how to create a stored procedure?",
    "show all columns in bot_master table",
    "delete all records from task_master",
    "what happened yesterday at the warehouse?",
    "can you help me write a python script?",
    "who is the CEO of the company?",
    "how many employees work here?",
    "show me the error logs for today",
    "what is the uptime of the server?",
]


# ============================================================
# Dataset builder
# ============================================================

def build_evaluation_dataset(
    registry_path: str,
    source_filter: Optional[str] = None,
    category_filter: Optional[str] = None,
    sample_per_kpi: int = 0,
) -> List[KPITestCase]:
    """Build the full evaluation dataset.

    Args:
        registry_path: Path to kpi_registry.json
        source_filter: "registry" | "production" | "negative" (all if None)
        category_filter: Filter by category (bot/inventory/orders/station)
        sample_per_kpi: If >0, sample N user_queries per KPI (0 = all)
    """
    registry = json.loads(Path(registry_path).read_text(encoding="utf-8"))
    cases: List[KPITestCase] = []
    case_id = 1

    # ── 1. Registry ground-truth ──
    if source_filter in (None, "registry"):
        for kpi in registry:
            if category_filter and kpi["category"] != category_filter:
                continue
            user_queries = kpi.get("user_queries", [])
            if sample_per_kpi > 0:
                user_queries = user_queries[:sample_per_kpi]
            for uq in user_queries:
                cases.append(KPITestCase(
                    id=case_id,
                    source="registry",
                    question=uq,
                    expected_kpi_id=kpi["id"],
                    expected_kpi_name=kpi["kpi_name"],
                    category=kpi["category"],
                    difficulty="easy",  # exact user_query → should be trivial
                ))
                case_id += 1

    # ── 2. Production regression cases ──
    if source_filter in (None, "production"):
        for pc in PRODUCTION_CASES:
            # Look up category from registry
            cat = ""
            name = ""
            for kpi in registry:
                if kpi["id"] == pc["expected_kpi_id"]:
                    cat = kpi["category"]
                    name = kpi["kpi_name"]
                    break
            if category_filter and cat != category_filter:
                continue
            cases.append(KPITestCase(
                id=case_id,
                source="production",
                question=pc["question"],
                expected_kpi_id=pc["expected_kpi_id"],
                expected_kpi_name=name,
                category=cat,
                original_question=pc.get("original_question", ""),
                tenant_values=pc.get("tenant_values"),
                difficulty=pc.get("difficulty", "medium"),
            ))
            case_id += 1

    # ── 3. Negative cases ──
    if source_filter in (None, "negative"):
        for nq in NEGATIVE_CASES:
            cases.append(KPITestCase(
                id=case_id,
                source="negative",
                question=nq,
                expected_kpi_id=None,
                expected_kpi_name="(none)",
                category="",
                difficulty="medium",
            ))
            case_id += 1

    return cases


# ============================================================
# Evaluation runner
# ============================================================

def run_evaluation(
    cases: List[KPITestCase],
    resolver,
    top_k: int = 5,
    verbose: bool = False,
) -> List[EvalResult]:
    """Run all cases through the resolver and collect results."""
    results: List[EvalResult] = []

    for tc in cases:
        t0 = time.perf_counter()

        # Resolve
        match = resolver.resolve(
            question=tc.question,
            tenant_values=tc.tenant_values,
            original_question=tc.original_question or None,
        )

        # Top-k for recall
        top_matches = resolver.resolve_top_k(
            question=tc.question,
            top_k=top_k,
        )
        top_ids = [m.kpi_id for m in top_matches]
        top5_hit = tc.expected_kpi_id in top_ids if tc.expected_kpi_id else True

        latency_ms = (time.perf_counter() - t0) * 1000

        actual_id = match.kpi_id if match else None
        actual_name = match.kpi_name if match else "(none)"
        actual_score = match.match_score if match else 0.0

        # Determine correctness
        if tc.expected_kpi_id is None:
            # Negative case: correct if resolver returns None
            correct = match is None
            error_type = "false_positive" if not correct else ""
        else:
            # Positive case: correct if KPI ID matches
            if match is None:
                correct = False
                error_type = "false_negative"
            elif match.kpi_id == tc.expected_kpi_id:
                correct = True
                error_type = ""
            else:
                correct = False
                error_type = "misroute"

        result = EvalResult(
            test_id=tc.id,
            source=tc.source,
            question=tc.question,
            expected_kpi_id=tc.expected_kpi_id,
            expected_kpi_name=tc.expected_kpi_name,
            actual_kpi_id=actual_id,
            actual_kpi_name=actual_name,
            actual_score=actual_score,
            correct=correct,
            error_type=error_type,
            top5_hit=top5_hit,
            latency_ms=latency_ms,
        )
        results.append(result)

        if verbose or not correct:
            status = "✅" if correct else "❌"
            print(
                f"  {status} [{tc.source[:4]:>4}] #{tc.id:<4} "
                f"Q: {tc.question[:55]:<57} "
                f"exp={tc.expected_kpi_id or 'None':<8} "
                f"got={actual_id or 'None':<8} "
                f"score={actual_score:.3f} "
                f"{'TOP5' if top5_hit else 'MISS'} "
                f"{error_type}"
            )

    return results


# ============================================================
# Report generation
# ============================================================

def print_report(results: List[EvalResult], cases: List[KPITestCase]):
    """Print a comprehensive evaluation report."""
    total = len(results)
    correct = sum(1 for r in results if r.correct)
    accuracy = correct / total if total else 0

    # By source
    sources = {}
    for r in results:
        s = r.source
        if s not in sources:
            sources[s] = {"total": 0, "correct": 0}
        sources[s]["total"] += 1
        if r.correct:
            sources[s]["correct"] += 1

    # By category (positive cases only)
    categories = {}
    for r in results:
        tc = next((c for c in cases if c.id == r.test_id), None)
        if tc and tc.category:
            cat = tc.category
            if cat not in categories:
                categories[cat] = {"total": 0, "correct": 0}
            categories[cat]["total"] += 1
            if r.correct:
                categories[cat]["correct"] += 1

    # Error breakdown
    false_negatives = [r for r in results if r.error_type == "false_negative"]
    false_positives = [r for r in results if r.error_type == "false_positive"]
    misroutes = [r for r in results if r.error_type == "misroute"]

    # Top-5 recall (positive cases only)
    pos_results = [r for r in results if r.expected_kpi_id is not None]
    top5_hits = sum(1 for r in pos_results if r.top5_hit)
    top5_recall = top5_hits / len(pos_results) if pos_results else 0

    # Mean confidence for correct matches
    correct_scores = [r.actual_score for r in results if r.correct and r.actual_score > 0]
    mean_confidence = sum(correct_scores) / len(correct_scores) if correct_scores else 0

    # Mean latency
    mean_latency = sum(r.latency_ms for r in results) / total if total else 0

    # ── Print report ──
    print("\n" + "=" * 80)
    print("  KPI RESOLVER EVALUATION REPORT")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)

    print(f"\n  Overall Accuracy:     {correct}/{total} ({accuracy:.1%})")
    print(f"  Top-5 Recall:         {top5_hits}/{len(pos_results)} ({top5_recall:.1%})")
    print(f"  Mean Confidence:      {mean_confidence:.3f}")
    print(f"  Mean Latency:         {mean_latency:.1f} ms")

    print(f"\n  ── By Source ──")
    for s, d in sorted(sources.items()):
        acc = d["correct"] / d["total"] if d["total"] else 0
        print(f"    {s:<12} {d['correct']}/{d['total']:<5} ({acc:.1%})")

    print(f"\n  ── By Category ──")
    for c, d in sorted(categories.items()):
        acc = d["correct"] / d["total"] if d["total"] else 0
        print(f"    {c:<12} {d['correct']}/{d['total']:<5} ({acc:.1%})")

    print(f"\n  ── Error Breakdown ──")
    print(f"    False Negatives:    {len(false_negatives)}")
    print(f"    False Positives:    {len(false_positives)}")
    print(f"    Misroutes:          {len(misroutes)}")

    if misroutes:
        print(f"\n  ── Misrouted Queries ──")
        for r in misroutes:
            print(f"    #{r.test_id} Q: {r.question[:55]}")
            print(f"       Expected: {r.expected_kpi_id} ({r.expected_kpi_name})")
            print(f"       Got:      {r.actual_kpi_id} ({r.actual_kpi_name}) score={r.actual_score:.3f}")

    if false_negatives:
        print(f"\n  ── False Negatives (missed KPIs) ──")
        for r in false_negatives[:10]:
            print(f"    #{r.test_id} Q: {r.question[:55]}")
            print(f"       Expected: {r.expected_kpi_id} ({r.expected_kpi_name})  top5={'YES' if r.top5_hit else 'NO'}")

    if false_positives:
        print(f"\n  ── False Positives (should be None) ──")
        for r in false_positives[:10]:
            print(f"    #{r.test_id} Q: {r.question[:55]}")
            print(f"       Matched:  {r.actual_kpi_id} ({r.actual_kpi_name}) score={r.actual_score:.3f}")

    print("\n" + "=" * 80)

    return {
        "accuracy": accuracy,
        "top5_recall": top5_recall,
        "mean_confidence": mean_confidence,
        "mean_latency_ms": mean_latency,
        "false_negatives": len(false_negatives),
        "false_positives": len(false_positives),
        "misroutes": len(misroutes),
        "total": total,
        "correct": correct,
    }


# ============================================================
# Save results to JSON
# ============================================================

def save_results(results: List[EvalResult], summary: dict, output_path: str):
    """Save detailed results + summary to JSON."""
    data = {
        "timestamp": datetime.now().isoformat(),
        "summary": summary,
        "results": [asdict(r) for r in results],
    }
    Path(output_path).write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n  Results saved to: {output_path}")


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="KPI Resolver Evaluation")
    parser.add_argument("--source", choices=["registry", "production", "negative"],
                        help="Filter by test source")
    parser.add_argument("--category", choices=["bot", "inventory", "orders", "station"],
                        help="Filter positive cases by category")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print every test case (not just failures)")
    parser.add_argument("--top-k", type=int, default=5,
                        help="Top-K for recall calculation (default: 5)")
    parser.add_argument("--sample", type=int, default=0,
                        help="Sample N user_queries per KPI from registry (0=all)")
    parser.add_argument("--output", "-o", type=str, default=None,
                        help="Save results to JSON file")
    args = parser.parse_args()

    registry_path = str(ROOT / "data" / "dashboard-data" / "kpi_registry.json")

    print("Loading KPI resolver...")
    from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver
    resolver = DashboardKPIResolver(registry_path=registry_path)

    print("Building evaluation dataset...")
    cases = build_evaluation_dataset(
        registry_path=registry_path,
        source_filter=args.source,
        category_filter=args.category,
        sample_per_kpi=args.sample,
    )
    print(f"  {len(cases)} test cases loaded")

    print("\nRunning evaluation...\n")
    results = run_evaluation(cases, resolver, top_k=args.top_k, verbose=args.verbose)

    summary = print_report(results, cases)

    if args.output:
        save_results(results, summary, args.output)
    else:
        # Default output path
        out = str(ROOT / "evaluation" / "kpi_evaluation_results.json")
        save_results(results, summary, out)


if __name__ == "__main__":
    main()
