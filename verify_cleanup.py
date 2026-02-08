import json

with open('data/classification/classified_queries.jsonl', 'r', encoding='utf-8') as f:
    entries = [json.loads(line) for line in f]

print(f"Total queries: {len(entries)}")
print(f"Bin presentation classified: {len([e for e in entries if e.get('classification') == 'bin_presentation'])}")
print(f"High confidence (>=0.95): {len([e for e in entries if e.get('confidence', 0) >= 0.95])}")

# Show the bin presentation queries
print("\nBin presentation queries:")
for i, e in enumerate(entries):
    if e.get('classification') == 'bin_presentation':
        print(f"  {i+1}. Query ID: {e.get('query_id')}")
        print(f"     User query: {e.get('user_query')}")
        print(f"     Confidence: {e.get('confidence')}")
        tables = e.get('tables_used', [])
        print(f"     Tables: {', '.join(tables)}")
        print()
