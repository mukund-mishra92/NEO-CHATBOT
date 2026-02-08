"""
Clean classified_queries.jsonl by removing incorrect bin presentation queries
and replacing them with correct ones using task_master_log.
"""

import json
from datetime import datetime

input_file = r"c:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\classification\classified_queries.jsonl"
output_file = r"c:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\classification\classified_queries_cleaned.jsonl"
backup_file = r"c:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\classification\classified_queries_backup.jsonl"

# Keywords that indicate bin presentation queries with wrong tables
wrong_table_indicators = [
    "station_pick_task_master",
    "recovery_pick_task_master",
    "order_bin_mapping"
]

# Correct queries to add
correct_queries = [
    {
        "query_id": "correct_bin_pres_station_timerange",
        "timestamp": datetime.now().isoformat(),
        "session_id": "system_correction",
        "user_query": "compute bin presentations done on each station from 7 pm to 9 pm yesterday",
        "generated_sql": """SELECT 
  hm.STATION_ID, 
  hm.STATION_ALIAS_NAME, 
  COUNT(*) AS bin_presentations 
FROM task_master_log tl 
JOIN hw_station_master hm ON tl.destination_location_id = hm.location_id 
WHERE tl.TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE') 
  AND tl.STATUS = 'COMPLETED' 
  AND tl.logged_timestamp >= (CURDATE() - INTERVAL 1 DAY) + INTERVAL 19 HOUR 
  AND tl.logged_timestamp < (CURDATE() - INTERVAL 1 DAY) + INTERVAL 21 HOUR 
GROUP BY hm.STATION_ID, hm.STATION_ALIAS_NAME 
ORDER BY bin_presentations DESC""",
        "execution_status": "success",
        "rows_returned": None,
        "confidence": 0.98,
        "tables_used": ["task_master_log", "hw_station_master"],
        "classification": "bin_presentation",
        "classification_timestamp": datetime.now().isoformat(),
        "classification_notes": "Corrected query using task_master_log",
        "corrected_sql": None,
        "metadata": {
            "source": "manual_correction",
            "correction_reason": "Original used wrong table (station_pick_task_master). Bin presentations MUST use task_master_log."
        }
    },
    {
        "query_id": "correct_bin_pres_bot_timerange",
        "timestamp": datetime.now().isoformat(),
        "session_id": "system_correction",
        "user_query": "compute bin presentations done per bot from 7 pm to 9 pm yesterday",
        "generated_sql": """SELECT 
  tl.BOT_ID, 
  bm.BOT_NAME, 
  COUNT(*) AS bin_presentations 
FROM task_master_log tl 
LEFT JOIN bot_master bm ON tl.BOT_ID = bm.BOT_ID 
WHERE tl.TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE') 
  AND tl.STATUS = 'COMPLETED' 
  AND tl.logged_timestamp >= (CURDATE() - INTERVAL 1 DAY) + INTERVAL 19 HOUR 
  AND tl.logged_timestamp < (CURDATE() - INTERVAL 1 DAY) + INTERVAL 21 HOUR 
GROUP BY tl.BOT_ID, bm.BOT_NAME 
ORDER BY bin_presentations DESC""",
        "execution_status": "success",
        "rows_returned": None,
        "confidence": 0.98,
        "tables_used": ["task_master_log", "bot_master"],
        "classification": "bin_presentation",
        "classification_timestamp": datetime.now().isoformat(),
        "classification_notes": "Correct query using task_master_log for per-bot analysis",
        "corrected_sql": None,
        "metadata": {
            "source": "manual_correction",
            "correction_reason": "Bin presentations per bot MUST use task_master_log grouped by BOT_ID."
        }
    }
]

def should_remove_query(query_obj):
    """Check if query should be removed (wrong bin presentation query)."""
    user_query = query_obj.get("user_query", "").lower()
    generated_sql = query_obj.get("generated_sql", "").lower()
    
    # Check if it's a bin presentation query
    is_bin_presentation = any(phrase in user_query for phrase in [
        "bin presentation", "bins presented", "bins reached", 
        "bins delivered", "bin presentations"
    ])
    
    if not is_bin_presentation:
        return False
    
    # Check if it uses wrong tables
    uses_wrong_table = any(table in generated_sql for table in wrong_table_indicators)
    
    return uses_wrong_table

# Create backup
print("Creating backup...")
import shutil
shutil.copy2(input_file, backup_file)
print(f"Backup created: {backup_file}")

# Process the file
removed_count = 0
kept_count = 0

print("\nProcessing queries...")
with open(input_file, 'r', encoding='utf-8') as infile, \
     open(output_file, 'w', encoding='utf-8') as outfile:
    
    for line_num, line in enumerate(infile, 1):
        if not line.strip():
            continue
            
        try:
            query_obj = json.loads(line)
            
            if should_remove_query(query_obj):
                removed_count += 1
                print(f"  Line {line_num}: REMOVED - {query_obj.get('user_query', 'N/A')[:80]}")
            else:
                outfile.write(line)
                kept_count += 1
        except json.JSONDecodeError as e:
            print(f"  Line {line_num}: WARNING - Invalid JSON, keeping as-is")
            outfile.write(line)
            kept_count += 1
    
    # Add correct queries at the end
    print("\nAdding correct queries...")
    for correct_query in correct_queries:
        outfile.write(json.dumps(correct_query) + '\n')
        print(f"  ADDED: {correct_query['user_query']}")

print(f"\n{'='*60}")
print(f"Summary:")
print(f"  Queries kept: {kept_count}")
print(f"  Queries removed: {removed_count}")
print(f"  Correct queries added: {len(correct_queries)}")
print(f"  Output file: {output_file}")
print(f"{'='*60}")

# Replace original with cleaned version
print("\nReplacing original file with cleaned version...")
import os
os.replace(output_file, input_file)
print("✓ File cleaned successfully!")
print(f"\nBackup available at: {backup_file}")
