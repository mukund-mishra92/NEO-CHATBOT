"""
Golden SQL Evaluation System
============================
Uses the 101 Grafana KPI queries as ground truth to evaluate our SQL generation.
Each KPI has ~6 user_queries mapped to verified SQL — total ~660 golden test cases.

Usage:
    python evaluation/golden_sql_evaluation.py --mode extract    # Build golden dataset
    python evaluation/golden_sql_evaluation.py --mode evaluate   # Run evaluation (requires DB)
    python evaluation/golden_sql_evaluation.py --mode report     # Show latest report
"""

import json
import os
import re
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# Project root
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
KPI_REGISTRY_PATH = DATA_DIR / "dashboard-data" / "kpi_registry.json"
GOLDEN_DATASET_PATH = DATA_DIR / "golden_sql_evaluation.json"
EVALUATION_RESULTS_PATH = DATA_DIR / "golden_sql_evaluation_results.json"


def load_kpi_registry() -> List[dict]:
    """Load the KPI registry with all 101 Grafana-verified queries."""
    with open(KPI_REGISTRY_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, list) else data.get("kpis", data.get("panels", []))


def normalize_sql(sql: str) -> str:
    """Normalize SQL for structural comparison."""
    # Remove Grafana variables
    sql = re.sub(r"\$__timeFilter\([^)]+\)", "1=1", sql)
    sql = re.sub(r"\$__timeFrom\(\)", "'2026-01-01'", sql)
    sql = re.sub(r"\$__timeTo\(\)", "'2026-12-31'", sql)
    sql = re.sub(r"IN\s*\(\$location\)", "IN ('bangalore')", sql)
    sql = re.sub(r"=\s*'\$location'", "= 'bangalore'", sql)
    sql = re.sub(r"\$location", "'bangalore'", sql)
    
    # Normalize whitespace
    sql = re.sub(r"\s+", " ", sql).strip()
    sql = sql.upper()
    return sql


def extract_tables_from_sql(sql: str) -> set:
    """Extract table names from SQL query."""
    normalized = sql.upper()
    tables = set()
    
    # FROM / JOIN patterns
    for match in re.finditer(r"(?:FROM|JOIN)\s+`?(\w+)`?", normalized, re.IGNORECASE):
        table = match.group(1).lower()
        # Filter out aliases and CTEs
        if not table.startswith(("select", "where", "group", "order", "having", "limit", "case", "when")):
            tables.add(table)
    return tables


def extract_columns_from_sql(sql: str) -> set:
    """Extract key column references from SQL query."""
    columns = set()
    # Look for column patterns: table.column or standalone columns in SELECT/WHERE/GROUP BY
    for match in re.finditer(r"(?:\w+\.)?`?([A-Za-z_][A-Za-z0-9_]*)`?", sql):
        col = match.group(1).lower()
        # Filter SQL keywords
        keywords = {"select", "from", "where", "join", "left", "right", "inner", "outer", 
                    "on", "and", "or", "not", "in", "as", "is", "null", "case", "when",
                    "then", "else", "end", "group", "by", "order", "having", "limit",
                    "count", "sum", "avg", "min", "max", "distinct", "round", "ifnull",
                    "coalesce", "nullif", "concat", "cast", "date", "timestamp",
                    "interval", "between", "like", "exists", "union", "all", "with",
                    "recursive", "asc", "desc", "into", "values", "insert", "update",
                    "delete", "create", "drop", "alter", "index", "table", "view",
                    "true", "false", "least", "greatest", "timestampdiff", "datediff",
                    "curdate", "now", "second", "minute", "hour", "day", "week", "month"}
        if col not in keywords and len(col) > 2:
            columns.add(col)
    return columns


def compare_sql_structure(generated_sql: str, golden_sql: str) -> dict:
    """Compare two SQL queries structurally (not exact match).
    
    Returns dict with:
    - table_match: bool - do they use the same tables?
    - column_overlap: float - Jaccard similarity of columns
    - join_pattern_match: bool - similar JOIN structure?
    - aggregation_match: bool - similar aggregation functions?
    - overall_score: float 0-1
    """
    gen_tables = extract_tables_from_sql(generated_sql)
    gold_tables = extract_tables_from_sql(golden_sql)
    
    gen_cols = extract_columns_from_sql(generated_sql)
    gold_cols = extract_columns_from_sql(golden_sql)
    
    # Table match
    table_intersection = gen_tables & gold_tables
    table_union = gen_tables | gold_tables
    table_score = len(table_intersection) / max(len(table_union), 1)
    
    # Column overlap (Jaccard)
    col_intersection = gen_cols & gold_cols
    col_union = gen_cols | gold_cols
    col_score = len(col_intersection) / max(len(col_union), 1)
    
    # Check critical patterns
    gen_upper = generated_sql.upper()
    gold_upper = golden_sql.upper()
    
    # JOIN pattern
    gen_joins = len(re.findall(r"\bJOIN\b", gen_upper))
    gold_joins = len(re.findall(r"\bJOIN\b", gold_upper))
    join_match = gen_joins == gold_joins
    
    # Aggregation functions
    agg_funcs = ["COUNT", "SUM", "AVG", "MIN", "MAX"]
    gen_aggs = {f for f in agg_funcs if f in gen_upper}
    gold_aggs = {f for f in agg_funcs if f in gold_upper}
    agg_match = gen_aggs == gold_aggs
    
    # Scoring weights
    overall = (
        table_score * 0.35 +
        col_score * 0.30 +
        (1.0 if join_match else 0.5) * 0.20 +
        (1.0 if agg_match else 0.5) * 0.15
    )
    
    return {
        "table_score": round(table_score, 3),
        "column_score": round(col_score, 3),
        "join_match": join_match,
        "aggregation_match": agg_match,
        "overall_score": round(overall, 3),
        "tables_generated": sorted(gen_tables),
        "tables_golden": sorted(gold_tables),
        "tables_missing": sorted(gold_tables - gen_tables),
        "tables_extra": sorted(gen_tables - gold_tables),
    }


def extract_golden_dataset():
    """Extract golden evaluation dataset from KPI registry."""
    kpis = load_kpi_registry()
    
    golden_entries = []
    stats = {"total_kpis": 0, "total_queries": 0, "categories": {}}
    
    for kpi in kpis:
        kpi_id = kpi.get("id", "unknown")
        kpi_name = kpi.get("kpi_name", "")
        category = kpi.get("category", "unknown")
        query = kpi.get("query", "")
        tables = kpi.get("tables_used", [])
        user_queries = kpi.get("user_queries", [])
        requires_time = kpi.get("requires_time_range", False)
        logic = kpi.get("logic", "")
        
        if not query or not user_queries:
            continue
        
        stats["total_kpis"] += 1
        stats["categories"][category] = stats["categories"].get(category, 0) + 1
        
        for uq in user_queries:
            golden_entries.append({
                "kpi_id": kpi_id,
                "kpi_name": kpi_name,
                "category": category,
                "user_query": uq,
                "golden_sql": query,
                "tables_expected": tables,
                "requires_time_range": requires_time,
                "logic": logic,
            })
            stats["total_queries"] += 1
    
    dataset = {
        "_description": "Golden evaluation dataset extracted from 101 Grafana KPI queries",
        "_extracted_at": datetime.now().isoformat(),
        "_stats": stats,
        "entries": golden_entries,
    }
    
    with open(GOLDEN_DATASET_PATH, "w", encoding="utf-8") as f:
        json.dump(dataset, f, indent=2, ensure_ascii=False)
    
    print(f"\n{'='*60}")
    print(f"GOLDEN EVALUATION DATASET EXTRACTED")
    print(f"{'='*60}")
    print(f"Total KPIs:   {stats['total_kpis']}")
    print(f"Total queries: {stats['total_queries']}")
    print(f"\nCategories:")
    for cat, count in sorted(stats["categories"].items()):
        print(f"  {cat:15s} — {count} KPIs")
    print(f"\nSaved to: {GOLDEN_DATASET_PATH}")
    print(f"{'='*60}")
    
    return dataset


def check_formula_coverage():
    """Check which KPI categories are covered by our domain formulas."""
    formulas_path = DATA_DIR / "domain_knowledge" / "domain_formulas.json"
    
    if not formulas_path.exists():
        print("Domain formulas not found.")
        return
    
    with open(formulas_path, "r", encoding="utf-8") as f:
        formula_data = json.load(f)
    
    formulas = formula_data.get("formulas", [])
    
    # Collect all formula keywords
    formula_keywords = set()
    formula_tables = set()
    for f in formulas:
        for kw in f.get("applies_to", []):
            formula_keywords.add(kw.lower())
        for t in f.get("tables", []):
            formula_tables.add(t.lower())
    
    kpis = load_kpi_registry()
    
    covered = []
    uncovered = []
    
    for kpi in kpis:
        kpi_id = kpi.get("id", "")
        kpi_name = kpi.get("kpi_name", "")
        user_queries = kpi.get("user_queries", [])
        
        # Check if any user query words match formula keywords
        is_covered = False
        for uq in user_queries:
            uq_lower = uq.lower()
            for kw in formula_keywords:
                if kw in uq_lower:
                    is_covered = True
                    break
            if is_covered:
                break
        
        if is_covered:
            covered.append(f"{kpi_id}: {kpi_name}")
        else:
            uncovered.append(f"{kpi_id}: {kpi_name}")
    
    print(f"\n{'='*60}")
    print("FORMULA COVERAGE ANALYSIS")
    print(f"{'='*60}")
    print(f"Domain formulas: {len(formulas)}")
    print(f"KPIs covered:    {len(covered)}/{len(kpis)}")
    print(f"KPIs uncovered:  {len(uncovered)}/{len(kpis)}")
    
    if uncovered:
        print(f"\nUncovered KPIs (no formula keyword match):")
        for u in uncovered[:20]:
            print(f"  - {u}")
        if len(uncovered) > 20:
            print(f"  ... and {len(uncovered) - 20} more")
    print(f"{'='*60}")


def show_report():
    """Display the latest evaluation results."""
    if EVALUATION_RESULTS_PATH.exists():
        with open(EVALUATION_RESULTS_PATH, "r", encoding="utf-8") as f:
            results = json.load(f)
        
        print(f"\n{'='*60}")
        print(f"LATEST EVALUATION RESULTS")
        print(f"{'='*60}")
        print(json.dumps(results.get("_summary", {}), indent=2))
    else:
        print("No evaluation results found. Run --mode evaluate first.")
    
    # Always show formula coverage
    check_formula_coverage()


def main():
    parser = argparse.ArgumentParser(description="Golden SQL Evaluation System")
    parser.add_argument("--mode", choices=["extract", "evaluate", "report", "coverage"],
                        default="extract", help="Operation mode")
    args = parser.parse_args()
    
    if args.mode == "extract":
        extract_golden_dataset()
    elif args.mode == "report" or args.mode == "coverage":
        show_report()
    elif args.mode == "evaluate":
        print("Evaluation mode requires the SQL assistant to be running.")
        print("Use: python evaluation/golden_sql_evaluation.py --mode extract  (to build dataset first)")
        print("Then integrate with test_production_queries.py for actual evaluation.")


if __name__ == "__main__":
    main()
