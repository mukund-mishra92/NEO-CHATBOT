"""
Test Script for Semi-Auto Diagnostic Memory Feature
Run this after starting the backend server to verify the session memory works
"""

import requests
import json

API_BASE = "http://localhost:8000/api/chatbot"

def test_session_memory():
    print("=" * 60)
    print("Testing Semi-Auto Diagnostic Session Memory")
    print("=" * 60)
    
    # Test 1: Start Diagnosis
    print("\n1. Starting diagnosis...")
    response = requests.post(
        f"{API_BASE}/diagnostic/start",
        params={"problem_description": "Bot is not moving on station"}
    )
    
    if response.status_code == 200:
        data = response.json()
        session_id = data.get('session_id')
        print(f"✅ Session created: {session_id}")
        print(f"   Total matches: {data.get('total_matches', 0)}")
        print(f"   Current case: {data.get('current_case', {}).get('case_number', 'N/A')}")
    else:
        print(f"❌ Failed to start diagnosis: {response.status_code}")
        return
    
    # Test 2: Ask Follow-up Question
    print("\n2. Asking follow-up question...")
    response = requests.post(
        f"{API_BASE}/diagnostic/followup",
        params={
            "session_id": session_id,
            "question": "Can you explain this solution?"
        }
    )
    
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Follow-up answered:")
        print(f"   Answer: {data.get('answer', '')[:100]}...")
    else:
        print(f"❌ Failed to ask follow-up: {response.status_code}")
    
    # Test 3: Ask Another Follow-up
    print("\n3. Asking about alternatives...")
    response = requests.post(
        f"{API_BASE}/diagnostic/followup",
        params={
            "session_id": session_id,
            "question": "Are there other solutions?"
        }
    )
    
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Follow-up answered:")
        print(f"   Answer: {data.get('answer', '')[:100]}...")
    else:
        print(f"❌ Failed to ask follow-up: {response.status_code}")
    
    # Test 4: Get Session History
    print("\n4. Getting session history...")
    response = requests.get(f"{API_BASE}/diagnostic/session/{session_id}")
    
    if response.status_code == 200:
        data = response.json()
        history = data.get('conversation_history', [])
        print(f"✅ Session history retrieved:")
        print(f"   Total messages: {len(history)}")
        print(f"   Resolved: {data.get('resolved', False)}")
        
        print("\n   Conversation:")
        for msg in history:
            role = msg.get('role', 'unknown').upper()
            message = msg.get('message', '')[:60]
            print(f"   [{role}] {message}...")
    else:
        print(f"❌ Failed to get session history: {response.status_code}")
    
    # Test 5: Get Session Summary
    print("\n5. Getting session summary...")
    response = requests.post(
        f"{API_BASE}/diagnostic/summary",
        params={"session_id": session_id}
    )
    
    if response.status_code == 200:
        data = response.json()
        summary = data.get('summary', '')
        print(f"✅ Session summary:")
        print(summary[:200] + "...")
    else:
        print(f"❌ Failed to get summary: {response.status_code}")
    
    # Test 6: Provide Negative Feedback (Try Next Solution)
    print("\n6. Marking solution as incorrect (try next)...")
    response = requests.post(
        f"{API_BASE}/diagnostic/feedback",
        params={
            "session_id": session_id,
            "is_correct": False
        }
    )
    
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Feedback processed:")
        print(f"   Status: {data.get('status', 'N/A')}")
        print(f"   Message: {data.get('message', 'N/A')}")
        if data.get('current_case'):
            print(f"   Next case: {data['current_case'].get('case_number', 'N/A')}")
    else:
        print(f"❌ Failed to provide feedback: {response.status_code}")
    
    # Test 7: Get Updated History
    print("\n7. Getting updated conversation history...")
    response = requests.get(f"{API_BASE}/diagnostic/session/{session_id}")
    
    if response.status_code == 200:
        data = response.json()
        history = data.get('conversation_history', [])
        print(f"✅ Updated history has {len(history)} messages")
        
        # Show last 3 messages
        print("\n   Last 3 messages:")
        for msg in history[-3:]:
            role = msg.get('role', 'unknown').upper()
            message = msg.get('message', '')[:60]
            print(f"   [{role}] {message}...")
    else:
        print(f"❌ Failed to get updated history: {response.status_code}")
    
    print("\n" + "=" * 60)
    print("Test Complete!")
    print("=" * 60)

if __name__ == "__main__":
    try:
        test_session_memory()
    except requests.exceptions.ConnectionError:
        print("❌ Error: Cannot connect to backend server")
        print("   Make sure the backend is running on http://localhost:8000")
    except Exception as e:
        print(f"❌ Error: {e}")
