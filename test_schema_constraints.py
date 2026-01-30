"""
Test Schema-Driven Constraints
Validates that the system now provides binding schema constraints before SQL generation
"""

import sys
import json
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent / "backend"))

from app.services.sql_assistant_service import SQLAssistantService

def test_schema_constraints():
    """Test that schema constraints are properly generated"""
    print("=" * 80)
    print("TESTING SCHEMA-DRIVEN CONSTRAINTS")
    print("=" * 80)
    
    service = SQLAssistantService()
    
    # Test Case 1: Bot query (should provide bot_master columns and STATUS enum)
    print("\n\n📋 TEST 1: Bot Query")
    print("-" * 80)
    test_query = "show me status of bot 32"
    
    # Classify intent
    intent_info = service._classify_query_intent(test_query)
    print(f"Intent: {intent_info['intent']}")
    print(f"Entities: {intent_info['entities']}")
    
    # Extract tables
    detected_tables = service._extract_tables_from_intent(intent_info)
    print(f"\nDetected Tables: {detected_tables}")
    
    # Build constraints
    constraints = service._build_schema_constraints(detected_tables, intent_info)
    print(f"\nGenerated Constraints:")
    print(constraints)
    
    # Check for critical elements
    checks = {
        "Has table list": "ALLOWED TABLES FOR THIS QUERY" in constraints,
        "Has column list": "Allowed Columns" in constraints,
        "Has enum values": "ONLY:" in constraints,
        "Mentions STATUS": "STATUS" in constraints,
        "Has ENABLED/DISABLED": "'ENABLED'" in constraints and "'DISABLED'" in constraints,
        "Mentions BOT_ID": "BOT_ID" in constraints,
        "Warns about guessing": "DO NOT use any columns or values NOT listed" in constraints
    }
    
    print("\n✅ Constraint Validation:")
    for check, passed in checks.items():
        status = "✅" if passed else "❌"
        print(f"  {status} {check}: {passed}")
    
    # Test Case 2: Order query (should provide order table columns)
    print("\n\n📋 TEST 2: Order Query")
    print("-" * 80)
    test_query2 = "show me all orders from today"
    
    intent_info2 = service._classify_query_intent(test_query2)
    print(f"Intent: {intent_info2['intent']}")
    print(f"Entities: {intent_info2['entities']}")
    
    detected_tables2 = service._extract_tables_from_intent(intent_info2)
    print(f"\nDetected Tables: {detected_tables2}")
    
    constraints2 = service._build_schema_constraints(detected_tables2, intent_info2)
    
    # Check order-specific constraints
    order_checks = {
        "Has table list": "ALLOWED TABLES" in constraints2,
        "Mentions order-related table": any(word in constraints2.lower() for word in ['order', 'wms_to_wcs']),
        "Has binding message": "YOU MUST ONLY use" in constraints2
    }
    
    print("\n✅ Order Constraint Validation:")
    for check, passed in order_checks.items():
        status = "✅" if passed else "❌"
        print(f"  {status} {check}: {passed}")
    
    # Test Case 3: Metadata query (should skip constraints - no data query)
    print("\n\n📋 TEST 3: Metadata Query (should have minimal constraints)")
    print("-" * 80)
    test_query3 = "show me columns in bot_master table"
    
    intent_info3 = service._classify_query_intent(test_query3)
    print(f"Intent: {intent_info3['intent']}")
    print(f"Is metadata query: {intent_info3['is_metadata_query']}")
    
    detected_tables3 = service._extract_tables_from_intent(intent_info3)
    print(f"\nDetected Tables: {detected_tables3}")
    
    constraints3 = service._build_schema_constraints(detected_tables3, intent_info3)
    print(f"Constraints (should be present even for metadata): {len(constraints3)} chars")
    
    # Summary
    print("\n\n" + "=" * 80)
    print("📊 SUMMARY")
    print("=" * 80)
    
    all_passed = all(checks.values()) and all(order_checks.values())
    
    if all_passed:
        print("✅ ALL TESTS PASSED!")
        print("\n🎯 Schema-driven constraints are now ACTIVE:")
        print("  • LLM receives BINDING constraints before generation")
        print("  • Allowed tables, columns, and enum values explicitly listed")
        print("  • No more guessing column names or status values")
        print("  • Reactive validation → Proactive schema-driven generation")
    else:
        print("❌ SOME TESTS FAILED")
        print("Review the constraint generation logic")
    
    return all_passed

if __name__ == "__main__":
    try:
        success = test_schema_constraints()
        exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
