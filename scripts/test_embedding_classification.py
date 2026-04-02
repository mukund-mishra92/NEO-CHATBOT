"""
Test script for embedding-based query classification service

This script tests:
1. Embedding model loading
2. Semantic similarity detection
3. Comparison with SequenceMatcher approach
4. Performance with different query variations
"""

import sys
from pathlib import Path
import time

# Add backend to path
backend_path = Path(__file__).parent.parent / "backend"
sys.path.insert(0, str(backend_path))

from app.services.query_classification_service_embedding import QueryClassificationServiceEmbedding
from difflib import SequenceMatcher


def test_embedding_model():
    """Test if embedding model loads correctly"""
    print("=" * 80)
    print("TEST 1: Embedding Model Loading")
    print("=" * 80)
    
    try:
        from sentence_transformers import SentenceTransformer
        print("✅ sentence-transformers library is installed")
        
        model = SentenceTransformer("all-MiniLM-L6-v2")
        print("✅ all-MiniLM-L6-v2 model loaded successfully")
        
        # Test encoding
        test_text = ["How many bots are active?"]
        embeddings = model.encode(test_text)
        print(f"✅ Encoding works - Shape: {embeddings.shape}")
        
        return True
    except ImportError as e:
        print(f"❌ Import error: {e}")
        print("Run: pip install sentence-transformers")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_semantic_similarity():
    """Test semantic similarity vs SequenceMatcher"""
    print("\n" + "=" * 80)
    print("TEST 2: Semantic Similarity Comparison")
    print("=" * 80)
    
    # Test cases that should be semantically similar but textually different
    test_cases = [
        {
            "query1": "How many bots are running now?",
            "query2": "What is the count of active bots?",
            "expected": "HIGH similarity (semantic match)",
        },
        {
            "query1": "Show me all active stations",
            "query2": "Give me stations that are running",
            "expected": "HIGH similarity (semantic match)",
        },
        {
            "query1": "How many pick waves are active?",
            "query2": "How many put waves are active?",
            "expected": "LOW similarity (single word changes meaning)",
        },
        {
            "query1": "Show completed tasks",
            "query2": "Show pending tasks",
            "expected": "LOW similarity (opposite meaning)",
        },
        {
            "query1": "How many bots do we have?",
            "query2": "How many bots do we have?",
            "expected": "PERFECT match",
        },
    ]
    
    try:
        from sentence_transformers import SentenceTransformer
        model = SentenceTransformer("all-MiniLM-L6-v2")
        
        print("\n{:<40} {:<40} {:>12} {:>12}".format(
            "Query 1", "Query 2", "Embed Score", "SequMatch"
        ))
        print("-" * 106)
        
        for case in test_cases:
            q1, q2 = case["query1"], case["query2"]
            
            # Embedding similarity (cosine)
            vecs = model.encode([q1, q2], normalize_embeddings=True)
            embed_score = float(vecs[0].dot(vecs[1]))
            
            # SequenceMatcher similarity
            seq_score = SequenceMatcher(None, q1, q2).ratio()
            
            # Format output
            q1_short = q1[:38] + ".." if len(q1) > 40 else q1
            q2_short = q2[:38] + ".." if len(q2) > 40 else q2
            
            print("{:<40} {:<40} {:>12.3f} {:>12.3f}".format(
                q1_short, q2_short, embed_score, seq_score
            ))
            print(f"  Expected: {case['expected']}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_classification_service():
    """Test the actual QueryClassificationService"""
    print("\n" + "=" * 80)
    print("TEST 3: Classification Service Integration")
    print("=" * 80)
    
    try:
        # Use test directory
        test_storage = Path(__file__).parent.parent / "data" / "classification_test"
        test_storage.mkdir(parents=True, exist_ok=True)
        
        print(f"📁 Test storage: {test_storage}")
        
        # Initialize service
        print("\n⏳ Initializing QueryClassificationServiceEmbedding...")
        service = QueryClassificationServiceEmbedding(test_storage)
        
        print(f"✅ Service initialized")
        print(f"   - Embedding ready: {service._embedding_ready}")
        print(f"   - Queries in cache: {len(service.classified_queries_cache)}")
        
        # Store some test queries
        print("\n⏳ Storing test queries...")
        
        queries_to_store = [
            {
                "user_query": "How many bots are running now?",
                "generated_sql": "SELECT COUNT(*) FROM bot_master WHERE STATUS='RUNNING'",
                "classification": "correct",
            },
            {
                "user_query": "Show me all active stations",
                "generated_sql": "SELECT * FROM station_master WHERE STATUS='ACTIVE'",
                "classification": "correct",
            },
            {
                "user_query": "What is the count of active bots?",
                "generated_sql": "SELECT COUNT(*) FROM bot_master WHERE STATUS='ACTIVE'",
                "classification": "unclassified",
            },
        ]
        
        stored_ids = []
        for q in queries_to_store:
            query_id = service.store_query(
                session_id="test_session",
                user_query=q["user_query"],
                generated_sql=q["generated_sql"],
                execution_status="success",
                rows_returned=1,
                confidence=0.9,
                tables_used=["bot_master"],
            )
            stored_ids.append(query_id)
            print(f"   ✅ Stored: {query_id[:30]}...")
            
            # Classify the queries
            if q["classification"] == "correct":
                service.classify_query(query_id, "correct")
                print(f"      📌 Classified as: correct")
        
        # Test similarity search
        print("\n⏳ Testing similarity search...")
        
        test_query = "What is the total number of bots running?"
        print(f"\n🔍 Searching for similar queries to: '{test_query}'")
        
        match = service.find_similar_classified_query(test_query, similarity_threshold=0.80)
        
        if match:
            print(f"✅ Found similar query!")
            print(f"   Query: {match['user_query']}")
            print(f"   Similarity Score: {match['similarity_score']:.3f}")
            print(f"   SQL: {match['generated_sql'][:80]}...")
        else:
            print("❌ No similar query found above threshold")
        
        # Test with different queries
        print("\n" + "-" * 80)
        test_queries = [
            "Count of active bots",
            "How many pick waves are running?",
            "Display all stations that are active",
        ]
        
        for tq in test_queries:
            match = service.find_similar_classified_query(tq, similarity_threshold=0.80)
            if match:
                print(f"🎯 '{tq[:40]}...' → Score: {match['similarity_score']:.3f}")
            else:
                print(f"❌ '{tq[:40]}...' → No match")
        
        # Stats
        print("\n📊 Classification Stats:")
        stats = service.get_classification_stats()
        for key, value in stats.items():
            print(f"   {key}: {value}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_performance():
    """Test performance of embedding-based search"""
    print("\n" + "=" * 80)
    print("TEST 4: Performance Benchmark")
    print("=" * 80)
    
    try:
        from sentence_transformers import SentenceTransformer
        import numpy as np
        
        model = SentenceTransformer("all-MiniLM-L6-v2")
        
        # Simulate large dataset
        num_queries = 1000
        print(f"\n⏳ Generating {num_queries} sample queries...")
        
        templates = [
            "How many {} are {}?",
            "Show me all {} with status {}",
            "What is the count of {}?",
            "Get all {} where {} is {}",
        ]
        
        entities = ["bots", "stations", "tasks", "waves", "orders"]
        statuses = ["active", "running", "completed", "pending"]
        
        queries = []
        for i in range(num_queries):
            template = templates[i % len(templates)]
            if "{}" in template:
                parts = template.count("{}")
                if parts == 2:
                    query = template.format(
                        entities[i % len(entities)],
                        statuses[i % len(statuses)]
                    )
                elif parts == 1:
                    query = template.format(entities[i % len(entities)])
                else:
                    query = template.format(
                        entities[i % len(entities)],
                        entities[(i+1) % len(entities)],
                        statuses[i % len(statuses)]
                    )
                queries.append(query)
        
        print(f"✅ Generated {len(queries)} queries")
        
        # Encode all queries
        print("\n⏳ Encoding all queries...")
        start = time.time()
        embeddings = model.encode(queries, batch_size=64, show_progress_bar=False, normalize_embeddings=True)
        encode_time = time.time() - start
        print(f"✅ Encoded in {encode_time:.2f}s ({num_queries/encode_time:.0f} queries/sec)")
        
        # Test similarity search
        print("\n⏳ Testing similarity search...")
        test_query = "How many bots are active?"
        
        start = time.time()
        test_vec = model.encode([test_query], normalize_embeddings=True)[0]
        encode_time_single = time.time() - start
        
        start = time.time()
        scores = embeddings.dot(test_vec)
        best_idx = np.argmax(scores)
        search_time = time.time() - start
        
        print(f"✅ Search completed in {search_time*1000:.2f}ms")
        print(f"   Query encoding: {encode_time_single*1000:.2f}ms")
        print(f"   Similarity computation: {search_time*1000:.2f}ms")
        print(f"   Best match: '{queries[best_idx]}' (score: {scores[best_idx]:.3f})")
        
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all tests"""
    print("\n" + "=" * 80)
    print("EMBEDDING-BASED QUERY CLASSIFICATION TEST SUITE")
    print("=" * 80)
    
    results = {
        "Embedding Model Loading": test_embedding_model(),
        "Semantic Similarity": test_semantic_similarity(),
        "Classification Service": test_classification_service(),
        "Performance Benchmark": test_performance(),
    }
    
    print("\n" + "=" * 80)
    print("TEST RESULTS SUMMARY")
    print("=" * 80)
    
    for test_name, passed in results.items():
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"{test_name:.<50} {status}")
    
    all_passed = all(results.values())
    
    if all_passed:
        print("\n🎉 All tests passed!")
    else:
        print("\n⚠️  Some tests failed. Check the output above for details.")
    
    return all_passed


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
