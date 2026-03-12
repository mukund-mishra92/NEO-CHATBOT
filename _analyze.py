import csv, json

tables = {}
with open(r'C:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\database\Table_information.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        name = row['Table_name']
        cols_raw = row['Table_columns(Data type)']
        cols = []
        for part in cols_raw.split('), '):
            part = part.strip()
            if '(' in part:
                cname = part.split('(')[0].strip()
                ctype = part.split('(', 1)[1].rstrip(')')
                cols.append({'name': cname, 'type': ctype})
        tables[name] = {
            'pk': row['Primary_key'],
            'columns': cols,
            'desc': row['Table_description'][:120],
            'category': row.get('Table_category', 'general_table'),
            'col_names': [c['name'] for c in cols]
        }

# KEY: Find the core tables that most other tables connect to
core_ids = ['BIN_ID', 'BOT_ID', 'LOCATION_ID', 'STATION_ID', 'WAVE_ID', 'SKU_ID', 'ARTICLE_ID', 'BATCH_ID', 'TASK_ID', 'ORDER_BIN_ID']
for cid in core_ids:
    homes = [t for t, info in tables.items() if cid in [c.upper() for c in info['col_names']]]
    if homes:
        print(f'{cid} ({len(homes)} tables):')
        for h in sorted(homes):
            is_pk = cid in tables[h]['pk'].upper()
            tag = "[PK]" if is_pk else "    "
            print(f'  {tag} {h}')
        print()

# Build domain classification
print("\n\n=== TABLES BY CATEGORY ===")
by_cat = {}
for t, info in tables.items():
    cat = info['category']
    if cat not in by_cat:
        by_cat[cat] = []
    by_cat[cat].append(t)

for cat in sorted(by_cat.keys()):
    print(f'\n{cat} ({len(by_cat[cat])} tables):')
    for t in sorted(by_cat[cat]):
        print(f'  {t}')

# Build the WAVE_ID linkage specifically
print("\n\n=== WAVE_ID chain ===")
for t, info in tables.items():
    if 'WAVE_ID' in [c.upper() for c in info['col_names']]:
        print(f'  {t}: PK={info["pk"]}')
