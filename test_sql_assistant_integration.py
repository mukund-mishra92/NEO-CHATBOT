"""
Test script for Integrated SQL Assistant Service
Tests the complete 6-step flow with nl_to_sql_generator priority
"""

import sys
import os

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from backend.app.services.sql_assistant_integrated import SQLAssistantService
from backend.app.models.schemas import ChatRequest, ChatbotType

def test_initialization():
    """Test 1: Service initialization"""
    print("\n" + "=" * 70)
    print("TEST 1: Service Initialization")
    print("=" * 70)
    
    try:
        service = SQLAssistantService()
        print("✅ Service initialized successfully")
        
        print(f"\n📊 Service Status:")
        print(f"   nl_to_sql_generator: {'✅ Available' if service.nl_sql_generator else '❌ Not available'}")
        print(f"   Vector store: {'✅ Available' if service.vector_store else '❌ Not available'}")
        print(f"   Chat history: {'✅ Available' if service.chat_history_service else '❌ Not available'}")
        print(f"   Classification: {'✅ Available' if service.classification_service else '❌ Not available'}")
        print(f"   Database: {'✅ Connected' if service.db_available else '❌ Not connected'}")
        
        print(f"\n⚙️ Configuration:")
        print(f"   Max retry attempts: {service.max_retry_attempts}")
        print(f"   High confidence threshold: {service.high_confidence_threshold:.0%}")
        print(f"   Acceptable confidence threshold: {service.acceptable_confidence_threshold:.0%}")
        print(f"   Session cache similarity: {service.session_cache_similarity_threshold:.0%}")
        print(f"   Available tables: {len(service.available_tables)}")
        
        return service
        
    except Exception as e:
        print(f"❌ Initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_simple_query(service):
    """Test 2: Simple query flow"""
    print("\n" + "=" * 70)
    print("TEST 2: Simple Query - 'show me all bots'")
    print("=" * 70)
    
    if not service:
        print("⚠️ Service not available, skipping test")
        return
    
    try:
        # Create chat request
        request = ChatRequest(
            message="show me all bots",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=None  # Will create new session
        )
        
        print(f"\n🔍 Processing query: {request.message}")
        print(f"\nExpected Flow:")
        print(f"   1. Check session cache (new session → NOT FOUND)")
        print(f"   2. Check classified queries (85% similarity)")
        print(f"   3. Check chat history patterns (80% similarity)")
        print(f"   4. Generate with nl_to_sql_generator (PRIORITY)")
        print(f"      - If confidence >= 94%: Use immediately")
        print(f"      - If confidence >= 75%: Use result")
        print(f"      - If confidence < 75%: Retry with feedback (max 3)")
        print(f"   5. Execute & validate")
        print(f"   6. Store in cache + JSONL + MySQL")
        
        # Process query
        response = service.process_query(request)
        
        print(f"\n📊 Response:")
        print(f"   Session ID: {response.session_id}")
        print(f"   Confidence: {response.confidence_score:.2%}")
        print(f"   Chatbot type: {response.chatbot_type}")
        
        if response.metadata:
            print(f"\n📋 Metadata:")
            for key, value in response.metadata.items():
                if key == 'sql_query':
                    print(f"   {key}: {value[:80]}...")
                else:
                    print(f"   {key}: {value}")
        
        print(f"\n💬 Response preview:")
        print(f"   {response.response[:200]}...")
        
    except Exception as e:
        print(f"❌ Query processing failed: {e}")
        import traceback
        traceback.print_exc()

def test_cache_hit(service):
    """Test 3: Cache hit with same query"""
    print("\n" + "=" * 70)
    print("TEST 3: Cache Hit - Repeat 'show me all bots'")
    print("=" * 70)
    
    if not service:
        print("⚠️ Service not available, skipping test")
        return
    
    try:
        # Create request with same session
        request = ChatRequest(
            message="show me all bots",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id="test_session_123"
        )
        
        print(f"\n🔍 First query (should generate new)...")
        response1 = service.process_query(request)
        print(f"   Confidence: {response1.confidence_score:.2%}")
        print(f"   Source: {response1.metadata.get('source', 'unknown')}")
        
        print(f"\n🔍 Second query (should hit cache)...")
        response2 = service.process_query(request)
        print(f"   Confidence: {response2.confidence_score:.2%}")
        print(f"   Source: {response2.metadata.get('source', 'unknown')}")
        
        if response2.metadata.get('source') == 'session_cache':
            print(f"\n✅ Session cache working! Similarity: {response2.metadata.get('similarity', 0):.2%}")
        else:
            print(f"\n⚠️ Expected cache hit but got: {response2.metadata.get('source')}")
        
    except Exception as e:
        print(f"❌ Cache test failed: {e}")
        import traceback
        traceback.print_exc()

def test_nl_to_sql_generator(service):
    """Test 4: Direct nl_to_sql_generator test"""
    print("\n" + "=" * 70)
    print("TEST 4: nl_to_sql_generator Direct Test")
    print("=" * 70)
    
    if not service:
        print("⚠️ Service not available, skipping test")
        return
    
    if not service.nl_sql_generator:
        print("⚠️ nl_to_sql_generator not available")
        print("   Required file: data/database/Table_information.csv")
        return
    
    try:
        print(f"\n🤖 Testing nl_to_sql_generator directly...")
        
        question = "how many active bots are there"
        sql, confidence, metadata = service._generate_sql_with_nl_generator(question)
        
        if sql:
            print(f"✅ Generated SQL successfully")
            print(f"   SQL: {sql}")
            print(f"   Confidence: {confidence:.2%}")
            print(f"   Tables used: {metadata.get('tables_used', [])}")
            print(f"   Is read-only: {metadata.get('is_read_only', True)}")
            
            if metadata.get('warnings'):
                print(f"   ⚠️ Warnings: {metadata['warnings']}")
        else:
            print(f"❌ No SQL generated")
            print(f"   Error: {metadata.get('error', 'unknown')}")
        
    except Exception as e:
        print(f"❌ nl_to_sql_generator test failed: {e}")
        import traceback
        traceback.print_exc()

def main():
    """Run all tests"""
    print("\n" + "=" * 70)
    print("INTEGRATED SQL ASSISTANT SERVICE - TEST SUITE")
    print("=" * 70)
    print("\nThis will test the complete 6-step flow:")
    print("1. Session cache")
    print("2. Classified queries")
    print("3. Chat history patterns")
    print("4. nl_to_sql_generator (PRIORITY) + retry + LLM fallback")
    print("5. Execute & validate")
    print("6. Store for reuse")
    
    # Test 1: Initialization
    service = test_initialization()
    
    if not service:
        print("\n❌ Cannot proceed with tests - service initialization failed")
        return
    
    # Test 2: Simple query
    test_simple_query(service)
    
    # Test 3: Cache hit
    test_cache_hit(service)
    
    # Test 4: nl_to_sql_generator
    test_nl_to_sql_generator(service)
    
    print("\n" + "=" * 70)
    print("TEST SUITE COMPLETED")
    print("=" * 70)
    print("\n📝 Next Steps:")
    print("   1. Check logs for detailed flow information")
    print("   2. Verify Table_information.csv exists for nl_to_sql_generator")
    print("   3. Update route imports to use sql_assistant_integrated")
    print("   4. Test with real queries from your application")
    print()

if __name__ == "__main__":
    main()
