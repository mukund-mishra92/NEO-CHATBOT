"""
Test server startup with refactored services
Quick test to ensure server can initialize without errors
"""

import sys
import os

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

print("=" * 80)
print("TESTING SERVER STARTUP")
print("=" * 80)

try:
    print("\n[1/5] Importing FastAPI app...")
    from backend.app.main import app
    print("✅ FastAPI app imported successfully")
    
    print("\n[2/5] Checking service imports...")
    from backend.app.services import DiagnosticSupportService, SQLAssistantService
    print("✅ Services imported successfully")
    
    print("\n[3/5] Testing service initialization...")
    diagnostic_service = DiagnosticSupportService()
    print(f"✅ DiagnosticSupportService initialized")
    
    sql_service = SQLAssistantService()
    print(f"✅ SQLAssistantService initialized")
    
    print("\n[4/5] Checking API routes...")
    routes = [route.path for route in app.routes]
    print(f"✅ {len(routes)} routes registered")
    
    # Check key routes exist
    key_routes = ['/api/chat', '/api/diagnostic-support/search']
    for route in key_routes:
        if any(route in r for r in routes):
            print(f"  ✓ {route}")
    
    print("\n[5/5] Verifying service methods...")
    # Test diagnostic methods
    assert hasattr(diagnostic_service, 'search_issue'), "Missing search_issue method"
    assert hasattr(diagnostic_service, 'start_diagnostic_session'), "Missing start_diagnostic_session method"
    
    # Test SQL assistant methods
    assert hasattr(sql_service, 'process_query'), "Missing process_query method"
    assert hasattr(sql_service, 'get_available_tables'), "Missing get_available_tables method"
    
    print("✅ All service methods present")
    
    print("\n" + "=" * 80)
    print("✅ SERVER STARTUP TEST: PASSED")
    print("=" * 80)
    print("\nServer is ready to start! Run:")
    print("  uvicorn backend.app.main:app --reload")
    print()
    
except Exception as e:
    print(f"\n❌ SERVER STARTUP TEST: FAILED")
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
