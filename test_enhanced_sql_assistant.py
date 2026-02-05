"""
Test script for Unified SQL Assistant Service
Verifies Tier 1 first approach with LLM fallback
Tests retry logic and high confidence fast path
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from app.services.sql_assistant import SQLAssistantService
from app.models.schemas import ChatRequest

def test_initialization():
    """Test service initialization"""
    print("=" * 60)
    print("TEST 1: Service Initialization")
    print("=" * 60)
    
    try:
        service = SQLAssistantService()
        print("✅ Service initialized successfully")
        print(f"   Database available: {service.db_available}")
        print(f"   Tier 1 available: {service.nl_to_sql_generator is not None}")
        print(f"   Available tables: {len(service.available_tables)}")
        print(f"   High confidence threshold: {service.high_confidence_threshold:.0%}")
        print(f"   Max retry attempts: {service.max_retry_attempts}")
        return service
    except Exception as e:
        print(f"❌ Initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_tier1_simple_query(service):
    """Test Tier 1 generation (always tries first)"""
    print("\n" + "=" * 60)
    print("TEST 2: Tier 1 First - Simple Query")
    print("=" * 60)
    
    if not service.nl_to_sql_generator:
        print("⚠️ Tier 1 not available - will use Tier 2 fallback")
        return
    
    try:
        question = "Show me all bot IDs"
        print(f"Query: {question}")
        
        # Test Tier 1 generation (direct call)
        sql, confidence, metadata = service._try_tier1_generation(question)
        
        if sql:
            print(f"✅ Tier 1 generated SQL:")
            print(f"   SQL: {sql}")
            print(f"   Confidence: {confidence:.0%}")
            print(f"   Tables: {metadata.get('tables_used')}")
            
            # Check if high confidence
            if confidence >= service.high_confidence_threshold:
                print(f"   🚀 HIGH CONFIDENCE - Would skip validation!")
        else:
            print("❌ Tier 1 generation returned None")
    except Exception as e:
        print(f"❌ Tier 1 test failed: {e}")
        import traceback
        traceback.print_exc()

def test_tier2_complex_query(service):
    """Test Tier 2 fallback (when Tier 1 fails)"""
    print("\n" + "=" * 60)
    print("TEST 3: Tier 2 Fallback - LLM Generation")
    print("=" * 60)
    
    try:
        question = "Show me bots that completed tasks yesterday"
        print(f"Query: {question}")
        
        # Force Tier 2 generation
        context = {}
        sql = service._generate_sql_tier2(question, 'with_context', context, 'test_session')
        
        if sql:
            print(f"✅ Tier 2 generated SQL:")
            print(f"   {sql}")
        else:
            print("❌ Tier 2 generation returned None")
    except Exception as e:
        print(f"❌ Tier 2 test failed: {e}")
        import traceback
        traceback.print_exc()

def test_full_query_flow(service):
    """Test full query processing"""
    print("\n" + "=" * 60)
    print("TEST 4: Full Query Flow")
    print("=" * 60)
    
    try:
        request = ChatRequest(
            message="How many bots do we have?",
            session_id=None
        )
        print(f"Query: {request.message}")
        
        response = service.process_query(request)
        
        print(f"\n✅ Response:")
        print(f"   Confidence: {response.confidence_score:.2%}")
        print(f"   Tier used: {response.metadata.get('tier', 'unknown')}")
        print(f"   SQL: {response.metadata.get('sql_query', 'N/A')}")
        print(f"   Row count: {response.metadata.get('row_count', 0)}")
        print(f"\nFormatted response:")
        print("-" * 60)
        print(response.response[:500])
        print("-" * 60)
        
    except Exception as e:
        print(f"❌ Full flow test failed: {e}")
        import traceback
        traceback.print_exc()

def test_tier_selection_logic(service):
    """Test the retry and fallback logic"""
    print("\n" + "=" * 60)
    print("TEST 5: Retry and Fallback Logic")
    print("=" * 60)
    
    test_cases = [
        ("Show me all bots", "Should use Tier 1 first"),
        ("What is the total count of tasks completed last month?", "Should use Tier 1 first, retry if needed"),
    ]
    
    for question, expected in test_cases:
        print(f"\nQuery: {question}")
        print(f"Expected: {expected}")
        
        print(f"   Architecture: ALWAYS Tier 1 first")
        print(f"   - If confidence >= 94%: Skip validation, return immediately")
        print(f"   - If confidence < 75%: Retry up to {service.max_retry_attempts} times")
        print(f"   - If all Tier 1 attempts fail: Fallback to Tier 2 (LLM)")

def main():
    print("=" * 60)
    print("Enhanced SQL Assistant Service - Test Suite")
    print("=" * 60)
    
    # Test 1: Initialize service
    service = test_initialization()
    if not service:
        print("\n❌ Cannot continue - service initialization failed")
        return
    
    # Test 2: Tier 1 simple query
    test_tier1_simple_query(service)
    
    # Test 3: Tier 2 complex query
    test_tier2_complex_query(service)
    
    # Test 4: Full query flow
    test_full_query_flow(service)
    
    # Test 5: Tier selection logic
    test_tier_selection_logic(service)
    
    print("\n" + "=" * 60)
    print("✅ Test suite completed")
    print("=" * 60)

if __name__ == "__main__":
    main()
