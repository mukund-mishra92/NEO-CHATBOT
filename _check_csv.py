import csv, json

# Check Table_information.csv
with open("data/database/Table_information.csv", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    
print("CSV COLUMNS:", list(rows[0].keys()))
print(f"TOTAL ROWS: {len(rows)}")
print()

tables_of_interest = {"bin_info_master", "live_inventory_master", "sku_master"}
for r in rows:
    if r["Table_name"] in tables_of_interest:
        print(f"TABLE: {r['Table_name']}")
        print(f"  DESC: {r['Table_description'][:150]}")  
        col_key = [k for k in r.keys() if "column" in k.lower()][0]
        print(f"  COLS: {r[col_key][:250]}")
        print(f"  PK: {r['Primary_key']}")
        print(f"  CAT: {r['Table_category']}")
        print()

# Check table_descriptions.json
with open("data/database/table_descriptions.json", encoding="utf-8") as f:
    descs = json.load(f)

print(f"\ntable_descriptions.json: {len(descs)} entries")
for d in descs:
    if d["table_name"] in tables_of_interest:
        print(f"\nTABLE: {d['table_name']}")
        print(f"  DESC: {d['description'][:150]}")
        print(f"  KEYS: {list(d.keys())}")
        if "frequently_joined_with" in d:
            print(f"  JOINS: {d['frequently_joined_with']}")
        if "self_sufficient_for" in d:
            print(f"  SELF-SUFFICIENT: {d['self_sufficient_for'][:2]}")
