"""
Test SQL Assistant Service - Phase 3
Tests the semantic frame-driven architecture end-to-end
"""

import sys
import os
from pathlib import Path

# Add backend to path
BACKEND_ROOT = Path(__file__).resolve().parent / "backend"
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

# Set environment for config
os.environ.setdefault("ENVIRONMENT", "development")

from app.models.schemas import ChatRequest, ChatbotType
from app.services.sql_assistant.core import SQLAssistantService


def test_simple_query():
    """Test 1: Simple single-table query"""
    print("\n" + "="*80)
    print("TEST 1: Simple Single-Table Query")
    print("="*80)
    
    service = SQLAssistantService()
    
    request = ChatRequest(
        message="Show me all bots",
        chatbot_type=ChatbotType.SQL_ASSISTANT,
        session_id="test-session-1",
        conversation_history=[]
    )
    
    response = service.process_query(request)
    
    print(f"\n✅ Response:")
    print(f"Confidence: {response.confidence_score:.2f}")
    print(f"Response:\n{response.response[:500]}...")
    
    return response.confidence_score > 0.5


def test_filter_query():
    """Test 2: Query with filters"""
    print("\n" + "="*80)
    print("TEST 2: Query with Filters")
    print("="*80)
    
    service = SQLAssistantService()
    
    request = ChatRequest(
        message="Show me all active bots",
        chatbot_type=ChatbotType.SQL_ASSISTANT,
        session_id="test-session-2",
        conversation_history=[]
    )
    
    response = service.process_query(request)
    
    print(f"\n✅ Response:")
    print(f"Confidence: {response.confidence_score:.2f}")
    print(f"Response:\n{response.response[:500]}...")
    
    return response.confidence_score > 0.5


def test_join_query():
    """Test 3: Query requiring JOIN"""
    print("\n" + "="*80)
    print("TEST 3: Query Requiring JOIN")
    print("="*80)
    
    service = SQLAssistantService()
    
    request = ChatRequest(
        message="Show me bots with their assigned tasks",
        chatbot_type=ChatbotType.SQL_ASSISTANT,
        session_id="test-session-3",
        conversation_history=[]
    )
    
    response = service.process_query(request)
    
    print(f"\n✅ Response:")
    print(f"Confidence: {response.confidence_score:.2f}")
    print(f"Response:\n{response.response[:500]}...")
    
    return response.confidence_score > 0.5


def test_aggregation_query():
    """Test 4: Aggregation query"""
    print("\n" + "="*80)
    print("TEST 4: Aggregation Query")
    print("="*80)
    
    service = SQLAssistantService()
    
    request = ChatRequest(
        message="Count the number of bots by status",
        chatbot_type=ChatbotType.SQL_ASSISTANT,
        session_id="test-session-4",
        conversation_history=[]
    )
    
    response = service.process_query(request)
    
    print(f"\n✅ Response:")
    print(f"Confidence: {response.confidence_score:.2f}")
    print(f"Response:\n{response.response[:500]}...")
    
    return response.confidence_score > 0.5


def test_component_initialization():
    """Test component initialization"""
    print("\n" + "="*80)
    print("TEST 0: Component Initialization")
    print("="*80)
    
    try:
        service = SQLAssistantService()
        
        print(f"[OK] LLM Service: {'Initialized' if service.llm_service else 'Failed'}")
        print(f"[OK] Schema Parser: {'Initialized' if service.schema_parser else 'Failed'}")
        print(f"[OK] Schema Graph: {'Initialized' if service.schema_graph else 'Failed'}")
        print(f"[OK] DB Available: {service.db_available}")
        print(f"[OK] Available Tables: {len(service.available_tables)}")
        print(f"[OK] Base Table Resolver: {'Initialized' if service.base_table_resolver else 'Failed'}")
        print(f"[OK] Semantic Extractor: {'Initialized' if service.semantic_extractor else 'Failed'}")
        print(f"[OK] SQL Builder: {'Initialized' if service.sql_builder else 'Failed'}")
        
        return True
    except Exception as e:
        print(f"X Initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_all_tests():
    """Run all tests"""
    print("\n" + "="*80)
    print("SQL ASSISTANT PHASE 3 - TEST SUITE")
    print("="*80)
    
    results = {}
    
    # Test 0: Initialization
    results['initialization'] = test_component_initialization()
    
    if not results['initialization']:
        print("\n[FAIL] Initialization failed. Stopping tests.")
        return
    
    # Test 1: Simple query
    try:
        results['simple_query'] = test_simple_query()
    except Exception as e:
        print(f"\n[FAIL] Test 1 failed: {e}")
        import traceback
        traceback.print_exc()
        results['simple_query'] = False
    
    # Test 2: Filter query
    try:
        results['filter_query'] = test_filter_query()
    except Exception as e:
        print(f"\n[FAIL] Test 2 failed: {e}")
        import traceback
        traceback.print_exc()
        results['filter_query'] = False
    
    # Test 3: JOIN query
    try:
        results['join_query'] = test_join_query()
    except Exception as e:
        print(f"\n[FAIL] Test 3 failed: {e}")
        import traceback
        traceback.print_exc()
        results['join_query'] = False
    
    # Test 4: Aggregation query
    try:
        results['aggregation_query'] = test_aggregation_query()
    except Exception as e:
        print(f"\n[FAIL] Test 4 failed: {e}")
        import traceback
        traceback.print_exc()
        results['aggregation_query'] = False
    
    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for test_name, result in results.items():
        status = "[PASS]" if result else "[FAIL]"
        print(f"{status}: {test_name}")
    
    print(f"\nTotal: {passed}/{total} tests passed ({passed/total*100:.0f}%)")
    
    if passed == total:
        print("\n[SUCCESS] All tests passed!")
    else:
        print(f"\n[WARNING] {total - passed} test(s) failed")


if __name__ == "__main__":
    run_all_tests()
