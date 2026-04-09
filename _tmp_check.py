"""Show kpi_079 and kpi_065 details."""
import json
d = json.load(open('data/dashboard-data/kpi_registry.json'))
for k in d:
    if k['id'] in ('kpi_079', 'kpi_065'):
        print(json.dumps(k, indent=2))
        print()
