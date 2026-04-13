"""Quick integration test for intent classifier."""
import sys
sys.path.insert(0, 'backend')
from dotenv import load_dotenv
load_dotenv()

from app.services.intent_classifier import IntentClassifier

classifier = IntentClassifier()

# Test cases covering all 3 categories
tests = [
    ('What is the throughput for today in FRK?', 'sql_assistant'),
    ('Bot 1234 is not moving', 'semi_auto_diagnostic'),
    ('What is NEO Fleet Manager?', 'knowledge_base'),
    ('How many active bots in BLR?', 'sql_assistant'),
    ('Conveyor belt jammed at station 5', 'semi_auto_diagnostic'),
    ('Explain the bot navigation algorithm', 'knowledge_base'),
    ('hello', 'knowledge_base'),
    ('show me IPP for all bots today', 'sql_assistant'),
    ('Error code E-401 on charger station 3', 'semi_auto_diagnostic'),
    ('What is a GTC station?', 'knowledge_base'),
]

correct = 0
for query, expected in tests:
    result = classifier.classify(query)
    ok = '✅' if result['intent'] == expected else '❌'
    if result['intent'] == expected:
        correct += 1
    print(f"{ok} Query: \"{query[:60]}\"")
    print(f"   Expected: {expected} | Got: {result['intent']} (conf={result['confidence']:.2f}, method={result['method']})")

print(f"\n🎯 {correct}/{len(tests)} correct ({correct/len(tests)*100:.0f}%)")
