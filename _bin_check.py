import json

with open("data/dashboard-data/kpi_registry.json") as f:
    reg = json.load(f)

print(f"Total KPIs: {len(reg)}")
for k in reg:
    kid = k["id"]
    name = k["kpi_name"]
    uq = k.get("user_queries", [])
    uq_str = " | ".join(uq[:2]) if uq else "NO QUERIES"
    print(f"{kid:10s}  {name[:55]:55s}  {uq_str[:100]}")
