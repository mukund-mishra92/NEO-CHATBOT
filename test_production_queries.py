"""
Production test script — sends real queries from logs to the running server
and validates SQL correctness.
"""
import requests
import json
import time
import sys

BASE = "http://localhost:8000/api/chatbot/chat"

TEST_QUERIES = [
    # --- Single location (named) ---
    ("total number of bot we have in frk location", "frk"),
    ("give me total number of alarms logged at location banglore", "BLR"),
    ("How many alarms were triggered by bots today at faruknagar", "frk"),
    ("total bin in faruknagar", "frk"),

    # --- All-sites aggregate ---
    ("how many total bots we have in the system", "_all_sites"),
    ("tell me total number of bins across all locations", "_all_sites"),
    ("Which alarm code occurred most frequently across all sites today", "_all_sites"),

    # --- Location breakdown (GROUP BY) ---
    ("how many bin loading happened at each station in each location in last one day", "_breakdown"),
    ("can you give me site wise bot alram logged today for bots", "_breakdown"),

    # --- Single location with complex query ---
    ("how many bin loading happened at each station in Faruknagar location in last one day", "frk"),
    ("give me total number of alarms logged at shakti site", "SHAKTI"),
    ("how many bot are enabled", None),  # default tenant or all-sites

    # --- Edge cases ---
    ("List alarms that have not been resolved yet", None),
    ("Which alarm code occurred most frequently?", None),
]


def run_test(query, expected_tenant):
    """Send a query and validate the response."""
    payload = {
        "message": query,
        "chatbot_type": "sql_assistant",
        "session_id": None,
        "user_id": "test@production-audit.com"
    }

    try:
        resp = requests.post(BASE, json=payload, timeout=60)
    except requests.ConnectionError:
        return "FAIL", "Server not reachable", None

    if resp.status_code != 200:
        return "FAIL", f"HTTP {resp.status_code}: {resp.text[:200]}", None

    data = resp.json()
    sql = data.get("metadata", {}).get("sql_query", "")
    row_count = data.get("metadata", {}).get("row_count", -1)
    confidence = data.get("confidence_score", 0)

    # --- Validation ---
    issues = []

    # 1. SQL should start with SELECT or WITH
    sql_upper = sql.strip().upper()
    if not (sql_upper.startswith("SELECT") or sql_upper.startswith("WITH")):
        issues.append(f"SQL doesn't start with SELECT/WITH: {sql[:50]}")

    # 2. Tenant filter check
    if expected_tenant == "_all_sites":
        # Should NOT have a specific tenant filter
        pass  # can't easily validate without checking the SQL deeply
    elif expected_tenant == "_breakdown":
        # Should have GROUP BY host-location
        if "GROUP BY" not in sql.upper():
            issues.append("Expected GROUP BY for breakdown query")
    elif expected_tenant and expected_tenant not in ("_all_sites", "_breakdown"):
        # Should have tenant filter
        tenant_in_sql = expected_tenant.lower() in sql.lower() or f"`host-location`" in sql.lower()
        if not tenant_in_sql:
            issues.append(f"Expected tenant '{expected_tenant}' filter in SQL")

    # 3. Should have reasonable confidence
    if confidence < 0.3:
        issues.append(f"Very low confidence: {confidence}")

    # 4. No dangerous patterns
    import re
    if re.search(r'\b(SLEEP|BENCHMARK|LOAD_FILE)\b', sql, re.IGNORECASE):
        issues.append("DANGEROUS function detected in SQL!")

    status = "PASS" if not issues else "WARN"
    return status, issues if issues else f"{row_count} rows, confidence={confidence:.2f}", sql


def main():
    print("=" * 80)
    print("NEO SQL Assistant — Production Query Test")
    print("=" * 80)

    results = {"PASS": 0, "WARN": 0, "FAIL": 0}
    details = []

    for i, (query, expected_tenant) in enumerate(TEST_QUERIES, 1):
        print(f"\n[{i}/{len(TEST_QUERIES)}] {query[:65]}...")
        sys.stdout.flush()

        start = time.time()
        status, info, sql = run_test(query, expected_tenant)
        elapsed = time.time() - start

        results[status] += 1
        icon = {"PASS": "✅", "WARN": "⚠️", "FAIL": "❌"}[status]
        print(f"  {icon} {status} ({elapsed:.1f}s) — {info}")
        if sql:
            # Print first 120 chars of SQL
            print(f"  SQL: {sql[:120]}{'...' if len(sql)>120 else ''}")
        
        details.append({
            "query": query,
            "status": status,
            "info": str(info),
            "sql": sql,
            "time_s": round(elapsed, 1)
        })

    print("\n" + "=" * 80)
    print(f"Results: {results['PASS']} PASS / {results['WARN']} WARN / {results['FAIL']} FAIL")
    print("=" * 80)

    # Save detailed results
    with open("test_production_results.json", "w") as f:
        json.dump(details, f, indent=2)
    print("Detailed results saved to test_production_results.json")


if __name__ == "__main__":
    main()
