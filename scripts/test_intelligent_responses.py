"""
Test Intelligent Response Adaptation
Shows how the Knowledge Base responds to different query types
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from app.modules.neo_chatbot.services.knowledge_base_service import KnowledgeBaseService
from app.modules.neo_chatbot.models.schemas import ChatRequest, ChatbotType

# Initialize service
kb_service = KnowledgeBaseService()

# Test different query types
test_queries = {
    "SIMPLE_FACT": [
        "What is NEO?",
        "How many bots are in the system?",
        "What is ASRS?",
        "When was NEO deployed?",
    ],
    
    "DEFINITION": [
        "What does ASRS mean?",
        "Define NEObot",
        "What is meant by velocity scoring?",
    ],
    
    "PROCEDURAL": [
        "How to configure the NEO system?",
        "How do I set up bot charging?",
        "Steps to troubleshoot bot errors",
    ],
    
    "COMPARISON": [
        "Difference between NEObot and traditional AGV",
        "NEO vs manual warehouse",
        "Compare different bot types",
    ],
    
    "EXPLORATORY": [
        "Tell me about the NEO ASRS system",
        "Explain how the dashboard works",
        "Overview of safety procedures",
    ],
    
    "GENERATIVE": [
        "Generate a new techno-commercial offer for Zepto",
        "Create a proposal for Amazon",
        "Write a maintenance schedule",
    ],
}

print("=" * 80)
print("INTELLIGENT RESPONSE TESTING")
print("=" * 80)

for query_type, queries in test_queries.items():
    print(f"\n{'=' * 80}")
    print(f"QUERY TYPE: {query_type}")
    print(f"{'=' * 80}\n")
    
    for query in queries[:2]:  # Test first 2 of each type
        print(f"\nQUERY: {query}")
        print("-" * 80)
        
        # Classify query
        classified_type = kb_service._classify_query(query)
        print(f"Classified as: {classified_type}")
        
        # Get LLM parameters
        max_tokens, temperature = kb_service._get_llm_parameters(classified_type)
        print(f"Parameters: max_tokens={max_tokens}, temperature={temperature}")
        
        print()

print("\n" + "=" * 80)
print("RESPONSE STRATEGY SUMMARY")
print("=" * 80)

strategies = {
    "SIMPLE_FACT": "Direct answer in 1-3 sentences, no extra formatting",
    "DEFINITION": "Clear definition + brief context",
    "PROCEDURAL": "Step-by-step numbered instructions",
    "COMPARISON": "Structured table or side-by-side comparison",
    "EXPLORATORY": "Comprehensive explanation with sections",
    "GENERATIVE": "Polite refusal + offer relevant examples from docs",
}

for query_type, strategy in strategies.items():
    print(f"\n{query_type}:")
    print(f"  Strategy: {strategy}")

print("\n" + "=" * 80)
print("✅ Test complete! Restart Flask to see these in action.")
print("=" * 80)
