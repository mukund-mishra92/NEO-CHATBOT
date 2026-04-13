"""
Intent Classifier Evaluation Script
Tests the intent classifier against historical data from chatbot_chat_history table.
Usage:
    python -m evaluation.intent_classifier_evaluation
    OR from project root:
    python evaluation/intent_classifier_evaluation.py
"""

import sys
import os
import json
import time
import logging
from pathlib import Path
from collections import defaultdict

# Ensure project root is on the path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "backend"))

# Load .env
from dotenv import load_dotenv
load_dotenv(project_root / ".env")

from backend.app.services.intent_classifier import IntentClassifier

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


def get_db_connection():
    """Create a database connection using environment config."""
    import pymysql
    return pymysql.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", "root"),
        database=os.getenv("DB_NAME", "neo"),
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=10
    )


def fetch_historical_data(limit: int = 500) -> list:
    """
    Fetch user_query and chatbot_type from chatbot_chat_history table.
    Only keeps the three target types: knowledge_base, sql_assistant, semi_auto_diagnostic.
    """
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            query = """
                SELECT user_query, chatbot_type 
                FROM chatbot_chat_history 
                WHERE chatbot_type IN ('knowledge_base', 'sql_assistant', 'semi_auto_diagnostic')
                  AND user_query IS NOT NULL 
                  AND TRIM(user_query) != ''
                  AND LENGTH(user_query) > 3
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (limit,))
            rows = cursor.fetchall()
            logger.info(f"📊 Fetched {len(rows)} rows from chatbot_chat_history")
            return rows
    finally:
        conn.close()


def fetch_type_distribution() -> dict:
    """Get the distribution of chatbot_types in the history table."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT chatbot_type, COUNT(*) as cnt 
                FROM chatbot_chat_history 
                WHERE user_query IS NOT NULL AND TRIM(user_query) != ''
                GROUP BY chatbot_type
                ORDER BY cnt DESC
            """)
            return {row["chatbot_type"]: row["cnt"] for row in cursor.fetchall()}
    finally:
        conn.close()


def evaluate_classifier(data: list, classifier: IntentClassifier) -> dict:
    """
    Run the classifier on historical data and measure accuracy.
    
    Returns detailed results with metrics.
    """
    results = {
        "total": len(data),
        "correct": 0,
        "incorrect": 0,
        "by_type": defaultdict(lambda: {"total": 0, "correct": 0, "incorrect": 0}),
        "by_method": defaultdict(lambda: {"total": 0, "correct": 0}),
        "confusion_matrix": defaultdict(lambda: defaultdict(int)),
        "errors": [],  # Sample of incorrect predictions
        "timing": {"total_ms": 0, "heuristic_ms": 0, "llm_ms": 0}
    }
    
    for i, row in enumerate(data):
        user_query = row["user_query"]
        expected = row["chatbot_type"]
        
        start = time.time()
        prediction = classifier.classify(user_query)
        elapsed_ms = (time.time() - start) * 1000
        
        predicted_intent = prediction["intent"]
        method = prediction["method"]
        
        is_correct = predicted_intent == expected
        
        # Update metrics
        results["by_type"][expected]["total"] += 1
        results["by_method"][method]["total"] += 1
        results["confusion_matrix"][expected][predicted_intent] += 1
        results["timing"]["total_ms"] += elapsed_ms
        
        if method == "heuristic":
            results["timing"]["heuristic_ms"] += elapsed_ms
        else:
            results["timing"]["llm_ms"] += elapsed_ms
        
        if is_correct:
            results["correct"] += 1
            results["by_type"][expected]["correct"] += 1
            results["by_method"][method]["correct"] += 1
        else:
            results["incorrect"] += 1
            results["by_type"][expected]["incorrect"] += 1
            # Store sample errors (up to 50)
            if len(results["errors"]) < 50:
                results["errors"].append({
                    "query": user_query[:150],
                    "expected": expected,
                    "predicted": predicted_intent,
                    "confidence": prediction["confidence"],
                    "method": method,
                    "reasoning": prediction["reasoning"]
                })
        
        # Progress log every 50 items
        if (i + 1) % 50 == 0:
            acc = results["correct"] / (i + 1) * 100
            logger.info(f"  Progress: {i+1}/{len(data)} ({acc:.1f}% accuracy so far)")
    
    return results


def print_report(results: dict, distribution: dict):
    """Print a formatted evaluation report."""
    total = results["total"]
    if total == 0:
        print("\n⚠️  No data to evaluate!")
        return
    
    accuracy = results["correct"] / total * 100
    
    print("\n" + "=" * 70)
    print("  INTENT CLASSIFIER EVALUATION REPORT")
    print("=" * 70)
    
    # Overall distribution in DB
    print("\n📊 Historical Data Distribution:")
    for t, count in distribution.items():
        print(f"   {t:30s} → {count} queries")
    
    # Overall accuracy
    print(f"\n🎯 Overall Accuracy: {results['correct']}/{total} = {accuracy:.1f}%")
    print(f"   Correct: {results['correct']}  |  Incorrect: {results['incorrect']}")
    
    # Per-type accuracy
    print("\n📋 Accuracy by Type:")
    for type_name, stats in sorted(results["by_type"].items()):
        type_total = stats["total"]
        type_correct = stats["correct"]
        type_acc = (type_correct / type_total * 100) if type_total > 0 else 0
        print(f"   {type_name:30s} → {type_correct}/{type_total} = {type_acc:.1f}%")
    
    # Per-method stats
    print("\n⚙️  Classification Method Distribution:")
    for method, stats in sorted(results["by_method"].items()):
        m_total = stats["total"]
        m_correct = stats["correct"]
        m_acc = (m_correct / m_total * 100) if m_total > 0 else 0
        print(f"   {method:20s} → {m_total} queries ({m_acc:.1f}% accuracy)")
    
    # Confusion matrix
    all_types = sorted(set(
        list(results["confusion_matrix"].keys()) +
        [t for row in results["confusion_matrix"].values() for t in row.keys()]
    ))
    
    print("\n🔢 Confusion Matrix (rows=expected, cols=predicted):")
    header = f"   {'':30s}" + "".join(f"{t[:12]:>14s}" for t in all_types)
    print(header)
    for expected in all_types:
        row_data = results["confusion_matrix"].get(expected, {})
        vals = "".join(f"{row_data.get(pred, 0):>14d}" for pred in all_types)
        print(f"   {expected:30s}{vals}")
    
    # Timing
    print("\n⏱️  Timing:")
    avg_total = results["timing"]["total_ms"] / total if total > 0 else 0
    print(f"   Average per query: {avg_total:.1f}ms")
    print(f"   Total time: {results['timing']['total_ms']/1000:.1f}s")
    
    # Sample errors
    if results["errors"]:
        print(f"\n❌ Sample Misclassifications ({len(results['errors'])} shown):")
        for i, err in enumerate(results["errors"][:20], 1):
            print(f"\n   {i}. Query: \"{err['query']}\"")
            print(f"      Expected: {err['expected']}  →  Predicted: {err['predicted']} "
                  f"(conf={err['confidence']:.2f}, method={err['method']})")
            print(f"      Reason: {err['reasoning']}")
    
    print("\n" + "=" * 70)
    
    return accuracy


def save_results(results: dict, output_path: str):
    """Save evaluation results to JSON."""
    # Convert defaultdicts to regular dicts for JSON serialization
    serializable = {
        "total": results["total"],
        "correct": results["correct"],
        "incorrect": results["incorrect"],
        "accuracy_pct": round(results["correct"] / results["total"] * 100, 2) if results["total"] > 0 else 0,
        "by_type": {k: dict(v) for k, v in results["by_type"].items()},
        "by_method": {k: dict(v) for k, v in results["by_method"].items()},
        "confusion_matrix": {k: dict(v) for k, v in results["confusion_matrix"].items()},
        "errors": results["errors"],
        "timing": results["timing"]
    }
    
    with open(output_path, "w") as f:
        json.dump(serializable, f, indent=2)
    logger.info(f"💾 Results saved to {output_path}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Evaluate intent classifier against chatbot_chat_history")
    parser.add_argument("--limit", type=int, default=500, help="Max rows to evaluate (default: 500)")
    parser.add_argument("--output", type=str, default=None, help="Output JSON file path")
    args = parser.parse_args()
    
    print("🚀 Starting Intent Classifier Evaluation...")
    
    # 1. Check data distribution
    print("\n📊 Checking historical data distribution...")
    distribution = fetch_type_distribution()
    for t, count in distribution.items():
        print(f"   {t}: {count} queries")
    
    # 2. Fetch test data
    print(f"\n📥 Fetching up to {args.limit} queries for evaluation...")
    data = fetch_historical_data(limit=args.limit)
    
    if not data:
        print("⚠️  No historical data found! Make sure chatbot_chat_history table has data.")
        return
    
    # 3. Initialize classifier
    print("\n🔧 Initializing intent classifier...")
    classifier = IntentClassifier()
    
    # 4. Run evaluation
    print(f"\n🏃 Evaluating {len(data)} queries...")
    results = evaluate_classifier(data, classifier)
    
    # 5. Print report
    accuracy = print_report(results, distribution)
    
    # 6. Save results
    output_path = args.output or str(project_root / "evaluation" / "intent_classifier_results.json")
    save_results(results, output_path)
    
    print(f"\n✅ Evaluation complete! Accuracy: {accuracy:.1f}%")


if __name__ == "__main__":
    main()
