import json

with open('data/classification/classified_queries.jsonl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

if lines:
    last_entry = json.loads(lines[-1])
    print(f"\nLast entry:")
    print(f"  Query ID: {last_entry.get('query_id', 'N/A')}")
    print(f"  User query: {last_entry.get('user_query', 'N/A')}")
    print(f"  Tables used: {last_entry.get('tables_used', 'N/A')}")
    print(f"  Confidence: {last_entry.get('confidence', 'N/A')}")
