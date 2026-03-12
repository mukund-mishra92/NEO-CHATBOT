"""
Test SQL Query Cleaning Function
Tests that SQL queries are properly cleaned without losing important characters
"""

import sys
import re

def _clean_sql_query(text: str) -> str:
    """Clean SQL query while preserving SQL syntax"""
    if not text or not isinstance(text, str):
        return ""
    # Replace smart quotes with regular SQL quotes
    text = text.replace('\x91', "'").replace('\x92', "'")  # Smart single quotes
    text = text.replace('\x93', "'").replace('\x94', "'")  # Smart double quotes
    text = text.replace('\u2018', "'").replace('\u2019', "'")  # Unicode smart quotes
    text = text.replace('\u201c', "'").replace('\u201d', "'")  # Unicode smart quotes
    # Remove only null/control characters that would break SQL
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
    # Normalize line breaks to single spaces
    text = text.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
    # Normalize multiple spaces to single space
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


def test_sql_cleaning():
    """Test various SQL query scenarios"""
    
    print("=" * 70)
    print("Testing SQL Query Cleaning Function")
    print("=" * 70)
    
    test_cases = [
        {
            "name": "Basic SELECT with asterisk",
            "input": "Select * from steps where bot_id='BOT-0001'",
            "expected_has": ["*", "Select", "from", "steps", "'BOT-0001'"],
            "expected_not": ["\x92", "\x91", "\\x92"]
        },
        {
            "name": "Query with smart single quotes (\\x92)",
            "input": "Select * from steps where bot_id=\x92BOT-0001\x92",
            "expected_has": ["*", "'BOT-0001'"],
            "expected_not": ["\x92", "\x91"]
        },
        {
            "name": "Multiple queries separated by semicolons",
            "input": "Select * from task_master where bot_id='BOT-001'; Select * from steps where bot_id='BOT-001'",
            "expected_has": ["*", "task_master", "steps", ";"],
            "expected_not": ["\x92", "\x91"]
        },
        {
            "name": "Query with COUNT and comparison",
            "input": "Select * from task_detail where bot_id='BOT-001' and COUNT_OF_STEPS_SENT>0",
            "expected_has": ["*", "COUNT_OF_STEPS_SENT", ">", "0"],
            "expected_not": ["\x92", "\x91"]
        },
        {
            "name": "Query with Unicode smart quotes",
            "input": "Select * from steps where bot_id=\u2018BOT-0001\u2019",
            "expected_has": ["*", "'BOT-0001'"],
            "expected_not": ["\u2018", "\u2019", "\x92"]
        },
        {
            "name": "Query with extra whitespace",
            "input": "Select  *   from    steps\nwhere bot_id='BOT-0001'",
            "expected_has": ["Select * from steps where"],
            "expected_not": ["  ", "\n"]
        },
        {
            "name": "Complex query with multiple conditions",
            "input": "Select * from bots where status='active' and type='AGV' and zone_id=5",
            "expected_has": ["*", "status='active'", "type='AGV'", "zone_id=5"],
            "expected_not": ["\x92"]
        }
    ]
    
    passed = 0
    failed = 0
    
    for i, test in enumerate(test_cases, 1):
        print(f"\nTest {i}: {test['name']}")
        print("-" * 70)
        
        # Clean the query
        result = _clean_sql_query(test['input'])
        
        print(f"Input:  {repr(test['input'][:60])}{'...' if len(test['input']) > 60 else ''}")
        print(f"Output: {result}")
        
        # Check expected items are present
        test_passed = True
        for expected in test['expected_has']:
            if expected not in result:
                print(f"  ❌ FAIL: Expected to find '{expected}' in result")
                test_passed = False
        
        # Check unwanted items are not present
        for not_expected in test['expected_not']:
            if not_expected in result:
                print(f"  ❌ FAIL: Did not expect to find '{not_expected}' in result")
                test_passed = False
        
        if test_passed:
            print("  ✅ PASS")
            passed += 1
        else:
            failed += 1
    
    print("\n" + "=" * 70)
    print(f"Results: {passed} passed, {failed} failed out of {len(test_cases)} tests")
    print("=" * 70)
    
    return failed == 0


def test_original_bug():
    """Test the specific bug reported by the user"""
    print("\n" + "=" * 70)
    print("Testing Original Bug Fix")
    print("=" * 70)
    
    # The exact SQL from the CSV
    input_query = "Select * from steps where bot_id='BOT-0001'."
    
    # What the user was seeing (simulated with smart quotes)
    buggy_input = "Select * from steps where bot_id=\x92BOT-0001\x92."
    
    print(f"\nOriginal SQL (correct): {input_query}")
    print(f"Buggy SQL (with smart quotes): {repr(buggy_input)}")
    
    cleaned = _clean_sql_query(buggy_input)
    print(f"\nAfter cleaning: {cleaned}")
    
    # Check if cleaned version has proper syntax
    has_asterisk = '*' in cleaned
    has_proper_quotes = "'" in cleaned and '\x92' not in cleaned
    no_smart_quotes = '\x92' not in cleaned
    
    print(f"\n✅ Has asterisk (*): {has_asterisk}")
    print(f"✅ Has proper quotes ('): {has_proper_quotes}")
    print(f"✅ No smart quotes (\\x92): {no_smart_quotes}")
    
    if has_asterisk and has_proper_quotes and no_smart_quotes:
        print("\n✅ ORIGINAL BUG FIXED!")
        return True
    else:
        print("\n❌ ORIGINAL BUG NOT FIXED")
        return False


if __name__ == "__main__":
    print("\n🔧 SQL Query Cleaning Test Suite\n")
    
    # Test the cleaning function
    all_tests_passed = test_sql_cleaning()
    
    # Test the specific bug
    bug_fixed = test_original_bug()
    
    if all_tests_passed and bug_fixed:
        print("\n🎉 All tests passed! SQL query cleaning is working correctly.")
        sys.exit(0)
    else:
        print("\n❌ Some tests failed. Please review the implementation.")
        sys.exit(1)
