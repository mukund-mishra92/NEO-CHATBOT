import json

with open(r'c:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\dashboard-data\kpi_registry.json', 'r') as f:
    data = json.load(f)

target_ids = [
    'kpi_050','kpi_086','kpi_098','kpi_087','kpi_099',
    'kpi_088','kpi_100','kpi_089','kpi_090','kpi_096',
    'kpi_022','kpi_024','kpi_012','kpi_074','kpi_075',
    'kpi_043','kpi_044','kpi_002','kpi_021'
]

for kpi in data:
    kid = kpi.get('id', '')
    if kid in target_ids:
        print('=' * 120)
        print(f"KPI_ID: {kid}")
        print(f"NAME: {kpi.get('kpi_name', '')}")
        print(f"CATEGORY: {kpi.get('category', '')}")
        print(f"LOGIC: {kpi.get('logic', '')}")
        print(f"TABLES: {kpi.get('tables_used', '')}")
        print(f"SQL QUERY:")
        print(kpi.get('query', ''))
        print()
