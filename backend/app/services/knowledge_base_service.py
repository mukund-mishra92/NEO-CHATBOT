"""
Knowledge Base Service - Document Q&A using RAG (Retrieval-Augmented Generation)
Answers questions about NEO documentation, code, and proposals
"""

import logging
import re
import uuid
from typing import List, Dict, Any, Optional
from pathlib import Path

from .llm_service import LLMService
from .vector_store_service import VectorStoreService
from .rlhf_service import RLHFService
from .diagnostic_support_service import DiagnosticSupportService
from ..models.schemas import ChatRequest, ChatResponse, SourceDocument, ChatbotType, MessageRole
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class KnowledgeBaseService:
    """
    Service for Knowledge Base Chatbot
    Uses RAG to answer questions about NEO documentation
    """
    
    def __init__(self):
        """Initialize knowledge base service"""
        self.llm_service = LLMService()
        self.vector_store = VectorStoreService()
        self.rlhf_service = RLHFService()
        self.diagnostic_service = DiagnosticSupportService()  # Add diagnostic support
        self.session_manager = get_session_manager()
        
        self.system_prompt = """You are NEO Assistant, an expert on the NEO Warehouse Management System.

Your knowledge base includes:
- NEO system documentation and user manuals
- Technical specifications and proposals
- **C# codebase** from NEO Fleet Manager (classes, methods, implementations)
- Code examples and implementations
- Standard Operating Procedures (SOPs)
- Safety guidelines and best practices
- **Diagnostic Support Database** - Real troubleshooting solutions for bot and station issues

Response Guidelines:
1. **Structure your answers clearly** with headings and sections
2. **Use formatting** - bullet points, numbered lists, bold/italic for emphasis
3. **Be specific and accurate** - cite document/file names when referencing information
4. **Provide context** - explain technical terms when needed
5. **Be concise yet comprehensive** - break complex topics into digestible parts
6. **Include code examples** when relevant - show actual implementation details
7. **For code queries**: Explain the code's purpose, key methods, and how it fits in the system
8. **For troubleshooting**: Check diagnostic database first for known issues and solutions
9. **If information is incomplete**, clearly state what's missing
9. **Use professional tone** - helpful, clear, and authoritative

Formatting Standards:
- Use **bold** for key terms, class names, and section headers
- Use bullet points (•) or numbered lists for multi-item information
- Use line breaks between sections for readability
- Include relevant document/file references in [brackets]
- Use code blocks (```csharp, ```python) for code snippets
- For code answers: Show class name, method signatures, and key logic

Code Response Format:
When answering code questions, structure your response as:
1. **What it does**: Brief overview
2. **Location**: File path and class name
3. **Key Methods/Properties**: List important members
4. **Implementation Details**: Show relevant code snippets
5. **Usage Example**: How to use/call this code
6. **Related Components**: What other classes/methods it interacts with

Always prioritize clarity and user understanding."""

        logger.info("✅ Knowledge Base Service initialized")
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process user query using RAG (Retrieval-Augmented Generation)
        
        Steps:
        1. Get or create session for conversation memory
        2. Classify query type (factual, generative, conversational, unanswerable)
        3. Generate embedding for user query
        4. Search vector store for relevant documents
        5. Build adaptive context based on query type
        6. Generate response with appropriate strategy
        7. Store conversation in session
        
        Args:
            chat_request: User's chat request
            
        Returns:
            Chat response with answer and sources
        """
        try:
            logger.info(f"🔍 Processing knowledge base query: {chat_request.message[:50]}...")
            
            # Step 1: Get or create session
            session_id = chat_request.session_id
            if not session_id or not self.session_manager.get_session(session_id):
                session_id = self.session_manager.create_session(
                    session_type=SessionType.KNOWLEDGE_BASE,
                    initial_message=chat_request.message
                )
                logger.info(f"🆕 Created new Knowledge Base session: {session_id}")
            else:
                # Add user message to existing session
                self.session_manager.add_message(session_id, 'user', chat_request.message)
            
            # Check if vector store has documents
            if len(self.vector_store.documents) == 0:
                return self._handle_empty_knowledge_base(chat_request)
            
            # Step 2: Check if this is a troubleshooting query
            is_troubleshooting = self._is_troubleshooting_query(chat_request.message)
            if is_troubleshooting:
                logger.info("🔧 Detected troubleshooting query, checking diagnostic database...")
                diagnostic_result = self._handle_diagnostic_query(chat_request)
                if diagnostic_result:
                    # Add assistant response to session
                    self.session_manager.add_message(session_id, 'assistant', diagnostic_result.response)
                    return diagnostic_result
            
            # Step 3: Classify query type for adaptive response strategy
            query_type = self._classify_query(chat_request.message)
            logger.info(f"📊 Query classified as: {query_type}")
            
            # Step 4: Generate query embedding
            query_embedding = self.llm_service.generate_embedding(chat_request.message)
            
            # Step 5: Search for relevant documents (with balanced category distribution)
            search_results = self.vector_store.search_balanced(
                query_embedding=query_embedding,
                top_k=8,  # Retrieve more documents for better context
                filter_metadata=chat_request.context,
                min_similarity=0.25,  # Lower threshold to catch more relevant content
                diversify=True  # Reduce proposal bias
            )
            
            # Filter and re-rank results
            filtered_results = self._filter_and_rerank(search_results, chat_request.message)
            
            # Step 6: Build context from retrieved documents
            context = self._build_context(filtered_results)
            source_documents = self._extract_source_documents(filtered_results)
            
            # Step 7: Get conversation history for context
            conversation_history = self.session_manager.get_context_for_llm(session_id, max_messages=10)
            
            # Step 8: Generate response using LLM with adaptive strategy
            messages = self._build_adaptive_messages(chat_request, context, query_type, conversation_history)
            
            # Adjust LLM parameters based on query type
            max_tokens, temperature = self._get_llm_parameters(query_type)
            
            response_text = self.llm_service.generate_response(
                messages=messages,
                system_prompt=self._get_adaptive_system_prompt(query_type),
                max_tokens=max_tokens,
                temperature=temperature
            )
            
            # Format response based on query type
            response_text = self._format_adaptive_response(response_text, query_type)
            
            # Step 9: Add assistant response to session
            self.session_manager.add_message(
                session_id, 
                'assistant', 
                response_text,
                metadata={
                    'query_type': query_type,
                    'source_count': len(source_documents),
                    'sources': [doc.document_name for doc in source_documents[:3]]
                }
            )
            
            # Calculate confidence based on source relevance
            confidence = self._calculate_confidence(filtered_results)
            
            # Record for RLHF learning
            try:
                self.rlhf_service.record_feedback(
                    chatbot_type="knowledge_base",
                    query=chat_request.message,
                    response=response_text,
                    feedback_type="neutral",  # Auto-logged on generation
                    rating=None,
                    comment=f"Auto-generated ({query_type} query)",
                    metadata={
                        "query_type": query_type,
                        "confidence": confidence,
                        "source_count": len(source_documents),
                        "document_names": [doc.document_name for doc in source_documents[:3]]
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to record RLHF feedback: {e}")
            
            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=source_documents,
                confidence_score=confidence,
                suggested_actions=self._generate_suggested_actions(chat_request.message)
            )
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"❌ Error processing knowledge base query: {error_msg}", exc_info=True)
            logger.error(f"Query was: {chat_request.message}")
            logger.error(f"Error type: {type(e).__name__}")
            return ChatResponse(
                response=f"I apologize, but I encountered an error while processing your question. Error: {error_msg}. Please try rephrasing or contact support.",
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=[],
                confidence_score=0.0
            )
    
    def _classify_query(self, query: str) -> str:
        """
        Classify query type to determine response strategy
        
        Types:
        - SIMPLE_FACT: Simple factual questions (What is X? How many? When?)
        - DEFINITION: Asking for definition/explanation (What does X mean?)
        - PROCEDURAL: How-to questions requiring steps (How to X?)
        - COMPARISON: Comparing multiple things (X vs Y, difference between)
        - EXPLORATORY: Open-ended exploration (Tell me about X)
        - GENERATIVE: Creating new content (Generate/Create/Write)
        - UNANSWERABLE: Questions outside knowledge base scope
        """
        query_lower = query.lower().strip()
        
        # Simple fact queries (short answers)
        simple_fact_patterns = [
            r'^what is (the |a )?(\w+)\??$',  # "What is X?"
            r'^how many\b',  # "How many..."
            r'^when (was|is|did)\b',  # "When..."
            r'^where (is|are)\b',  # "Where..."
            r'^who (is|are)\b',  # "Who..."
            r'^which\b',  # "Which..."
            r'^(yes|no),?\s',  # Yes/No questions
            r'\?(yes|no)\??$',  # Ending with yes/no
        ]
        
        for pattern in simple_fact_patterns:
            if re.search(pattern, query_lower):
                return "SIMPLE_FACT"
        
        # Code-related queries
        code_patterns = [
            r'\bclass\b', r'\bmethod\b', r'\bfunction\b', r'\bcode\b',
            r'\bimplementation\b', r'\bcontroller\b', r'\bservice\b',
            r'\b(show|find|get|display)\s+(me\s+)?(the\s+)?code\b',
            r'\bhow\s+is\s+\w+\s+(implemented|coded|written)\b',
            r'\bsource\s+code\b', r'\b\.cs\b', r'\bc#\b'
        ]
        
        for pattern in code_patterns:
            if re.search(pattern, query_lower):
                return "CODE_QUERY"
        
        # Definition queries
        if any(phrase in query_lower for phrase in [
            "what does", "define", "definition of", "meaning of", "what is meant by"
        ]):
            return "DEFINITION"
        
        # Procedural queries (step-by-step)
        if any(phrase in query_lower for phrase in [
            "how to", "how do i", "how can i", "steps to", "procedure for", 
            "process of", "way to", "method to"
        ]):
            return "PROCEDURAL"
        
        # Comparison queries
        if any(phrase in query_lower for phrase in [
            " vs ", " versus ", "difference between", "compare", "comparison",
            "better than", "advantages of", "disadvantages of"
        ]):
            return "COMPARISON"
        
        # Generative queries (cannot be answered from docs)
        if any(phrase in query_lower for phrase in [
            "generate", "create a", "write a", "make a", "design a",
            "develop a", "build me", "give me a new"
        ]):
            return "GENERATIVE"
        
        # Exploratory queries (detailed explanations)
        if any(phrase in query_lower for phrase in [
            "tell me about", "explain", "describe", "overview of",
            "information about", "details about", "all about"
        ]):
            return "EXPLORATORY"
        
        # Default to exploratory for longer queries
        return "EXPLORATORY" if len(query.split()) > 5 else "SIMPLE_FACT"
    
    def _get_adaptive_system_prompt(self, query_type: str) -> str:
        """Get system prompt based on query type"""
        
        base_prompt = """You are NEO Assistant, an expert on the NEO Warehouse Management System.

CRITICAL FORMATTING RULES:
- DO NOT use emoji or special characters in citations
- Put ALL source citations at the END in a 'Sources:' line
- DO NOT cite sources inline with [Document 1], [Document 2] etc
- Use clean markdown: ## for headings, - for bullets, **bold** for emphasis
- Add blank lines between sections for readability
"""
        
        if query_type == "SIMPLE_FACT":
            return base_prompt + """

TASK: Provide a direct, concise answer in 1-3 sentences.

RULES:
- Answer directly without unnecessary context
- No lengthy explanations unless asked
- No forced formatting with sections
- If it's a yes/no question, start with yes or no
- Cite the document source in [brackets] at the end

Example:
Q: "What is NEO?"
A: "NEO is an Automated Storage and Retrieval System (ASRS) that uses autonomous robots to store and retrieve bins efficiently. [NEO System Documentation]"
"""
        
        elif query_type == "DEFINITION":
            return base_prompt + """

TASK: Provide a clear definition followed by brief context.

FORMAT:
**Definition:** [Clear, concise definition in 1-2 sentences]

**Context:** [Brief explanation of why it matters or how it's used - 2-3 sentences]

[Source: Document name]
"""
        
        elif query_type == "PROCEDURAL":
            return base_prompt + """

TASK: Provide step-by-step instructions.

FORMAT:
**How to [Task]:**

1. [First step]
2. [Second step]
3. [Continue...]

**Important Notes:**
• [Any warnings or prerequisites]
• [Special considerations]

[Source: Document name]
"""
        
        elif query_type == "COMPARISON":
            return base_prompt + """

TASK: Provide a structured comparison.

FORMAT:
**Key Differences:**

| Aspect | Option A | Option B |
|--------|----------|----------|
| [Feature] | [Detail] | [Detail] |

**Summary:** [Which is better for what use case]

[Source: Document name]
"""
        
        elif query_type == "CODE_QUERY":
            return base_prompt + """

TASK: Provide detailed code information with context.

FORMAT:
**📁 File:** [Filename and path if available]

**📝 Purpose:** [What this code does - 1-2 sentences]

**🔧 Key Components:**
• **Class:** [ClassName]
• **Methods:** [List important methods]
• **Properties:** [Key properties if relevant]

**💻 Implementation:**
```csharp
[Show relevant code snippet - focus on key logic]
```

**📋 Explanation:**
[Explain what the code does step by step]

**🔗 Related Components:**
[What other classes/services this interacts with]

**💡 Usage Example:**
[How to use or call this code if applicable]

[Source: Filename]
"""
        
        elif query_type == "GENERATIVE":
            return base_prompt + """

TASK: Explain that you cannot generate new content, but can help with existing documentation.

RESPONSE STRATEGY:
1. Politely explain you can only provide information from existing documentation
2. Offer to share relevant examples/templates from the docs
3. Suggest what specific information you CAN provide

Be helpful, not rigid. Offer alternatives.
"""
        
        else:  # EXPLORATORY
            return base_prompt + """

TASK: Provide a comprehensive, well-structured explanation.

FORMAT:
**Overview**
[2-3 sentence summary]

**Key Points**
• [Main point 1]
• [Main point 2]
• [Main point 3]

**Additional Details**
[Relevant specifics, examples, or context]

**Source References**
[Document names]
"""
    
    def _get_llm_parameters(self, query_type: str) -> tuple:
        """Get max_tokens and temperature based on query type"""
        
        params = {
            "SIMPLE_FACT": (300, 0.2),      # Short, focused
            "DEFINITION": (500, 0.3),       # Medium, precise
            "PROCEDURAL": (1000, 0.3),      # Detailed, structured
            "COMPARISON": (800, 0.3),       # Analytical
            "GENERATIVE": (400, 0.5),       # Helpful redirection
            "EXPLORATORY": (1500, 0.4),     # Comprehensive
        }
        
        return params.get(query_type, (1000, 0.4))
    
    def _build_adaptive_messages(self, chat_request: ChatRequest, context: str, query_type: str, conversation_history: List[Dict[str, str]] = None) -> List[Dict[str, str]]:
        """Build messages with adaptive prompting based on query type, with conversation context FIRST"""
        messages = []
        
        # ========================================
        # STEP 1: Add conversation history FIRST for context
        # This ensures LLM understands the ongoing conversation
        # ========================================
        context_instruction = ""
        if conversation_history and len(conversation_history) > 1:
            # Build a context summary from previous messages
            history_parts = []
            for msg in conversation_history[-8:-1]:  # Last 7 messages, excluding current
                role = msg.get('role', 'unknown').upper()
                content = msg.get('content', '')
                # Summarize long content
                if len(content) > 300:
                    content = content[:300] + "..."
                history_parts.append(f"[{role}]: {content}")
            
            if history_parts:
                context_instruction = f"""
╔══════════════════════════════════════════════════════════════════════════════╗
║  📚 CONVERSATION HISTORY - YOU MUST CONSIDER THIS CONTEXT!                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
{chr(10).join(history_parts)}

⚠️ CRITICAL: This is a CONTINUING CONVERSATION. Build upon previous answers!
"""
                # Add as a system-like message at the start
                messages.append({
                    "role": "user",
                    "content": context_instruction
                })
                messages.append({
                    "role": "assistant", 
                    "content": "I understand. I'll consider our previous conversation when answering your next question."
                })
        
        # ========================================
        # STEP 2: Build query-specific prompt
        # ========================================
        if query_type == "SIMPLE_FACT":
            user_message = f"""Documentation:
{context}

Question: {chat_request.message}

Provide a direct, concise answer in 1-3 sentences. No extra formatting."""
        
        elif query_type == "GENERATIVE":
            user_message = f"""Documentation Available:
{context}

User Request: {chat_request.message}

The user is asking you to GENERATE/CREATE new content. You cannot do this.

Instead:
1. Politely explain you can only reference existing documentation
2. Offer relevant examples or templates from the documentation
3. Ask what specific information from existing docs would be helpful

Be conversational and helpful, not robotic."""
        
        else:
            user_message = f"""Documentation:
{context}

Question: {chat_request.message}

Provide a clear, well-structured answer using the documentation. Follow the response format for {query_type} queries."""
        
        messages.append({
            "role": "user",
            "content": user_message
        })
        
        return messages
    
    def _format_adaptive_response(self, response_text: str, query_type: str) -> str:
        """Format response based on query type"""
        
        # Minimal formatting for simple facts
        if query_type == "SIMPLE_FACT":
            # Just clean up extra newlines
            response_text = re.sub(r'\n{2,}', '\n', response_text)
            return response_text.strip()
        
        # Standard formatting for others
        response_text = re.sub(r'\n{3,}', '\n\n', response_text)
        response_text = response_text.strip()
        
        return response_text
    
    def _handle_empty_knowledge_base(self, chat_request: ChatRequest) -> ChatResponse:
        """Handle case when no documents are in knowledge base"""
        return ChatResponse(
            response="""I don't have any documents in my knowledge base yet. 

To enable document Q&A:
1. Place your documentation files (PDF, DOCX, TXT) in: app/modules/neo_chatbot/data/documents/
2. Run the document ingestion process to index them
3. Then I'll be able to answer questions about your documentation!

Currently I can still help with:
- Database queries (SQL Assistant)
- System diagnostics and troubleshooting
- General NEO system questions (with limited context)

What would you like help with?""",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            session_id=chat_request.session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            suggested_actions=["Add documents to knowledge base", "Try SQL Assistant", "Ask about diagnostics"]
        )
    
    def _build_context(self, search_results: List[Dict[str, Any]]) -> str:
        """Build context string from search results with improved formatting"""
        if not search_results:
            return "No relevant documentation found."
        
        context_parts = []
        for i, result in enumerate(search_results, 1):
            doc = result["document"]
            filename = doc['metadata'].get('filename', 'Unknown')
            category = doc['metadata'].get('category', 'Unknown')
            similarity = result['similarity']
            content = doc['content']
            
            # Include more content for high-relevance documents
            max_length = 800 if similarity > 0.5 else 500
            content_preview = content[:max_length]
            if len(content) > max_length:
                content_preview += "..."
            
            context_parts.append(f"""
[Document {i}] {filename}
Category: {category} | Relevance: {similarity:.1%}

{content_preview}
{'─' * 80}
""")
        
        return "\n".join(context_parts)
    
    def _filter_and_rerank(self, search_results: List[Dict[str, Any]], query: str) -> List[Dict[str, Any]]:
        """Filter and re-rank search results based on query relevance"""
        if not search_results:
            return []
        
        # Filter out very low similarity results
        filtered = [r for r in search_results if r['similarity'] > 0.2]
        
        # Re-rank by combining similarity with keyword matching
        query_keywords = set(query.lower().split())
        
        for result in filtered:
            content_lower = result['document']['content'].lower()
            keyword_matches = sum(1 for kw in query_keywords if kw in content_lower)
            
            # Boost score if content has many query keywords
            keyword_boost = min(keyword_matches * 0.05, 0.15)
            result['boosted_similarity'] = min(result['similarity'] + keyword_boost, 1.0)
        
        # Sort by boosted similarity
        filtered.sort(key=lambda x: x.get('boosted_similarity', x['similarity']), reverse=True)
        
        # Return top 5 most relevant
        return filtered[:5]
    
    def _extract_source_documents(self, search_results: List[Dict[str, Any]]) -> List[SourceDocument]:
        """Extract source documents from search results"""
        sources = []
        for result in search_results:
            doc = result["document"]
            sources.append(SourceDocument(
                document_name=doc['metadata'].get('filename', 'Unknown'),
                content_snippet=doc['content'][:200] + "..." if len(doc['content']) > 200 else doc['content'],
                relevance_score=result['similarity'],
                page_number=doc['metadata'].get('page_number'),
                document_type=doc['metadata'].get('category', 'unknown')
            ))
        return sources
    
    def _calculate_confidence(self, search_results: List[Dict[str, Any]]) -> float:
        """Calculate confidence score based on search results quality"""
        if not search_results:
            return 0.0
        
        # Weighted confidence calculation
        # - Top result has most weight
        # - Consider number of high-quality results
        # - Penalize if only low-similarity results
        
        similarities = [r.get('boosted_similarity', r['similarity']) for r in search_results]
        
        if not similarities:
            return 0.0
        
        # Weight top results more heavily
        weights = [0.4, 0.3, 0.2, 0.1][:len(similarities)]
        weights.extend([0.05] * (len(similarities) - len(weights)))
        
        weighted_score = sum(s * w for s, w in zip(similarities, weights))
        
        # Boost confidence if we have multiple high-quality results
        high_quality_count = sum(1 for s in similarities if s > 0.5)
        quality_boost = min(high_quality_count * 0.05, 0.15)
        
        final_confidence = min(weighted_score + quality_boost, 1.0)
        
        return round(final_confidence, 2)
    
    def _generate_suggested_actions(self, query: str) -> List[str]:
        """Generate contextual suggested follow-up actions"""
        suggestions = []
        
        query_lower = query.lower()
        
        # Installation/Setup queries
        if any(word in query_lower for word in ["install", "setup", "configure", "deployment"]):
            suggestions.extend([
                "View system requirements and prerequisites",
                "Check step-by-step installation guide",
                "See configuration examples and best practices"
            ])
        
        # Error/Troubleshooting queries
        elif any(word in query_lower for word in ["error", "issue", "problem", "fix", "troubleshoot", "not working"]):
            suggestions.extend([
                "Check common issues and solutions",
                "View diagnostic procedures",
                "Access error code reference",
                "Contact technical support"
            ])
        
        # Technical/API queries
        elif any(word in query_lower for word in ["code", "api", "function", "method", "class", "interface"]):
            suggestions.extend([
                "View API documentation",
                "See code examples and snippets",
                "Explore technical integration guides"
            ])
        
        # Bot/Automation queries
        elif any(word in query_lower for word in ["bot", "robot", "agv", "automation"]):
            suggestions.extend([
                "Learn about bot operations",
                "View bot configuration guide",
                "Check bot maintenance procedures"
            ])
        
        # Safety/SOP queries
        elif any(word in query_lower for word in ["safety", "sop", "procedure", "guideline", "protocol"]):
            suggestions.extend([
                "Review safety guidelines",
                "Check standard operating procedures",
                "View emergency protocols"
            ])
        
        # Dashboard/UI queries
        elif any(word in query_lower for word in ["dashboard", "interface", "ui", "screen", "display"]):
            suggestions.extend([
                "Explore dashboard features",
                "View user interface guide",
                "Learn about report generation"
            ])
        
        # Default suggestions
        else:
            suggestions.extend([
                "Explore related documentation",
                "View practical examples",
                "Check getting started guide",
                "Ask about specific features"
            ])
        
        return suggestions[:4]  # Limit to 4 suggestions
        
        return suggestions[:3]
    
    def add_document(
        self,
        filename: str,
        content: str,
        category: str,
        additional_metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Add document to knowledge base
        
        Args:
            filename: Document filename
            content: Document text content
            category: Document category (documentation, code, proposal, support)
            additional_metadata: Additional metadata
            
        Returns:
            Success status
        """
        try:
            # Generate unique document ID
            doc_id = str(uuid.uuid4())
            
            # Generate embedding
            embedding = self.llm_service.generate_embedding(content)
            
            # Prepare metadata
            metadata = {
                "filename": filename,
                "category": category,
                **(additional_metadata or {})
            }
            
            # Add to vector store
            self.vector_store.add_document(
                document_id=doc_id,
                content=content,
                embedding=embedding,
                metadata=metadata
            )
            
            logger.info(f"✅ Added document to knowledge base: {filename}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error adding document to knowledge base: {e}")
            return False
    
    def _is_troubleshooting_query(self, query: str) -> bool:
        """Detect if query is asking for troubleshooting help"""
        troubleshooting_keywords = [
            'error', 'issue', 'problem', 'stuck', 'not working', 'failed', 'stopped',
            'unable to', 'cannot', 'can\'t', 'won\'t', 'troubleshoot', 'debug', 'fix',
            'alarm', 'stopped', 'bot stuck', 'station', 'lidar', 'buffer', 'maintenance',
            'e-stop', 'emergency', 'recovery', 'manual mode', 'hmi', 'teleoperation'
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in troubleshooting_keywords)
    
    def _handle_diagnostic_query(self, chat_request: ChatRequest) -> Optional[ChatResponse]:
        """Handle troubleshooting queries using diagnostic database"""
        try:
            # Search diagnostic database
            matches = self.diagnostic_service.search_issue(
                query=chat_request.message,
                issue_type=None  # Search both BOT and STATION level
            )
            
            if not matches:
                return None  # Fall back to normal RAG
            
            # Take top 3 matches
            top_matches = matches[:3]
            
            # Build diagnostic response
            response_parts = [
                "## 🔧 Diagnostic Support\n",
                f"I found {len(top_matches)} known solution(s) for similar issues:\n"
            ]
            
            for i, match in enumerate(top_matches, 1):
                severity_emoji = "🔴" if match['severity'].lower() == "high" else "🟡" if match['severity'].lower() == "medium" else "🟢"
                
                response_parts.append(f"\n### Solution {i}: {match['problem']}")
                response_parts.append(f"\n{severity_emoji} **Severity:** {match['severity']}")
                response_parts.append(f"\n**Type:** {match['type'].replace('_', ' ')}")
                response_parts.append(f"\n\n**Solution Steps:**")
                
                # Format solution steps
                solution_lines = match['solution'].split('.')
                for step in solution_lines:
                    step = step.strip()
                    if step:
                        response_parts.append(f"\n- {step}")
                
                # Add SQL query if available
                if match.get('sql_query') and match['sql_query'].strip():
                    response_parts.append(f"\n\n**SQL Query for Diagnosis:**")
                    response_parts.append(f"\n```sql\n{match['sql_query']}\n```")
                
                # Add developer escalation note
                if match.get('reported_to_dev', '').upper() == 'Y':
                    response_parts.append(f"\n\n⚠️ *Note: This issue may require developer attention if not resolved.*")
                
                response_parts.append("\n" + "-" * 60)
            
            # Add general advice
            response_parts.append("\n\n### 📋 General Troubleshooting Tips:")
            response_parts.append("\n1. Always check bot status and alarms first")
            response_parts.append("\n2. Verify task assignments in task_master")
            response_parts.append("\n3. Check bot communication via IP ping")
            response_parts.append("\n4. Try RECOVERY before NON-RECOVERY")
            response_parts.append("\n5. Document the issue for future reference")
            
            response_text = "".join(response_parts)
            
            # Create source documents from matches
            sources = [
                SourceDocument(
                    document_name=f"Diagnostic DB - {match['type']}",
                    content_snippet=match['problem'][:200],
                    relevance_score=match['relevance_score'] / 100.0,
                    page_number=match['id'],
                    document_type="diagnostic"
                )
                for match in top_matches
            ]
            
            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=sources,
                confidence_score=0.95,  # High confidence for exact matches
                suggested_actions=[
                    "Show me SQL queries for bot diagnostics",
                    "What are common station-level issues?",
                    "How do I use HMI teleoperation mode?"
                ]
            )
            
        except Exception as e:
            logger.error(f"❌ Error in diagnostic query handling: {e}", exc_info=True)
            return None  # Fall back to normal RAG
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get knowledge base statistics"""
        stats = self.vector_store.get_statistics()
        stats["llm_provider"] = self.llm_service.get_provider_info()
        return stats

