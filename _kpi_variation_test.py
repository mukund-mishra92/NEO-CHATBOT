"""
Comprehensive KPI variation testing.
For each of the 25 verified queries, generates natural variations and tests
whether they match the correct KPI.
"""
import sys, os, json, logging
from pathlib import Path

# Suppress all logging noise
logging.disable(logging.CRITICAL)

# Ensure project root is on path
ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT / "backend"))

from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver

registry_path = str(ROOT / "data" / "dashboard-data" / "kpi_registry.json")
resolver = DashboardKPIResolver(registry_path=registry_path)
# Force keyword-only mode (no OpenAI API calls)
resolver._embeddings_available = False

# ── The 25 verified queries mapped to expected KPI IDs ──
VERIFIED = {
    # Q1: Alarm Type per Bot
    "give me each bot alarm type with count for last three days in frk": "kpi_009",
    # Q2: Home Time per Bot (Hours)
    "Show home time per bot (hours) in Chennai this week": "kpi_011",
    # Q3: Bin Utilisation
    "what is the bin utilization percentage in banglore": "kpi_015",
    # Q4: Volume Utilization
    "what is the volume utilization percentage in faruknagar": "kpi_021",
    # Q5: Weight Utilisation
    "What is the weight utilization percentage in Bangalore today": "kpi_024",
    # Q6: Top 10 PUT SKUs
    "Show the top values for top 10 put skus in Faruknagar this week": "kpi_029",
    # Q7: Total Location Blocked
    "Show total count of blocked locations in frk": "kpi_031",
    # Q8: Total Bin Blocked
    "Show total count of blocked bins in frk today": "kpi_032",
    # Q9: Distinct SKU
    "What is the total distinct sku in Faruknagar": "kpi_033",
    # Q10: Total Quantity
    "What is the total quantity of all inventory in Chennai": "kpi_034",
    # Q11: Reserved to Put
    "How many items are reserved for put operations in Bangalore": "kpi_035",
    # Q13: Reserved to Pick
    "How many items are reserved for pick operations in Faruknagar": "kpi_036",
    # Q14: Location Audit Marked
    "What is the total location audit marked in Faruknagar": "kpi_037",
    # Q15: Bin Audit Marked
    "What is the total bin audit marked in Shakti.?": "kpi_038",
    # Q16: Total Blocked SKUs
    "How many distinct SKUs are blocked in Faruknagar": "kpi_040",
    # Q17: Total Blocked Quantity
    "What is the total quantity of blocked inventory in Shakti.?": "kpi_041",
    # Q18: Bin Segment Usage Distribution
    "Show the detailed view for bin segment usage distribution in Shakti..?": "kpi_042",
    # Q19: SKU Count by Expiry Ageing
    "Show the top values for sku count by expiry ageing (days) in Chennai?": "kpi_043",
    # Q20: SKU Quantity by Expiry Ageing
    "Show the top values for sku quantity by expiry ageing (days) in Bangalore?": "kpi_044",
    # Q21: SKU wise Expiry Ageing
    "Show the detailed view for sku wise expiry ageing in Faruknagar?": "kpi_045",
    # Q22: Bin-wise Volume Utilization (%)
    "What is the volume utilization percentage for each bin in Chennai?": "kpi_046",
    # Q23: SKU-wise Bin Distribution
    "Show SKU-wise bin distribution in blr today": "kpi_047",
    # Q24: OLBP / QPL
    "Can you show me olbp / qpl in Chennai during this week": "kpi_050",
    # Q25: QBP = OLBP x QPL
    "How is QBP performing over time?": "kpi_051",
}

# ── Variations for each query (90%+ semantic similarity) ──
VARIATIONS = {
    "kpi_009": [
        "show alarm type wise count per bot for last 3 days in faruknagar",
        "alarm type breakdown for each bot in frk last 3 days",
        "bot wise alarm type count for past three days in faruknagar",
        "alarm breakdown by type per bot in frk for last three days",
        "each bot's alarm types with count in faruknagar last 3 days",
        "give me alarm type count for each bot in frk last 3 days",
        "alarm type count per bot frk last three days",
        "show alarm type per bot in frk for the past 3 days",
        "alarm types and counts for bots in faruknagar last 3 days",
    ],
    "kpi_011": [
        "home time per bot in hours in chennai this week",
        "show bot wise home time hours in chennai this week",
        "what is the home time for each bot in chennai this week",
        "home hours per bot in chennai this week",
        "bot home time in hours chennai this week",
        "how many hours did each bot stay at home in chennai this week",
        "show home time per bot hours chennai",
        "home time per bot chennai this week",
    ],
    "kpi_015": [
        "bin utilization percentage in bangalore",
        "what is bin utilisation in bangalore",
        "show bin utilization % in blr",
        "bin utilization rate in bangalore",
        "what percentage of bins are utilized in bangalore",
        "bin utilisation percentage bangalore",
        "what is the bin utilisation in banglore",
        "bin usage percentage in bangalore",
        "give me bin utilization percentage for bangalore",
    ],
    "kpi_021": [
        "volume utilization percentage in frk",
        "what is volume utilisation in faruknagar",
        "show volume utilization % in faruknagar",
        "volume utilization rate in faruknagar",
        "what percentage of volume is utilized in faruknagar",
        "volume utilisation faruknagar",
        "volume usage percentage in frk",
        "give me volume utilization percentage for faruknagar",
    ],
    "kpi_024": [
        "weight utilization percentage in bangalore today",
        "what is weight utilisation in bangalore today",
        "show weight utilization % in blr today",
        "weight utilization rate in bangalore today",
        "weight utilisation percentage bangalore today",
        "what percentage of weight capacity is used in bangalore today",
        "weight usage percentage in bangalore today",
        "give me weight utilization percentage for bangalore today",
    ],
    "kpi_029": [
        "top 10 put skus in faruknagar this week",
        "show top 10 put sku in frk this week",
        "top 10 skus by put quantity in faruknagar this week",
        "show top put skus in faruknagar this week",
        "top 10 sku for put operations in frk this week",
        "top put skus faruknagar this week",
        "what are the top 10 put skus in frk this week",
        "give me top 10 put skus this week in faruknagar",
    ],
    "kpi_031": [
        "total blocked locations in frk",
        "how many locations are blocked in faruknagar",
        "blocked location count in frk",
        "show total blocked locations in faruknagar",
        "count of blocked locations in frk",
        "number of blocked locations in faruknagar",
        "total location blocked frk",
        "how many locations blocked in frk",
    ],
    "kpi_032": [
        "total blocked bins in frk today",
        "how many bins are blocked in faruknagar today",
        "blocked bin count in frk today",
        "show total blocked bins in faruknagar today",
        "count of blocked bins in frk today",
        "number of blocked bins in faruknagar today",
        "total bin blocked frk today",
        "how many bins blocked in frk today",
    ],
    "kpi_033": [
        "total distinct sku in faruknagar",
        "how many distinct skus in faruknagar",
        "distinct sku count in frk",
        "show distinct sku count in faruknagar",
        "number of distinct skus in faruknagar",
        "total unique sku in frk",
        "how many unique skus are there in faruknagar",
        "distinct sku faruknagar",
    ],
    "kpi_034": [
        "total quantity of inventory in chennai",
        "what is total inventory quantity in chennai",
        "show total quantity in chennai",
        "total qty of all inventory in chennai",
        "how much total inventory in chennai",
        "what is the total qty in chennai",
        "total inventory quantity chennai",
        "give me total quantity of inventory in chennai",
    ],
    "kpi_035": [
        "items reserved for put in bangalore",
        "how many items reserved for put operations in blr",
        "reserved to put count in bangalore",
        "show reserved for put items in bangalore",
        "reserved to put in bangalore",
        "put reserved items in bangalore",
        "total reserved to put in bangalore",
        "reserved for put in blr",
    ],
    "kpi_036": [
        "items reserved for pick in faruknagar",
        "how many items reserved for pick operations in frk",
        "reserved to pick count in faruknagar",
        "show reserved for pick items in faruknagar",
        "reserved to pick in faruknagar",
        "pick reserved items in faruknagar",
        "total reserved to pick in faruknagar",
        "reserved for pick in frk",
    ],
    "kpi_037": [
        "total location audit marked in faruknagar",
        "how many locations are marked for audit in faruknagar",
        "location audit count in frk",
        "show location audit marked in faruknagar",
        "number of locations marked for audit in faruknagar",
        "location audit marked faruknagar",
        "how many location audits in frk",
        "show total location audit in faruknagar",
    ],
    "kpi_038": [
        "total bin audit marked in shakti",
        "how many bins are marked for audit in shakti",
        "bin audit count in shakti",
        "show bin audit marked in shakti",
        "number of bins marked for audit in shakti",
        "bin audit marked shakti",
        "how many bin audits in shakti",
        "show total bin audit in shakti",
    ],
    "kpi_040": [
        "total blocked skus in faruknagar",
        "how many skus are blocked in faruknagar",
        "blocked sku count in frk",
        "show total blocked skus in faruknagar",
        "number of blocked skus in faruknagar",
        "distinct blocked sku count in frk",
        "how many distinct skus blocked in faruknagar",
        "blocked skus faruknagar",
    ],
    "kpi_041": [
        "total blocked quantity in shakti",
        "what is the blocked inventory quantity in shakti",
        "blocked quantity count in shakti",
        "show total blocked quantity in shakti",
        "total quantity of blocked items in shakti",
        "how much inventory is blocked in shakti",
        "blocked inventory quantity shakti",
        "what is total blocked quantity in shakti",
    ],
    "kpi_042": [
        "bin segment usage distribution in shakti",
        "show bin segment distribution in shakti",
        "show detailed bin segment usage in shakti",
        "bin segment distribution shakti",
        "bin usage by segment distribution in shakti",
        "detailed view bin segment usage shakti",
        "bin segment usage breakdown in shakti",
    ],
    "kpi_043": [
        "sku count by expiry ageing days in chennai",
        "show top sku count by expiry ageing in chennai",
        "sku count by expiry age in chennai",
        "top sku count by expiry days in chennai",
        "sku count expiry ageing days chennai",
        "show sku count by expiry in chennai",
        "expiry ageing sku count in chennai",
        "top values sku count expiry ageing chennai",
    ],
    "kpi_044": [
        "sku quantity by expiry ageing days in bangalore",
        "show top sku quantity by expiry ageing in bangalore",
        "sku quantity by expiry age in bangalore",
        "top sku quantity by expiry days in bangalore",
        "sku quantity expiry ageing days bangalore",
        "show sku quantity by expiry in bangalore",
        "expiry ageing sku quantity in bangalore",
        "top values sku quantity expiry ageing bangalore",
    ],
    "kpi_045": [
        "sku wise expiry ageing in faruknagar",
        "show sku expiry ageing details in faruknagar",
        "sku wise expiry details in frk",
        "detailed sku expiry ageing faruknagar",
        "sku wise expiry ageing breakdown in faruknagar",
        "show sku wise expiry in faruknagar",
        "sku expiry ageing in faruknagar",
        "detailed view sku expiry ageing faruknagar",
    ],
    "kpi_046": [
        "volume utilization percentage for each bin in chennai",
        "bin wise volume utilization in chennai",
        "show bin wise volume utilization percentage in chennai",
        "volume utilization per bin in chennai",
        "bin wise volume utilisation in chennai",
        "what is volume utilization for each bin in chennai",
        "volume utilization % per bin chennai",
        "show bin volume utilization percentage in chennai",
    ],
    "kpi_047": [
        "sku wise bin distribution in bangalore today",
        "show sku bin distribution in blr today",
        "sku wise bin distribution bangalore today",
        "sku bin distribution in bangalore today",
        "show sku wise bin distribution today in blr",
        "sku wise bin distribution blr",
        "bin distribution per sku in bangalore today",
        "sku bin breakup in bangalore today",
    ],
    "kpi_050": [
        "show olbp qpl in chennai this week",
        "olbp and qpl in chennai this week",
        "show me olbp / qpl chennai this week",
        "olbp qpl trend in chennai this week",
        "olbp / qpl in chennai during this week",
        "olbp qpl chennai this week",
        "what is olbp / qpl in chennai this week",
        "show olbp and qpl in chennai this week",
    ],
    "kpi_051": [
        "how is qbp performing over time",
        "show qbp trend over time",
        "qbp performance trend",
        "qbp over time trend",
        "show qbp performance over time",
        "qbp trend",
        "how is qbp doing over time",
        "qbp performance over time",
    ],
}

# ── Negative cases: queries that should NOT match any KPI ──
NEGATIVES = [
    "where is BOT-0001 in frk",
    "what is the IP of BOT-0027",
    "show me the columns in bot_master table",
    "what tables are in the database",
    "what is the battery level of BOT-0003",
    "show me the tower side for BOT-0001",
    "tell me about the schema of task_master_log",
    "which bot is at location X=5 Y=3",
    "what is the status of BOT-0015",
    "list all columns of inventory_master",
    "how many columns does bot_master have",
    "what is the grid position of BOT-0002",
]

# ── Run tests ──
def run_test():
    print("=" * 80)
    print("PART 1: VERIFIED QUERIES (exact matches)")
    print("=" * 80)
    
    verified_pass = 0
    verified_fail = 0
    for query, expected in VERIFIED.items():
        result = resolver.resolve(query, tenant_values=["frk"])
        matched_id = result.kpi_id if result else None
        status = "PASS" if matched_id == expected else "FAIL"
        if status == "FAIL":
            verified_fail += 1
            print(f"  {status}: '{query[:60]}...' => {matched_id} (expected {expected})")
        else:
            verified_pass += 1
    
    print(f"\nVerified: {verified_pass} PASS, {verified_fail} FAIL out of {len(VERIFIED)}")
    
    print("\n" + "=" * 80)
    print("PART 2: VARIATIONS")
    print("=" * 80)
    
    var_pass = 0
    var_fail = 0
    failures = []
    for expected_kpi, variations in VARIATIONS.items():
        for var in variations:
            result = resolver.resolve(var, tenant_values=["frk"])
            matched_id = result.kpi_id if result else None
            if matched_id == expected_kpi:
                var_pass += 1
            else:
                var_fail += 1
                score_info = f"score={result.match_score:.3f}" if result else "no match"
                failures.append((var, expected_kpi, matched_id, score_info))
                print(f"  FAIL: '{var[:65]}' => {matched_id} ({score_info}) expected {expected_kpi}")
    
    print(f"\nVariations: {var_pass} PASS, {var_fail} FAIL out of {var_pass + var_fail}")
    
    print("\n" + "=" * 80)
    print("PART 3: NEGATIVE CASES (should NOT match any KPI)")
    print("=" * 80)
    
    neg_pass = 0
    neg_fail = 0
    for query in NEGATIVES:
        result = resolver.resolve(query, tenant_values=["frk"])
        if result is None:
            neg_pass += 1
        else:
            neg_fail += 1
            print(f"  FAIL: '{query}' => {result.kpi_id} '{result.kpi_name}' (score={result.match_score:.3f}) — should be None")
    
    print(f"\nNegatives: {neg_pass} PASS, {neg_fail} FAIL out of {len(NEGATIVES)}")
    
    # Summary
    total = len(VERIFIED) + var_pass + var_fail + len(NEGATIVES)
    total_pass = verified_pass + var_pass + neg_pass
    total_fail = verified_fail + var_fail + neg_fail
    
    print("\n" + "=" * 80)
    print(f"TOTAL: {total_pass} PASS, {total_fail} FAIL out of {total_pass + total_fail}")
    print("=" * 80)
    
    if failures:
        print("\n── VARIATION FAILURE DETAILS ──")
        for var, expected, got, score in failures:
            print(f"  Query:    '{var}'")
            print(f"  Expected: {expected}")
            print(f"  Got:      {got} ({score})")
            print()
    
    return total_fail

if __name__ == "__main__":
    exit_code = run_test()
    sys.exit(1 if exit_code > 0 else 0)
