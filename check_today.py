import pymysql
from datetime import datetime

conn = pymysql.connect(host='localhost', user='root', password='root', database='neo')
cursor = conn.cursor()

# Check records from today
cursor.execute("""
    SELECT chatbot_type, user_query, timestamp 
    FROM chatbot_chat_history 
    WHERE DATE(timestamp) = CURDATE()
    ORDER BY timestamp DESC
""")

results = cursor.fetchall()
print(f"\n📊 Records from TODAY ({datetime.now().date()}):")
print("=" * 100)

if results:
    for row in results:
        query = row[1][:70] + '...' if len(row[1]) > 70 else row[1]
        print(f"{row[2]} | {row[0]:20} | {query}")
    print(f"\n✅ Total found: {len(results)}")
else:
    print("❌ No records found from today")
    print("\nMost recent record:")
    cursor.execute("SELECT timestamp, chatbot_type, user_query FROM chatbot_chat_history ORDER BY timestamp DESC LIMIT 1")
    last = cursor.fetchone()
    if last:
        print(f"   {last[0]} | {last[1]} | {last[2][:60]}...")

cursor.close()
conn.close()
