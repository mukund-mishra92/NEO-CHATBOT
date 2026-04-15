import csv
schema_typed = {}
with open("data/database/Table_information.csv", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    headers = {h.lower().strip(): h for h in reader.fieldnames}
    for row in reader:
        t = row[headers["table_name"]].strip()
        c = row[headers["table_columns(data type)"]].strip()
        pk = row[headers["primary_key"]].strip()
        schema_typed[t] = {"cols": c, "pk": pk}

for t in ["bin_info_master", "live_inventory_master", "sku_master"]:
    info = schema_typed.get(t, {})
    print(f"{t}:")
    print(f"  PK: {info.get('pk', 'N/A')}")
    print(f"  COLS: {info.get('cols', 'N/A')}")
    print()
