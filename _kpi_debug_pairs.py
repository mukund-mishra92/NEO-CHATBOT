import sys, logging
from pathlib import Path
logging.disable(logging.CRITICAL)
ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT / "backend"))
from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver

registry_path = str(ROOT / "data" / "dashboard-data" / "kpi_registry.json")
resolver = DashboardKPIResolver(registry_path=registry_path)
resolver._embeddings_available = False

# Compare confused KPI pairs — show keywords and score breakdown
PAIRS_TO_INSPECT = [
    ("kpi_014", "kpi_042", "bin segment usage distribution in shakti"),
    ("kpi_015", "kpi_046", "bin wise volume utilization in chennai"),
    ("kpi_008", "kpi_009", "alarm type count per bot frk last three days"),
    ("kpi_088", "kpi_051", "show qbp performance over time"),
    ("kpi_027", "kpi_033", "distinct sku count in frk"),
    ("kpi_034", "kpi_041", "total quantity of blocked items in shakti"),
    ("kpi_043", "kpi_044", "show sku quantity by expiry in bangalore"),
]

for kpi_a_id, kpi_b_id, query in PAIRS_TO_INSPECT:
    kpi_a = next((k for k in resolver.kpis if k.id == kpi_a_id), None)
    kpi_b = next((k for k in resolver.kpis if k.id == kpi_b_id), None)
    if not kpi_a or not kpi_b:
        continue
    
    score_a = resolver._score_match(query, kpi_a)
    score_b = resolver._score_match(query, kpi_b)
    
    print(f"\n{'='*70}")
    print(f"Query: '{query}'")
    print(f"  {kpi_a_id} '{kpi_a.kpi_name}' => score={score_a:.3f}")
    print(f"    keywords: {sorted(kpi_a.keywords)}")
    print(f"    user_queries: {kpi_a.user_queries[:3]}")
    print(f"  {kpi_b_id} '{kpi_b.kpi_name}' => score={score_b:.3f}")
    print(f"    keywords: {sorted(kpi_b.keywords)}")
    print(f"    user_queries: {kpi_b.user_queries[:3]}")
