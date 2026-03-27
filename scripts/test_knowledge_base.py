"""
Test Knowledge Base Service
Query the knowledge base with sample questions
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

import logging
from app.modules.neo_chatbot.services.knowledge_base_service import KnowledgeBaseService
from app.modules.neo_chatbot.models.schemas import ChatRequest, ChatbotType
import uuid

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def test_query(kb_service: KnowledgeBaseService, question: str):
    """Test a single query"""
    print("\n" + "=" * 80)
    print(f"❓ QUESTION: {question}")
    print("=" * 80)
    
    request = ChatRequest(
        message=question,
        chatbot_type=ChatbotType.KNOWLEDGE_BASE,
        session_id=str(uuid.uuid4())
    )
    
    response = kb_service.process_query(request)
    
    print(f"\n💬 ANSWER:")
    print(response.response)
    
    if response.sources:
        print(f"\n📚 SOURCES ({len(response.sources)}):")
        for i, source in enumerate(response.sources, 1):
            print(f"\n{i}. {source.document_name}")
            print(f"   Relevance: {source.relevance_score:.2%}")
            print(f"   Type: {source.document_type}")
            print(f"   Snippet: {source.content_snippet[:200]}...")
    
    if response.confidence_score:
        print(f"\n🎯 Confidence: {response.confidence_score:.1%}")
    
    print("\n" + "=" * 80)


def main():
    """Main function"""
    print("\n" + "=" * 80)
    print("NEO KNOWLEDGE BASE - INTERACTIVE TEST")
    print("=" * 80)
    
    # Initialize service
    print("\n🔧 Initializing Knowledge Base Service...")
    kb_service = KnowledgeBaseService()
    
    # Check if vector store has documents
    doc_count = len(kb_service.vector_store.documents)
    print(f"📚 Vector store contains {doc_count} document chunks")
    
    if doc_count == 0:
        print("\n⚠️ WARNING: No documents found in vector store!")
        print("Please run document ingestion first:")
        print("  python app/modules/neo_chatbot/scripts/ingest_documents.py")
        return
    
    print(f"✅ Ready to answer questions!\n")
    
    # Test questions
    test_questions = [
        "What is the NEO ASRS system?",
        "How do I operate the dashboard?",
        "What are the safety procedures?",
        "Tell me about bin management",
        "How to handle maintenance tasks?"
    ]
    
    print("\n" + "=" * 80)
    print("🧪 AUTOMATED TESTS")
    print("=" * 80)
    
    for question in test_questions:
        test_query(kb_service, question)
    
    # Interactive mode
    print("\n" + "=" * 80)
    print("💬 INTERACTIVE MODE")
    print("=" * 80)
    print("Type your questions (or 'quit' to exit)\n")
    
    while True:
        try:
            question = input("\n❓ Your question: ").strip()
            
            if not question:
                continue
            
            if question.lower() in ['quit', 'exit', 'q']:
                print("\n👋 Goodbye!")
                break
            
            test_query(kb_service, question)
        
        except KeyboardInterrupt:
            print("\n\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"\n❌ Error: {e}")


if __name__ == "__main__":
    main()
