"""
Test script for Step-by-Step Diagnostic Workflow

This script tests the diagnostic workflow API endpoints
"""

import sys
import json

# Add parent directory to path
sys.path.insert(0, 'backend')

from ..\backend\app.services.diagnostic_support_service import DiagnosticSupportService


def test_solution_parsing():
    """Test solution step parsing"""
    print("=" * 60)
    print("Testing Solution Parsing")
    print("=" * 60)
    
    service = DiagnosticSupportService()
    
    # Test case 1: Numbered list
    solution1 = """1. Check bot status in database
2. Verify bot assignment to station
3. Check for error messages
4. Reset bot if needed"""
    
    steps1 = service.parse_solution_steps(solution1)
    print("\nTest 1: Numbered List (1., 2., 3.)")
    print(f"Input: {solution1[:50]}...")
    print(f"Parsed Steps: {len(steps1)}")
    for i, step in enumerate(steps1, 1):
        print(f"  Step {i}: {step}")
    
    # Test case 2: Step format
    solution2 = """Step 1: Query bot status table
Step 2: Confirm bot assignment
Step 3: Review error logs"""
    
    steps2 = service.parse_solution_steps(solution2)
    print("\nTest 2: Step Format (Step 1:, Step 2:)")
    print(f"Parsed Steps: {len(steps2)}")
    for i, step in enumerate(steps2, 1):
        print(f"  Step {i}: {step}")
    
    # Test case 3: Multi-line
    solution3 = """Check bot status
Verify assignment
Reset if needed"""
    
    steps3 = service.parse_solution_steps(solution3)
    print("\nTest 3: Multi-line (no numbers)")
    print(f"Parsed Steps: {len(steps3)}")
    for i, step in enumerate(steps3, 1):
        print(f"  Step {i}: {step}")


def test_sql_parsing():
    """Test SQL query parsing"""
    print("\n" + "=" * 60)
    print("Testing SQL Query Parsing")
    print("=" * 60)
    
    service = DiagnosticSupportService()
    
    # Test case 1: Multiple queries
    sql1 = """SELECT * FROM bot_status WHERE bot_id = 123;
SELECT * FROM bot_tasks WHERE bot_id = 123;
SELECT * FROM error_logs WHERE bot_id = 123 ORDER BY timestamp DESC LIMIT 10;"""
    
    queries1 = service.parse_sql_queries(sql1)
    print("\nTest 1: Multiple Queries (semicolon separated)")
    print(f"Parsed Queries: {len(queries1)}")
    for i, query in enumerate(queries1, 1):
        print(f"  Query {i}: {query[:60]}...")
    
    # Test case 2: Single query
    sql2 = "SELECT * FROM orders WHERE status = 'PENDING'"
    
    queries2 = service.parse_sql_queries(sql2)
    print("\nTest 2: Single Query")
    print(f"Parsed Queries: {len(queries2)}")
    for i, query in enumerate(queries2, 1):
        print(f"  Query {i}: {query}")


def test_session_workflow():
    """Test diagnostic session workflow"""
    print("\n" + "=" * 60)
    print("Testing Diagnostic Session Workflow")
    print("=" * 60)
    
    service = DiagnosticSupportService()
    
    # Check if we have any issues loaded
    if len(service.bot_level_issues) == 0:
        print("\n⚠️ No bot-level issues loaded. Skipping session test.")
        print("Make sure support log CSV files are in data/support/support_logs/")
        return
    
    # Get first issue
    first_issue = service.bot_level_issues[0]
    issue_id = first_issue.get('s_no')
    
    print(f"\nUsing Issue #{issue_id}")
    print(f"Problem: {first_issue.get('problem', 'N/A')[:60]}...")
    print(f"Severity: {first_issue.get('severity', 'N/A')}")
    
    # Start session
    print("\n1. Starting diagnostic session...")
    result = service.start_diagnostic_session(issue_id, "bot_level")
    
    if not result.get('success'):
        print(f"❌ Failed to start session: {result.get('error')}")
        return
    
    session_id = result.get('session_id')
    print(f"✅ Session started: {session_id}")
    print(f"Total steps: {result.get('total_steps')}")
    print(f"First step: {result['current_step']['step_text'][:60]}...")
    
    # Get session status
    print("\n2. Getting session status...")
    status = service.get_session_status(session_id)
    print(f"✅ Status: {status['status']}")
    print(f"Current step: {status['current_step']['step_number']} of {status['current_step']['total_steps']}")
    
    # Submit feedback (not fixed)
    print("\n3. Submitting feedback (issue not fixed)...")
    feedback = service.submit_step_feedback(session_id, is_fixed=False, feedback_notes="Testing next step")
    
    if feedback.get('status') == 'active':
        print(f"✅ Moved to next step: {feedback['next_step']['step_number']}")
        print(f"Next step text: {feedback['next_step']['step_text'][:60]}...")
    elif feedback.get('status') == 'unresolved':
        print(f"✅ All steps completed: {feedback['message']}")
    
    # Close session
    print("\n4. Closing session...")
    close_result = service.close_session(session_id)
    if close_result.get('success'):
        print(f"✅ Session closed")
        print(f"History entries: {len(close_result.get('history', []))}")


def test_issue_data():
    """Test loaded issue data"""
    print("\n" + "=" * 60)
    print("Loaded Issue Statistics")
    print("=" * 60)
    
    service = DiagnosticSupportService()
    
    print(f"\nBot-level issues: {len(service.bot_level_issues)}")
    print(f"Station-level issues: {len(service.station_level_issues)}")
    
    if service.bot_level_issues:
        print("\nSample Bot-level Issues:")
        for i, issue in enumerate(service.bot_level_issues[:3], 1):
            print(f"\n  Issue #{issue.get('s_no')}:")
            print(f"    Problem: {issue.get('problem', 'N/A')[:60]}...")
            print(f"    Severity: {issue.get('severity', 'N/A')}")
            
            # Parse and show steps
            steps = service.parse_solution_steps(issue.get('solution', ''))
            print(f"    Parsed Steps: {len(steps)}")
            
            # Parse and show queries
            queries = service.parse_sql_queries(issue.get('sql_query', ''))
            print(f"    Parsed SQL Queries: {len(queries)}")


if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("NEO DIAGNOSTIC WORKFLOW TEST SUITE")
    print("=" * 60)
    
    try:
        # Test parsing functions
        test_solution_parsing()
        test_sql_parsing()
        
        # Test loaded data
        test_issue_data()
        
        # Test session workflow
        test_session_workflow()
        
        print("\n" + "=" * 60)
        print("✅ ALL TESTS COMPLETED")
        print("=" * 60)
        print("\nNext Steps:")
        print("1. Start the server: python -m uvicorn app.main:app --reload")
        print("2. Open browser: http://localhost:8000/diagnostic_support.html")
        print("3. Search for an issue and click 'Start Step-by-Step Diagnostic'")
        print("\n")
        
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
