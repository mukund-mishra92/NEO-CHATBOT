# import pandas as pd

# df = pd.read_csv('Table_information.csv')

# print("="*80)
# print("UPDATED CSV VERIFICATION")
# print("="*80)

# # Check bot_master
# bot_master = df[df['Table_name'] == 'bot_master'].iloc[0]
# print(f"\n✅ bot_master:")
# print(f"   Category: {bot_master['Table_category']}")
# print(f"   Description: {bot_master['Table_description'][:80]}...")

# # Check bot_master_log
# bot_log = df[df['Table_name'] == 'bot_master_log'].iloc[0]
# print(f"\n📋 bot_master_log:")
# print(f"   Category: {bot_log['Table_category']}")
# print(f"   Description: {bot_log['Table_description'][:80]}...")

# # Check telemetry tables
# tele = df[df['Table_name'].str.contains('feedback|teleoperation', case=False, na=False)]
# print(f"\n📊 Telemetry/Feedback tables:")
# for _, row in tele.iterrows():
#     print(f"   {row['Table_name']}: {row['Table_category']}")

# print("\n" + "="*80)
# print("PRIORITY MULTIPLIERS (when query contains 'current position'):")
# print("="*80)
# print(f"bot_master:         3.0× ✅ HIGH PRIORITY")
# print(f"bot_master_log:     0.2× ❌ LOW PRIORITY")
# print(f"telemetry_table:    0.2× ❌ LOW PRIORITY")
# print("="*80)


import json
from pathlib import Path

INPUT_FILE = INPUT_FILE = r"C:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\classification\classified_queries.jsonl"
OUTPUT_FILE = r"C:\Users\Balmukund.Mishra\Desktop\NEO\Neo-Chatbot\data\classification\classified_queries_2.jsonl"

REQUIRED_FIELDS = {
    "query_id": "",
    "timestamp": None,
    "session_id": "",
    "user_query": "",
    "generated_sql": "",
    "execution_status": "unknown",
    "rows_returned": 0,
    "confidence": 0.0,
    "tables_used": [],
    "classification": "unclassified",
    "classification_timestamp": None,
    "classification_notes": None,
    "corrected_sql": None,
    "metadata": {}
}


def normalize_record(record: dict) -> dict:
    """Ensure record matches service expectations"""
    fixed = {}

    for key, default in REQUIRED_FIELDS.items():
        value = record.get(key, default)

        # Fix metadata edge case
        if key == "metadata" and value is None:
            value = {}

        fixed[key] = value

    return fixed


def fix_jsonl():
    good = 0
    bad = 0

    with open(INPUT_FILE, "r", encoding="utf-8") as infile, \
         open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:

        for line_no, line in enumerate(infile, start=1):
            line = line.strip()
            if not line:
                continue

            try:
                record = json.loads(line)
                record = normalize_record(record)
                outfile.write(json.dumps(record, ensure_ascii=False) + "\n")
                good += 1
            except Exception as e:
                bad += 1
                print(f"❌ Skipped line {line_no}: {e}")

    print("\n====== SUMMARY ======")
    print(f"✅ Valid records written : {good}")
    print(f"❌ Corrupted lines skipped: {bad}")
    #print(f"📄 Output file: {OUTPUT_FILE.resolve()}")


if __name__ == "__main__":
    fix_jsonl()
