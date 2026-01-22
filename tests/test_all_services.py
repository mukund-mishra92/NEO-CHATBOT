"""
Test all three chatbot services via API
"""

import requests
import json

API_BASE = "http://127.0.0.1:3960/api/chatbot"

print("=" * 80)
print("TESTING ALL THREE CHATBOT SERVICES")
print("=" * 80)

# Test 1: Knowledge Base Service
print("\n[TEST 1] Knowledge Base Service")
print("-" * 80)
try:
    response = requests.post(
        f"{API_BASE}/chat",
        json={
            "message": "what is neo",
            "chatbot_type": "knowledge_base",
            "session_id": "test-session-1"
        }
    )
    if response.status_code == 200:
        result = response.json()
        print(f"✅ Status: {response.status_code}")
        print(f"✅ Confidence: {result.get('confidence_score', 0):.2f}")
        print(f"✅ Response preview: {result.get('response', '')[:100]}...")
    else:
        print(f"❌ Status: {response.status_code}")
        print(f"❌ Error: {response.text}")
except Exception as e:
    print(f"❌ Exception: {e}")

# Test 2: SQL Assistant Service
print("\n[TEST 2] SQL Assistant Service")
print("-" * 80)
try:
    response = requests.post(
        f"{API_BASE}/chat",
        json={
            "message": "give me all the bot ids available in the neo system",
            "chatbot_type": "sql_assistant",
            "session_id": "test-session-2"
        }
    )
    if response.status_code == 200:
        result = response.json()
        print(f"✅ Status: {response.status_code}")
        print(f"✅ Confidence: {result.get('confidence_score', 0):.2f}")
        print(f"✅ Response preview: {result.get('response', '')[:200]}...")
    else:
        print(f"❌ Status: {response.status_code}")
        print(f"❌ Error: {response.text}")
except Exception as e:
    print(f"❌ Exception: {e}")

# Test 3: Diagnostic Service
print("\n[TEST 3] Diagnostic Service")
print("-" * 80)
try:
    response = requests.post(
        f"{API_BASE}/chat",
        json={
            "message": "why bot is not moving",
            "chatbot_type": "diagnostic",
            "session_id": "test-session-3"
        }
    )
    if response.status_code == 200:
        result = response.json()
        print(f"✅ Status: {response.status_code}")
        print(f"✅ Confidence: {result.get('confidence_score', 0):.2f}")
        print(f"✅ Response preview: {result.get('response', '')[:200]}...")
    else:
        print(f"❌ Status: {response.status_code}")
        print(f"❌ Error: {response.text}")
except Exception as e:
    print(f"❌ Exception: {e}")

print("\n" + "=" * 80)
print("TEST SUMMARY")
print("=" * 80)
print("""
All three services should now be working with the refactored modular architecture:
✅ Knowledge Base Service - Uses vector store for documentation
✅ SQL Assistant Service - Generates and executes SQL queries
✅ Diagnostic Service - Provides troubleshooting support
""")
