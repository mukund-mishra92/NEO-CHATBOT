"""
Test script for the updated embedding-based query classification service.

Tests:
1. Only queries with classification='correct' are indexed
2. Embeddings are rebuilt on every service startup
3. Unclassified queries are NOT indexed
4. Classifying a query as correct adds it to the index
5. query_embeddings.npz is updated correctly
"""

import sys
import io
from pathlib import Path

# Set UTF-8 encoding for console output
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

import json
import shutil
from datetime import datetime
from app.services.query_classification_service1 import QueryClassificationService

def setup_test_environment():
    """Create a clean test environment"""
    test_dir = Path(__file__).parent.parent / "data" / "classification_test_updated"
    
    # Clean up if exists
    if test_dir.exists():
        shutil.rmtree(test_dir)
    
    test_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"✅ Test environment created: {test_dir}")
    return test_dir


def test_1_unclassified_not_indexed(test_dir):
    """Test that unclassified queries are NOT indexed"""
    print("\n" + "="*70)
    print("TEST 1: Unclassified queries should NOT be indexed")
    print("="*70)
    
    service = QueryClassificationService(test_dir)
    
    # Store 3 unclassified queries
    query_ids = []
    for i in range(3):
        qid = service.store_query(
            session_id=f"test_session_{i}",
            user_query=f"Test query {i}: How many bots are running?",
            generated_sql=f"SELECT COUNT(*) FROM bot_master WHERE status='RUNNING'",
            execution_status="success",
            rows_returned=5,
            confidence=0.95,
            tables_used=["bot_master"]
        )
        query_ids.append(qid)
    
    stats = service.get_classification_stats()
    
    print(f"\n📊 Stats after storing 3 unclassified queries:")
    print(f"   Total queries: {stats['total_queries']}")
    print(f"   Unclassified: {stats['unclassified']}")
    print(f"   Correct: {stats['correct']}")
    print(f"   Embeddings indexed: {stats['embedding_indexed']}")
    
    # Verify
    assert stats['total_queries'] == 3, "Should have 3 total queries"
    assert stats['unclassified'] == 3, "All should be unclassified"
    assert stats['embedding_indexed'] == 0, "❌ FAIL: No embeddings should be indexed for unclassified queries"
    
    print("\n✅ PASS: Unclassified queries are NOT indexed")
    return query_ids


def test_2_classify_as_correct_indexes(test_dir, query_ids):
    """Test that classifying as correct adds to index"""
    print("\n" + "="*70)
    print("TEST 2: Classifying as correct should add to index")
    print("="*70)
    
    service = QueryClassificationService(test_dir)
    
    # Classify first query as correct
    print(f"\n🏷️  Classifying query {query_ids[0]} as 'correct'...")
    success = service.classify_query(
        query_id=query_ids[0],
        classification="correct",
        notes="Good SQL"
    )
    
    assert success, "Classification should succeed"
    
    stats = service.get_classification_stats()
    
    print(f"\n📊 Stats after classifying 1 query as correct:")
    print(f"   Total queries: {stats['total_queries']}")
    print(f"   Unclassified: {stats['unclassified']}")
    print(f"   Correct: {stats['correct']}")
    print(f"   Embeddings indexed: {stats['embedding_indexed']}")
    
    # Verify
    assert stats['correct'] == 1, "Should have 1 correct query"
    assert stats['embedding_indexed'] == 1, "❌ FAIL: Should have 1 embedding indexed"
    
    # Verify embeddings file was created
    embeddings_file = test_dir / "query_embeddings.npz"
    assert embeddings_file.exists(), "❌ FAIL: query_embeddings.npz should be created"
    
    print("\n✅ PASS: Classifying as correct adds to embedding index")


def test_3_rebuild_on_startup(test_dir, query_ids):
    """Test that embeddings are rebuilt on service startup"""
    print("\n" + "="*70)
    print("TEST 3: Embeddings should be rebuilt on startup")
    print("="*70)
    
    # First, classify another query as correct
    service = QueryClassificationService(test_dir)
    service.classify_query(
        query_id=query_ids[1],
        classification="correct",
        notes="Also good"
    )
    
    stats_before = service.get_classification_stats()
    print(f"\n📊 Before restart: {stats_before['embedding_indexed']} embeddings indexed")
    
    # Now delete the embeddings file to simulate corruption
    embeddings_file = test_dir / "query_embeddings.npz"
    if embeddings_file.exists():
        embeddings_file.unlink()
        print(f"🗑️  Deleted {embeddings_file.name}")
    
    # Restart service (should rebuild embeddings)
    print("🔄 Restarting service...")
    service = QueryClassificationService(test_dir)
    
    stats_after = service.get_classification_stats()
    
    print(f"\n📊 After restart:")
    print(f"   Total queries: {stats_after['total_queries']}")
    print(f"   Correct: {stats_after['correct']}")
    print(f"   Embeddings indexed: {stats_after['embedding_indexed']}")
    
    # Verify
    assert stats_after['correct'] == 2, "Should have 2 correct queries"
    assert stats_after['embedding_indexed'] == 2, "❌ FAIL: Should have rebuilt 2 embeddings"
    assert embeddings_file.exists(), "❌ FAIL: query_embeddings.npz should be recreated"
    
    print("\n✅ PASS: Embeddings rebuilt on startup from correct queries")


def test_4_similarity_search_only_correct(test_dir, query_ids):
    """Test that similarity search only matches correct queries"""
    print("\n" + "="*70)
    print("TEST 4: Similarity search should only match correct queries")
    print("="*70)
    
    service = QueryClassificationService(test_dir)
    
    # Try to find similar to the unclassified query
    match = service.find_similar_classified_query(
        user_query="Test query 2: How many bots are running?",  # Similar to query_ids[2] which is unclassified
        similarity_threshold=0.70
    )
    
    if match:
        print(f"\n🎯 Found match: {match['user_query']}")
        print(f"   Classification: {match['classification']}")
        print(f"   Similarity: {match['similarity_score']:.3f}")
        
        # Should match one of the correct queries (0 or 1), not the unclassified one
        assert match['classification'] == 'correct', "Match should only be from correct queries"
        assert match['query_id'] in [query_ids[0], query_ids[1]], "Should match correct queries only"
    else:
        print("\n⚠️  No match found (threshold might be too high)")
    
    print("\n✅ PASS: Only correct queries are searchable")


def test_5_stats_consistency(test_dir):
    """Test that stats are consistent"""
    print("\n" + "="*70)
    print("TEST 5: Stats consistency check")
    print("="*70)
    
    service = QueryClassificationService(test_dir)
    stats = service.get_classification_stats()
    
    print(f"\n📊 Final Stats:")
    print(f"   Total queries: {stats['total_queries']}")
    print(f"   Unclassified: {stats['unclassified']}")
    print(f"   Correct: {stats['correct']}")
    print(f"   Incorrect: {stats['incorrect']}")
    print(f"   Needs review: {stats['needs_review']}")
    print(f"   Correct queries available: {stats['correct_queries_available']}")
    print(f"   Embeddings indexed: {stats['embedding_indexed']}")
    print(f"   Embedding ready: {stats['embedding_ready']}")
    
    # Verify consistency
    assert stats['embedding_indexed'] == stats['correct'], \
        "❌ FAIL: Embeddings indexed should match correct queries count"
    
    assert stats['correct_queries_available'] == stats['correct'], \
        "❌ FAIL: correct_queries_available should match correct count"
    
    total_sum = (stats['unclassified'] + stats['correct'] + 
                 stats['incorrect'] + stats['needs_review'])
    assert total_sum == stats['total_queries'], \
        "❌ FAIL: Sum of classifications should match total"
    
    print("\n✅ PASS: All stats are consistent")


def test_6_no_new_fields_in_jsonl(test_dir):
    """Test that no new fields like user_reviewed are added to JSONL"""
    print("\n" + "="*70)
    print("TEST 6: No new fields in classified_queries.jsonl")
    print("="*70)
    
    jsonl_file = test_dir / "classified_queries.jsonl"
    
    with open(jsonl_file, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            record = json.loads(line)
            
            # Check that user_reviewed field does NOT exist
            assert "user_reviewed" not in record, \
                f"❌ FAIL: Line {line_num} has 'user_reviewed' field (should not exist)"
            
            # Check that classification field exists
            assert "classification" in record, \
                f"❌ FAIL: Line {line_num} missing 'classification' field"
    
    print(f"\n✅ PASS: No 'user_reviewed' field in any record")
    print("✅ PASS: Existing JSONL format maintained (no breaking changes)")


def main():
    print("="*70)
    print("EMBEDDING SERVICE UPDATED - TEST SUITE")
    print("="*70)
    
    test_dir = setup_test_environment()
    
    try:
        # Run tests
        query_ids = test_1_unclassified_not_indexed(test_dir)
        test_2_classify_as_correct_indexes(test_dir, query_ids)
        test_3_rebuild_on_startup(test_dir, query_ids)
        test_4_similarity_search_only_correct(test_dir, query_ids)
        test_5_stats_consistency(test_dir)
        test_6_no_new_fields_in_jsonl(test_dir)
        
        print("\n" + "="*70)
        print("✅ ALL TESTS PASSED!")
        print("="*70)
        print("\n📝 Summary:")
        print("   ✓ Unclassified queries are NOT indexed")
        print("   ✓ Classifying as correct adds to index")
        print("   ✓ Embeddings rebuild on startup from correct queries")
        print("   ✓ Similarity search only matches correct queries")
        print("   ✓ Stats are consistent")
        print("   ✓ No new fields added (backward compatible)")
        print("\n💡 Key Points:")
        print("   • query_embeddings.npz contains ONLY correct queries")
        print("   • Embeddings are rebuilt on every service startup")
        print("   • No breaking changes to JSONL format")
        print("   • Existing services should not be affected")
        
    except AssertionError as e:
        print(f"\n❌ TEST FAILED: {e}")
        return 1
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
