import pymysql
from datetime import datetime

# Connect to database
conn = pymysql.connect(
    host='localhost', 
    user='root', 
    password='root', 
    database='neo'
)
cursor = conn.cursor()

# Check total records
cursor.execute('SELECT COUNT(*) FROM chatbot_chat_history')
total = cursor.fetchone()[0]
print(f'\n📊 Total records in chatbot_chat_history: {total}')

# Check records by chatbot type
cursor.execute('''
    SELECT chatbot_type, COUNT(*) as count 
    FROM chatbot_chat_history 
    GROUP BY chatbot_type
''')
print('\n📈 Records by chatbot type:')
for row in cursor.fetchall():
    print(f'   - {row[0]}: {row[1]} records')

# Check recent records
cursor.execute('''
    SELECT chat_id, chatbot_type, user_query, timestamp 
    FROM chatbot_chat_history 
    ORDER BY timestamp DESC 
    LIMIT 10
''')
print('\n🕐 Recent 10 chat records:')
print('=' * 100)
results = cursor.fetchall()
for row in results:
    chat_id = row[0][:30] + '...' if len(row[0]) > 30 else row[0]
    chatbot_type = row[1]
    query = row[2][:60] + '...' if len(row[2]) > 60 else row[2]
    timestamp = row[3]
    print(f'{timestamp} | {chatbot_type:20} | {chat_id}')
    print(f'   Query: {query}')
    print()

# Check if there are records from today
cursor.execute('''
    SELECT COUNT(*) 
    FROM chatbot_chat_history 
    WHERE DATE(timestamp) = CURDATE()
''')
today_count = cursor.fetchone()[0]
print(f'\n📅 Records from today: {today_count}')

# Check most recent timestamp
cursor.execute('SELECT MAX(timestamp) FROM chatbot_chat_history')
last_record = cursor.fetchone()[0]
print(f'⏰ Most recent record: {last_record}')

cursor.close()
conn.close()
