"""Test the entity-aware similarity matching"""
from difflib import SequenceMatcher

def calculate_similarity_old(query1: str, query2: str) -> float:
    """Old version - pure character matching"""
    return SequenceMatcher(None, query1.lower(), query2.lower()).ratio()

def calculate_similarity_new(query1: str, query2: str) -> float:
    """New version - entity-aware matching"""
    q1_lower = query1.lower()
    q2_lower = query2.lower()
    
    # Define key entities that should NOT be confused
    entity_groups = [
        ['bot', 'bots', 'robot', 'robots'],
        ['station', 'stations', 'workstation', 'workstations'],
        ['wave', 'waves', 'batch', 'batches'],
        ['bin', 'bins', 'tote', 'totes', 'container'],
        ['order', 'orders', 'sku', 'skus', 'article', 'articles'],
        ['alarm', 'alarms', 'alert', 'alerts', 'error', 'errors'],
    ]
    
    # Check if queries mention different entities
    q1_entities = set()
    q2_entities = set()
    
    for group in entity_groups:
        for entity in group:
            if entity in q1_lower:
                q1_entities.add(group[0])  # Use first word as canonical form
            if entity in q2_lower:
                q2_entities.add(group[0])
    
    # If both queries mention entities but they're DIFFERENT, return 0
    if q1_entities and q2_entities and q1_entities != q2_entities:
        print(f"   ❌ Entity mismatch: {q1_entities} vs {q2_entities} - returning 0%")
        return 0.0
    
    # Otherwise use character-level similarity
    return SequenceMatcher(None, q1_lower, q2_lower).ratio()

# Test cases
test_cases = [
    ("how many stations we have in this setup", "how many bots we have in this setup"),
    ("how many stations we have", "how many stations are there"),
    ("show me bot 7 position", "show me bot 8 position"),
    ("count all active bots", "count all disabled bots"),
    ("what waves are running", "what stations are running"),
    ("show alarm logs", "show error logs"),
]

print("="*80)
print("ENTITY-AWARE SIMILARITY TEST")
print("="*80)

for q1, q2 in test_cases:
    old_sim = calculate_similarity_old(q1, q2)
    new_sim = calculate_similarity_new(q1, q2)
    
    print(f"\nQuery 1: {q1}")
    print(f"Query 2: {q2}")
    print(f"Old similarity: {old_sim:.2%} (threshold: 85%)")
    print(f"New similarity: {new_sim:.2%}")
    
    if old_sim >= 0.85 and new_sim < 0.85:
        print(f"✅ FIXED: Would have matched incorrectly, now correctly rejected")
    elif old_sim < 0.85 and new_sim >= 0.85:
        print(f"⚠️ ISSUE: Would not have matched, now matches")
    elif old_sim >= 0.85 and new_sim >= 0.85:
        print(f"✅ MATCH: Both old and new correctly match")
    else:
        print(f"✅ NO MATCH: Both old and new correctly reject")

print("\n" + "="*80)
