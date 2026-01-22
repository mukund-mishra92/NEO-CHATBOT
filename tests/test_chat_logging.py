"""
Test script to verify chat history logging for all chatbot types
"""
import pymysql
from datetime import datetime, timedelta

def check_chat_history():
    """Check chat history records in the database"""
    
    # Connect to database
    conn = pymysql.connect(
        host='localhost',
        user='root',
        password='root',
        database='neo'
    )
    cursor = conn.cursor()
    
    print("\n" + "="*100)
    print("📊 CHAT HISTORY DATABASE STATUS")
    print("="*100)
    
    # Total records
    cursor.execute('SELECT COUNT(*) FROM chatbot_chat_history')
    total = cursor.fetchone()[0]
    print(f"\n✅ Total records: {total}")
    
    # Records by chatbot type
    cursor.execute('''
        SELECT chatbot_type, COUNT(*) as count 
        FROM chatbot_chat_history 
        GROUP BY chatbot_type
        ORDER BY count DESC
    ''')
    print("\n📈 Records by Chatbot Type:")
    print("-" * 60)
    for row in cursor.fetchall():
        print(f"   {row[0]:20} : {row[1]:5} records")
    
    # Records from today
    cursor.execute('''
        SELECT COUNT(*) 
        FROM chatbot_chat_history 
        WHERE DATE(timestamp) = CURDATE()
    ''')
    today_count = cursor.fetchone()[0]
    print(f"\n📅 Records from today: {today_count}")
    
    # Records from last hour
    cursor.execute('''
        SELECT COUNT(*) 
        FROM chatbot_chat_history 
        WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    ''')
    last_hour = cursor.fetchone()[0]
    print(f"⏰ Records from last hour: {last_hour}")
    
    # Most recent timestamp
    cursor.execute('SELECT MAX(timestamp) FROM chatbot_chat_history')
    last_record = cursor.fetchone()[0]
    print(f"🕐 Most recent record: {last_record}")
    
    # Recent records from each type
    print("\n" + "="*100)
    print("📝 RECENT RECORDS BY TYPE (Last 5 from each)")
    print("="*100)
    
    for chatbot_type in ['knowledge_base', 'sql_assistant', 'diagnostic']:
        cursor.execute('''
            SELECT chat_id, user_query, timestamp, confidence_score
            FROM chatbot_chat_history 
            WHERE chatbot_type = %s
            ORDER BY timestamp DESC 
            LIMIT 5
        ''', (chatbot_type,))
        
        results = cursor.fetchall()
        print(f"\n🔹 {chatbot_type.upper().replace('_', ' ')}:")
        print("-" * 100)
        
        if results:
            for row in results:
                chat_id = row[0][:30] + '...'
                query = row[1][:60] + '...' if len(row[1]) > 60 else row[1]
                timestamp = row[2]
                confidence = row[3]
                print(f"   {timestamp} | Conf: {confidence:.2f} | {query}")
        else:
            print("   ❌ No records found")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*100)
    print("✅ Chat history check complete!")
    print("="*100 + "\n")

if __name__ == "__main__":
    try:
        check_chat_history()
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
