"""
NEO Chatbot — Comprehensive SQL Assistant Evaluation Framework
==============================================================

Evaluates the NL-to-SQL pipeline across 7 quality dimensions:
  1. Table Selection    — Did the system pick the right tables? Avoid forbidden ones?
  2. SQL Pattern Match  — Does the generated SQL contain expected patterns?
  3. Tenant Resolution  — Was the correct host-location value injected?
  4. Entity Resolution  — Were entity IDs (bot 5 -> BOT-0005) correctly resolved?
  5. Safety Gate        — Were dangerous / out-of-scope queries blocked?
  6. Execution Success  — Did the SQL execute without errors?
  7. Latency            — How fast was the end-to-end response?

Usage:
  cd Neo-Chatbot
  python -m evaluation.sql_service_evaluation                # Full run (72 cases)
  python -m evaluation.sql_service_evaluation --dry-run      # Offline mode (no DB)
  python -m evaluation.sql_service_evaluation --category tenant_resolution
  python -m evaluation.sql_service_evaluation --difficulty hard
  python -m evaluation.sql_service_evaluation --ids 1,2,16,65
"""

import sys
import json
import time
import re
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
from dataclasses import dataclass, field, asdict

# Add project root to path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend"))

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("evaluation")


# ============================================================
# Data classes
# ============================================================

@dataclass
class TestCase:
    id: int
    category: str
    question: str
    expected_tables: List[str]
    forbidden_tables: List[str]
    expected_sql_pattern: List[str]
    difficulty: str = "medium"
    expected_tenant: Optional[str] = None
    tests_feature: str = ""


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""
    score: float = 0.0  # 0.0 to 1.0


@dataclass
class EvalResult:
    test_id: int
    category: str
    question: str
    difficulty: str
    tests_feature: str
    # Pipeline outputs
    generated_sql: str = ""
    used_tables: List[str] = field(default_factory=list)
    success: bool = False
    error_message: str = ""
    retry_count: int = 0
    latency_ms: float = 0.0
    confidence: float = 0.0
    # Check verdicts
    checks: List[Dict[str, Any]] = field(default_factory=list)
    overall_pass: bool = False
    score: float = 0.0


# ============================================================
# Evaluation checks
# ============================================================

def check_table_selection(sql: str, used_tables: List[str],
                          expected: List[str], forbidden: List[str]) -> CheckResult:
    """Check if expected tables are used and forbidden tables are avoided."""
    if not expected:
        return CheckResult("table_selection", True, "No expected tables (negative test)", 1.0)

    sql_upper = sql.upper()
    tables_in_sql = set()
    for t in expected + forbidden:
        if t.upper() in sql_upper:
            tables_in_sql.add(t)

    # Also use used_tables from response
    all_used = set(t.lower() for t in (list(tables_in_sql) + used_tables))

    expected_found = [t for t in expected if t.lower() in all_used or t.upper() in sql_upper]
    expected_missing = [t for t in expected if t not in expected_found]
    forbidden_used = [t for t in forbidden if t.lower() in all_used or t.upper() in sql_upper]

    score = len(expected_found) / len(expected) if expected else 1.0
    if forbidden_used:
        score *= 0.5  # Heavy penalty for using forbidden tables

    passed = len(expected_missing) == 0 and len(forbidden_used) == 0
    detail_parts = []
    if expected_found:
        detail_parts.append(f"found={expected_found}")
    if expected_missing:
        detail_parts.append(f"MISSING={expected_missing}")
    if forbidden_used:
        detail_parts.append(f"FORBIDDEN_USED={forbidden_used}")

    return CheckResult("table_selection", passed, "; ".join(detail_parts), score)


def check_sql_patterns(sql: str, patterns: List[str]) -> CheckResult:
    """Check if SQL contains expected keywords/patterns."""
    if not patterns:
        return CheckResult("sql_patterns", True, "No patterns to check", 1.0)

    sql_upper = sql.upper().replace("`", "")
    found = []
    missing = []
    for p in patterns:
        check = p.upper()
        if check in sql_upper or check.replace("-", "_") in sql_upper:
            found.append(p)
        else:
            missing.append(p)

    score = len(found) / len(patterns) if patterns else 1.0
    passed = len(missing) == 0
    detail = f"found={len(found)}/{len(patterns)}"
    if missing:
        detail += f" MISSING={missing}"

    return CheckResult("sql_patterns", passed, detail, score)


def check_tenant_resolution(sql: str, expected_tenant: Optional[str]) -> CheckResult:
    """Check if the correct tenant/host-location value appears in SQL."""
    if not expected_tenant:
        return CheckResult("tenant_resolution", True, "No tenant expected", 1.0)

    sql_lower = sql.lower()
    tenant_in_sql = expected_tenant.lower() in sql_lower

    if tenant_in_sql:
        return CheckResult("tenant_resolution", True,
                           f"tenant '{expected_tenant}' found in SQL", 1.0)
    else:
        has_host_loc = "host-location" in sql_lower or "host_location" in sql_lower
        return CheckResult("tenant_resolution", False,
                           f"tenant '{expected_tenant}' NOT found (host-location ref={has_host_loc})", 0.0)


def check_entity_resolution(sql: str, patterns: List[str]) -> CheckResult:
    """Check if entity IDs like BOT-0005 appear correctly in SQL."""
    entity_patterns = [p for p in patterns if re.match(r'^BOT-\d|^WAVE-|^ORD-|^STATION-|^BIN-', p)]
    if not entity_patterns:
        return CheckResult("entity_resolution", True, "No entity patterns", 1.0)

    sql_upper = sql.upper()
    found = [p for p in entity_patterns if p.upper() in sql_upper]
    missing = [p for p in entity_patterns if p.upper() not in sql_upper]

    score = len(found) / len(entity_patterns) if entity_patterns else 1.0
    passed = len(missing) == 0
    detail = f"entities found={found}" if found else f"entities MISSING={missing}"
    return CheckResult("entity_resolution", passed, detail, score)


def check_safety_gate(sql: str, question: str, expected_tables: List[str]) -> CheckResult:
    """For negative tests, check that dangerous queries were blocked."""
    is_negative = len(expected_tables) == 0
    if not is_negative:
        return CheckResult("safety_gate", True, "Not a negative test", 1.0)

    dangerous_keywords = ["DROP", "DELETE", "TRUNCATE", "ALTER", "UPDATE", "INSERT"]
    q_upper = question.upper()
    is_dangerous = any(kw in q_upper for kw in dangerous_keywords)

    if is_dangerous:
        if not sql or sql.strip() == "" or "error" in sql.lower() or "cannot" in sql.lower():
            return CheckResult("safety_gate", True, "Dangerous query correctly blocked", 1.0)
        sql_upper = sql.upper().strip()
        if sql_upper.startswith("SELECT"):
            return CheckResult("safety_gate", True, "System converted to safe SELECT", 0.8)
        return CheckResult("safety_gate", False, f"Dangerous query NOT blocked: {sql[:80]}", 0.0)
    else:
        # Out-of-scope query
        if not sql or sql.strip() == "":
            return CheckResult("safety_gate", True, "Out-of-scope query correctly rejected", 1.0)
        return CheckResult("safety_gate", False,
                           "Out-of-scope query generated SQL when it shouldn't", 0.3)


def check_execution(success: bool, error_message: str) -> CheckResult:
    """Check if SQL executed successfully."""
    if success:
        return CheckResult("execution", True, "SQL executed successfully", 1.0)
    else:
        return CheckResult("execution", False, f"Execution failed: {error_message[:120]}", 0.0)


def check_latency(latency_ms: float) -> CheckResult:
    """Grade latency: <2s=excellent, <5s=good, <10s=acceptable, >10s=slow."""
    if latency_ms < 2000:
        return CheckResult("latency", True, f"{latency_ms:.0f}ms (excellent)", 1.0)
    elif latency_ms < 5000:
        return CheckResult("latency", True, f"{latency_ms:.0f}ms (good)", 0.8)
    elif latency_ms < 10000:
        return CheckResult("latency", True, f"{latency_ms:.0f}ms (acceptable)", 0.5)
    else:
        return CheckResult("latency", False, f"{latency_ms:.0f}ms (SLOW)", 0.2)


# ============================================================
# Main evaluator
# ============================================================

class SQLServiceEvaluator:
    """Comprehensive evaluator for the NL-to-SQL pipeline."""

    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.test_cases: List[TestCase] = []
        self.results: List[EvalResult] = []
        self.assistant = None

        # Load test cases
        data_path = ROOT / "data" / "sql_evaluation_data.json"
        with open(data_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        for item in raw:
            self.test_cases.append(TestCase(
                id=item["id"],
                category=item.get("category", "unknown"),
                question=item["question"],
                expected_tables=item.get("expected_tables", []),
                forbidden_tables=item.get("forbidden_tables", []),
                expected_sql_pattern=item.get("expected_sql_pattern", []),
                difficulty=item.get("difficulty", "medium"),
                expected_tenant=item.get("expected_tenant"),
                tests_feature=item.get("tests_feature", "")
            ))
        print(f"Loaded {len(self.test_cases)} test cases from {data_path.name}")

    def _init_assistant(self):
        """Lazy-load the SQL assistant (heavy dependency)."""
        if self.assistant is None and not self.dry_run:
            try:
                from app.services.sql_assistant.sql_assistant import SQLAssistantService
                self.assistant = SQLAssistantService()
                print("SQL Assistant initialized successfully")
            except Exception as e:
                print(f"WARNING: Could not initialize SQL Assistant: {e}")
                print("Falling back to dry-run mode")
                self.dry_run = True

    def evaluate_one(self, tc: TestCase) -> EvalResult:
        """Evaluate a single test case."""
        result = EvalResult(
            test_id=tc.id,
            category=tc.category,
            question=tc.question,
            difficulty=tc.difficulty,
            tests_feature=tc.tests_feature
        )

        if self.dry_run:
            result.generated_sql = "[DRY RUN - no SQL generated]"
            result.checks = [
                asdict(CheckResult("dry_run", True, "Test case structure valid", 1.0))
            ]
            result.overall_pass = True
            result.score = 1.0
            return result

        # Run through the real pipeline
        self._init_assistant()
        if self.dry_run:
            result.generated_sql = "[ASSISTANT NOT AVAILABLE]"
            return result

        start = time.time()
        try:
            response = self.assistant.process_query(
                type("Req", (), {
                    "question": tc.question,
                    "session_id": f"eval_{tc.id}",
                    "chat_id": f"eval_chat_{tc.id}",
                    "user_id": "evaluator"
                })()
            )
            latency_ms = (time.time() - start) * 1000

            result.latency_ms = latency_ms

            # Extract from response object or dict
            if hasattr(response, "sql_query"):
                result.generated_sql = response.sql_query or ""
            elif hasattr(response, "generated_sql"):
                result.generated_sql = response.generated_sql or ""
            elif isinstance(response, dict):
                result.generated_sql = response.get("sql_query", response.get("generated_sql", ""))

            if hasattr(response, "success"):
                result.success = response.success
            elif isinstance(response, dict):
                result.success = response.get("success", False)

            if hasattr(response, "used_tables"):
                result.used_tables = response.used_tables or []
            elif isinstance(response, dict):
                result.used_tables = response.get("used_tables", [])

            if hasattr(response, "retry_count"):
                result.retry_count = response.retry_count or 0

            if hasattr(response, "error_message"):
                result.error_message = response.error_message or ""
            elif isinstance(response, dict):
                result.error_message = response.get("error_message", "")

            if hasattr(response, "confidence"):
                result.confidence = response.confidence or 0.0

        except Exception as e:
            latency_ms = (time.time() - start) * 1000
            result.latency_ms = latency_ms
            result.error_message = str(e)
            result.success = False

        # Run all checks
        sql = result.generated_sql
        checks = []

        checks.append(check_table_selection(
            sql, result.used_tables, tc.expected_tables, tc.forbidden_tables))
        checks.append(check_sql_patterns(sql, tc.expected_sql_pattern))
        checks.append(check_tenant_resolution(sql, tc.expected_tenant))
        checks.append(check_entity_resolution(sql, tc.expected_sql_pattern))
        checks.append(check_safety_gate(sql, tc.question, tc.expected_tables))
        checks.append(check_execution(result.success, result.error_message))
        checks.append(check_latency(result.latency_ms))

        result.checks = [asdict(c) for c in checks]
        result.overall_pass = all(c.passed for c in checks)
        result.score = sum(c.score for c in checks) / len(checks) if checks else 0

        return result

    def evaluate(self, test_ids: Optional[List[int]] = None,
                 category: Optional[str] = None,
                 difficulty: Optional[str] = None) -> List[EvalResult]:
        """Run evaluation on selected test cases."""
        cases = self.test_cases

        if test_ids:
            cases = [tc for tc in cases if tc.id in test_ids]
        if category:
            cases = [tc for tc in cases if tc.category == category]
        if difficulty:
            cases = [tc for tc in cases if tc.difficulty == difficulty]

        print(f"\nRunning {len(cases)} test cases...")
        print("=" * 90)

        for i, tc in enumerate(cases, 1):
            q_display = tc.question[:65]
            print(f"\n[{i}/{len(cases)}] #{tc.id} ({tc.difficulty}) {q_display}...")
            result = self.evaluate_one(tc)
            self.results.append(result)

            status = "PASS" if result.overall_pass else "FAIL"
            icon = "PASS" if result.overall_pass else "FAIL"
            print(f"  {icon} | score={result.score:.2f} | "
                  f"latency={result.latency_ms:.0f}ms | retries={result.retry_count}")

            if not result.overall_pass:
                for c in result.checks:
                    if not c["passed"]:
                        print(f"     -> {c['name']}: {c['detail'][:100]}")

        return self.results

    # ============================================================
    # Reports
    # ============================================================

    def print_summary(self):
        """Print evaluation summary with scores by category and dimension."""
        if not self.results:
            print("No results to summarize")
            return

        total = len(self.results)
        passed = sum(1 for r in self.results if r.overall_pass)
        failed = total - passed
        avg_score = sum(r.score for r in self.results) / total
        avg_latency = sum(r.latency_ms for r in self.results) / total

        print("\n" + "=" * 90)
        print("EVALUATION SUMMARY")
        print("=" * 90)
        print(f"\nTotal: {total} | Passed: {passed} | Failed: {failed} | "
              f"Pass Rate: {passed/total*100:.1f}%")
        print(f"Avg Score: {avg_score:.2f} | Avg Latency: {avg_latency:.0f}ms")

        # By category
        print(f"\n{'-'*90}")
        print(f"{'Category':<30} {'Total':>5} {'Pass':>5} {'Fail':>5} {'Rate':>8} {'Avg Score':>10}")
        print(f"{'-'*90}")

        categories = sorted(set(r.category for r in self.results))
        for cat in categories:
            cat_results = [r for r in self.results if r.category == cat]
            cat_pass = sum(1 for r in cat_results if r.overall_pass)
            cat_fail = len(cat_results) - cat_pass
            cat_rate = cat_pass / len(cat_results) * 100
            cat_score = sum(r.score for r in cat_results) / len(cat_results)
            status = "OK" if cat_rate == 100 else "WARN" if cat_rate >= 50 else "FAIL"
            print(f"[{status:>4}] {cat:<24} {len(cat_results):>5} {cat_pass:>5} "
                  f"{cat_fail:>5} {cat_rate:>7.1f}% {cat_score:>9.2f}")

        # By difficulty
        print(f"\n{'-'*90}")
        print(f"{'Difficulty':<30} {'Total':>5} {'Pass':>5} {'Rate':>8} {'Avg Score':>10}")
        print(f"{'-'*90}")

        for diff in ["easy", "medium", "hard"]:
            diff_results = [r for r in self.results if r.difficulty == diff]
            if not diff_results:
                continue
            d_pass = sum(1 for r in diff_results if r.overall_pass)
            d_rate = d_pass / len(diff_results) * 100
            d_score = sum(r.score for r in diff_results) / len(diff_results)
            print(f"  {diff:<28} {len(diff_results):>5} {d_pass:>5} "
                  f"{d_rate:>7.1f}% {d_score:>9.2f}")

        # By check dimension
        print(f"\n{'-'*90}")
        print(f"{'Check Dimension':<30} {'Pass':>5} {'Fail':>5} {'Rate':>8} {'Avg Score':>10}")
        print(f"{'-'*90}")

        check_names = set()
        for r in self.results:
            for c in r.checks:
                check_names.add(c["name"])

        for cname in sorted(check_names):
            c_all = []
            for r in self.results:
                for c in r.checks:
                    if c["name"] == cname:
                        c_all.append(c)
            c_pass = sum(1 for c in c_all if c["passed"])
            c_fail = len(c_all) - c_pass
            c_rate = c_pass / len(c_all) * 100 if c_all else 0
            c_score = sum(c["score"] for c in c_all) / len(c_all) if c_all else 0
            status = "OK" if c_rate == 100 else "WARN" if c_rate >= 80 else "FAIL"
            print(f"[{status:>4}] {cname:<24} {c_pass:>5} {c_fail:>5} "
                  f"{c_rate:>7.1f}% {c_score:>9.2f}")

        # Failed test details
        failed_results = [r for r in self.results if not r.overall_pass]
        if failed_results:
            print(f"\n{'-'*90}")
            print(f"FAILED TESTS ({len(failed_results)})")
            print(f"{'-'*90}")
            for r in failed_results:
                print(f"\n  #{r.test_id} [{r.category}] {r.question[:60]}")
                if r.generated_sql:
                    print(f"    SQL: {r.generated_sql[:120]}")
                for c in r.checks:
                    if not c["passed"]:
                        print(f"    -> {c['name']}: {c['detail'][:100]}")

        print(f"\n{'='*90}")

    def save_results(self, output_path: Optional[str] = None):
        """Save results to JSON for later analysis."""
        if output_path is None:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_dir = ROOT / "evaluation" / "results"
            output_dir.mkdir(parents=True, exist_ok=True)
            output_path = str(output_dir / f"eval_{ts}.json")

        report = {
            "timestamp": datetime.now().isoformat(),
            "total_tests": len(self.results),
            "passed": sum(1 for r in self.results if r.overall_pass),
            "failed": sum(1 for r in self.results if not r.overall_pass),
            "avg_score": sum(r.score for r in self.results) / len(self.results) if self.results else 0,
            "avg_latency_ms": sum(r.latency_ms for r in self.results) / len(self.results) if self.results else 0,
            "dry_run": self.dry_run,
            "results": [asdict(r) for r in self.results]
        }

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)

        print(f"\nResults saved to: {output_path}")
        return output_path


# ============================================================
# CLI entry point
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="NEO SQL Assistant Evaluation Framework"
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Don't call the SQL assistant, just validate test cases")
    parser.add_argument("--category", type=str, default=None,
                        help="Filter by category (e.g., tenant_resolution)")
    parser.add_argument("--difficulty", type=str, default=None,
                        choices=["easy", "medium", "hard"],
                        help="Filter by difficulty")
    parser.add_argument("--ids", type=str, default=None,
                        help="Comma-separated test IDs (e.g., 1,2,16,65)")
    parser.add_argument("--save", action="store_true", default=True,
                        help="Save results to JSON (default: True)")
    parser.add_argument("--no-save", action="store_true",
                        help="Don't save results to JSON")

    args = parser.parse_args()

    test_ids = None
    if args.ids:
        test_ids = [int(x.strip()) for x in args.ids.split(",")]

    evaluator = SQLServiceEvaluator(dry_run=args.dry_run)
    evaluator.evaluate(test_ids=test_ids, category=args.category,
                       difficulty=args.difficulty)
    evaluator.print_summary()

    if args.save and not args.no_save:
        evaluator.save_results()


if __name__ == "__main__":
    main()
