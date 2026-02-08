import json
from pathlib import Path

# Read all lines
with open('data/classification/classified_queries.jsonl', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"Original: {len(lines)} lines")

# Find entries with "hourly average bin presentation"
bad_indices = []
for i, line in enumerate(lines):
    try:
        entry = json.loads(line)
        query = entry.get('user_query', '').lower()
        tables = entry.get('tables_used', [])
        
        if 'hourly average bin presentation' in query:
            print(f"\nFound at line {i+1}:")
            print(f"  Query: {entry.get('user_query')}")
            print(f"  Tables: {tables}")
            print(f"  Contains 'order_bin_task_master': {'order_bin_task_master' in str(entry)}")
            
            # Mark for removal if it uses wrong table
            if 'order_bin_task_master' in str(entry):
                bad_indices.append(i)
                print(f"  → MARKED FOR REMOVAL")
    except:
        pass

if bad_indices:
    print(f"\n\nRemoving {len(bad_indices)} bad entries...")
    
    # Keep only good lines
    good_lines = [line for i, line in enumerate(lines) if i not in bad_indices]
    
    # Backup
    backup_path = 'data/classification/classified_queries_backup_hourly.jsonl'
    with open(backup_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print(f"✓ Backup saved to {backup_path}")
    
    # Write cleaned file
    with open('data/classification/classified_queries.jsonl', 'w', encoding='utf-8') as f:
        f.writelines(good_lines)
    
    print(f"✓ Cleaned file: {len(good_lines)} lines remaining")
else:
    print("\nNo bad entries found!")
