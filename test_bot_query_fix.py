"""
Test script to verify bot query fix
Tests that "where is bot 32" generates correct SQL with existing columns
"""

import requests
import json

# Test endpoint
BASE_URL = "http://localhost:8000"

def test_bot_query():
    """Test bot location query"""
    print("\n" + "="*80)
    print("TEST: Where is bot 32")
    print("="*80)
    
    payload = {
        "query": "where is bot 32",
        "session_id": "test_fix_session",
        "user_id": "test_user"
    }
    
    response = requests.post(f"{BASE_URL}/api/chat", json=payload)
    
    print(f"\nStatus Code: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"\nResponse: {data.get('response', '')[:500]}")
        
        # Check SQL query
        metadata = data.get('metadata', {})
        sql = metadata.get('generated_sql', '')
        
        print(f"\nGenerated SQL:\n{sql}")
        
        # Validation checks
        checks = {
            "Uses BOT_ID column": "BOT_ID" in sql,
            "NO BOT_NUMBER in WHERE": "BOT_NUMBER" not in sql,
            "Uses bot_master table": "bot_master" in sql.lower(),
            "Has location columns (GRIDX/GRIDY/GRIDZ)": any(col in sql for col in ['GRIDX', 'GRIDY', 'GRIDZ']),
        }
        
        print("\n" + "-"*80)
        print("VALIDATION CHECKS:")
        print("-"*80)
        for check, passed in checks.items():
            status = "✅ PASS" if passed else "❌ FAIL"
            print(f"{status}: {check}")
        
        all_passed = all(checks.values())
        print("\n" + "="*80)
        if all_passed:
            print("✅ ALL CHECKS PASSED - BUG IS FIXED!")
        else:
            print("❌ SOME CHECKS FAILED - BUG STILL EXISTS!")
        print("="*80)
        
        return all_passed
    else:
        print(f"❌ Error: {response.text}")
        return False


def test_bot_list_query():
    """Test bot listing query"""
    print("\n" + "="*80)
    print("TEST: List all bots")
    print("="*80)
    
    payload = {
        "query": "show me all bots",
        "session_id": "test_fix_session_2",
        "user_id": "test_user"
    }
    
    response = requests.post(f"{BASE_URL}/api/chat", json=payload)
    
    if response.status_code == 200:
        data = response.json()
        metadata = data.get('metadata', {})
        sql = metadata.get('generated_sql', '')
        
        print(f"\nGenerated SQL:\n{sql}")
        
        checks = {
            "Uses bot_master table": "bot_master" in sql.lower(),
            "NO BOT_NUMBER column": "BOT_NUMBER" not in sql,
            "NO IS_ACTIVE column": "IS_ACTIVE" not in sql,
            "NO BOT_TYPE column": "BOT_TYPE" not in sql,
        }
        
        print("\n" + "-"*80)
        print("VALIDATION CHECKS:")
        print("-"*80)
        for check, passed in checks.items():
            status = "✅ PASS" if passed else "❌ FAIL"
            print(f"{status}: {check}")
        
        return all(checks.values())
    else:
        print(f"❌ Error: {response.text}")
        return False


if __name__ == "__main__":
    print("\n🔍 TESTING BOT QUERY FIX")
    print("This script tests that bot queries use correct column names")
    print("Expected: BOT_ID (NOT BOT_NUMBER), STATUS, GRIDX, GRIDY, GRIDZ, IP")
    
    try:
        test1_passed = test_bot_query()
        test2_passed = test_bot_list_query()
        
        print("\n" + "="*80)
        print("FINAL RESULTS:")
        print("="*80)
        print(f"Test 1 (Where is bot 32): {'✅ PASSED' if test1_passed else '❌ FAILED'}")
        print(f"Test 2 (List all bots): {'✅ PASSED' if test2_passed else '❌ FAILED'}")
        
        if test1_passed and test2_passed:
            print("\n🎉 ALL TESTS PASSED - BOT QUERY BUG IS FIXED!")
        else:
            print("\n⚠️ Some tests failed - bug may still exist")
            
    except requests.exceptions.ConnectionError:
        print("\n❌ ERROR: Cannot connect to server at http://localhost:8000")
        print("Make sure the backend server is running!")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
